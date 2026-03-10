/**
 * Main social posting pipeline.
 *
 * Orchestrates: read note → generate text → post to platforms → embed → push.
 *
 * Each platform posting task is expressed as an async function that returns
 * an EmbedSection on success or null on failure. The tasks run in parallel
 * via Promise.allSettled, making platform failures independent.
 *
 * @module pipeline
 */

import fs from "node:fs";
import path from "node:path";

import type {
  EnvironmentConfig,
  EmbedSection,
  ReflectionData,
} from "./types.ts";
import {
  TWITTER_HANDLE,
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  BLUESKY_MAX_LENGTH,
  MASTODON_SECTION_HEADER,
  MASTODON_MAX_LENGTH,
} from "./types.ts";
import { PipelineTimer } from "./timer.ts";
import { calculateTweetLength, countGraphemes, fitPostToLimit } from "./text.ts";
import { readNote } from "./frontmatter.ts";
import { generateTweetWithGemini } from "./gemini.ts";
import { validateEnvironment, getYesterdayDate } from "./env.ts";
import { buildTweetSection, buildBlueskySection, buildMastodonSection } from "./embed-section.ts";
import { syncObsidianVault, pushObsidianVault } from "./obsidian-sync.ts";

// Platform imports
import { postTweet, getEmbedHtml } from "./platforms/twitter.ts";
import {
  postToBluesky,
  extractBlueskyDid, extractBlueskyPostId, buildBlueskyPostUrl,
  getBlueskyEmbedHtml,
} from "./platforms/bluesky.ts";
import { postToMastodon, getMastodonEmbedHtml } from "./platforms/mastodon.ts";
import { fetchOgMetadata } from "./platforms/og-metadata.ts";

// --- Platform Posting Tasks ---

type PostingTask = () => Promise<EmbedSection | null>;

const createTwitterTask = (
  env: EnvironmentConfig,
  postText: string,
  date: string,
): PostingTask => async () => {
  try {
    console.log(`🐦 Posting tweet to Twitter...`);
    const tweet = await postTweet(postText, env.twitter!);
    console.log(`✅ Tweet posted: https://twitter.com/${TWITTER_HANDLE}/status/${tweet.id}`);

    console.log(`🔗 Fetching tweet embed code...`);
    const embedHtml = await getEmbedHtml(tweet.id, tweet.text, date);
    console.log(`📋 Got tweet embed HTML (${embedHtml.length} chars)`);

    return { header: TWEET_SECTION_HEADER, embedHtml, buildSection: buildTweetSection };
  } catch (error) {
    console.error(`⚠️  Twitter posting failed (non-fatal)`);
    const e = error as { code?: number; data?: unknown; rateLimit?: unknown; message?: string; stack?: string; type?: string };
    console.error(`  ⚠️ [final] ${e.code ?? "?"} ${e.message ?? "unknown error"}`);
    console.error(`🔍 Twitter API error details:`);
    console.error(`  HTTP status: ${e.code ?? "unknown"}, type: ${e.type ?? "unknown"}`);
    if (e.data) console.error(`  Response data: ${JSON.stringify(e.data, null, 2)}`);
    if (e.rateLimit) console.error(`  Rate limit: ${JSON.stringify(e.rateLimit, null, 2)}`);
    if (e.stack) console.error(`  Stack trace:\n${e.stack.split("\n").slice(0, 4).join("\n")}`);
    return null;
  }
};

const createBlueskyTask = (
  env: EnvironmentConfig,
  reflection: ReflectionData,
  postText: string,
  date: string,
): PostingTask => async () => {
  try {
    console.log(`🦋 Posting to Bluesky...`);

    console.log(`  🔍 Fetching OG metadata from ${reflection.url}...`);
    const ogMeta = await fetchOgMetadata(reflection.url);

    const linkCard = {
      uri: reflection.url,
      title: ogMeta.title || reflection.title,
      description: ogMeta.description || `Daily reflection from bagrounds.org — ${reflection.date}`,
      thumbUrl: ogMeta.imageUrl,
    };

    if (ogMeta.description) {
      console.log(`  📋 OG description: ${ogMeta.description.slice(0, 80)}...`);
    }
    if (ogMeta.imageUrl) {
      console.log(`  🖼️ OG image found: ${ogMeta.imageUrl}`);
    }

    const blueskyText = fitPostToLimit(postText, BLUESKY_MAX_LENGTH);
    if (blueskyText !== postText) {
      console.log(`  ✂️ Bluesky: trimmed post from ${countGraphemes(postText)} to ${countGraphemes(blueskyText)} graphemes`);
    }

    const bskyPost = await postToBluesky(blueskyText, env.bluesky!, linkCard);
    const did = extractBlueskyDid(bskyPost.uri);
    const postId = extractBlueskyPostId(bskyPost.uri);
    console.log(`✅ Bluesky post created: ${buildBlueskyPostUrl(did, postId)}`);

    console.log(`🔗 Fetching Bluesky embed code...`);
    const embedHtml = await getBlueskyEmbedHtml(
      bskyPost.uri, bskyPost.text, date, env.bluesky!.identifier, bskyPost.cid,
    );
    console.log(`📋 Got Bluesky embed HTML (${embedHtml.length} chars)`);

    return { header: BLUESKY_SECTION_HEADER, embedHtml, buildSection: buildBlueskySection };
  } catch (error) {
    console.error(`⚠️  Bluesky posting failed (non-fatal):`);
    console.error(`   ${error instanceof Error ? error.message : error}`);
    if (error instanceof Error && error.stack) {
      console.error(`   Stack: ${error.stack.split("\n").slice(0, 3).join("\n   ")}`);
    }
    return null;
  }
};

const createMastodonTask = (
  env: EnvironmentConfig,
  postText: string,
  date: string,
): PostingTask => async () => {
  try {
    console.log(`🐘 Posting to Mastodon...`);

    const mastodonText = fitPostToLimit(postText, MASTODON_MAX_LENGTH);
    if (mastodonText !== postText) {
      console.log(`  ✂️ Mastodon: trimmed post from ${countGraphemes(postText)} to ${countGraphemes(mastodonText)} graphemes`);
    }

    const mastodonPost = await postToMastodon(mastodonText, env.mastodon!);
    console.log(`✅ Mastodon post created: ${mastodonPost.url}`);

    console.log(`🔗 Fetching Mastodon embed code...`);
    const embedHtml = await getMastodonEmbedHtml(mastodonPost.url, mastodonPost.text, date);
    console.log(`📋 Got Mastodon embed HTML (${embedHtml.length} chars)`);

    return { header: MASTODON_SECTION_HEADER, embedHtml, buildSection: buildMastodonSection };
  } catch (error) {
    console.error(`⚠️  Mastodon posting failed (non-fatal):`);
    console.error(`   ${error instanceof Error ? error.message : error}`);
    if (error instanceof Error && error.stack) {
      console.error(`   Stack: ${error.stack.split("\n").slice(0, 3).join("\n   ")}`);
    }
    return null;
  }
};

/**
 * Collect posting tasks for all configured platforms that haven't been posted yet.
 *
 * This is a declarative, data-driven approach: each platform is represented
 * as a configuration tuple, and tasks are created by mapping over the
 * configurations that pass their guard conditions.
 */
const collectPostingTasks = (
  env: EnvironmentConfig,
  reflection: ReflectionData,
  postText: string,
  date: string,
): PostingTask[] => {
  const platformConfigs: Array<{
    name: string;
    enabled: boolean;
    alreadyPosted: boolean;
    createTask: () => PostingTask;
  }> = [
    {
      name: "Twitter",
      enabled: !!env.twitter,
      alreadyPosted: reflection.hasTweetSection,
      createTask: () => createTwitterTask(env, postText, date),
    },
    {
      name: "Bluesky",
      enabled: !!env.bluesky,
      alreadyPosted: reflection.hasBlueskySection,
      createTask: () => createBlueskyTask(env, reflection, postText, date),
    },
    {
      name: "Mastodon",
      enabled: !!env.mastodon,
      alreadyPosted: reflection.hasMastodonSection,
      createTask: () => createMastodonTask(env, postText, date),
    },
  ];

  return platformConfigs
    .filter(({ enabled, alreadyPosted, name }) => {
      if (!enabled) {
        console.log(`ℹ️  ${name} credentials not configured, skipping`);
        return false;
      }
      return !alreadyPosted;
    })
    .map(({ createTask }) => createTask());
};

/**
 * Execute posting tasks in parallel and collect successful embed sections.
 */
const executePostingTasks = async (tasks: PostingTask[]): Promise<EmbedSection[]> => {
  if (tasks.length === 0) return [];

  console.log(`📡 Posting to ${tasks.length} platform(s) in parallel...`);
  const results = await Promise.allSettled(tasks.map((task) => task()));

  return results
    .filter((r): r is PromiseFulfilledResult<EmbedSection | null> => r.status === "fulfilled")
    .map((r) => r.value)
    .filter((v): v is EmbedSection => v !== null);
};

/**
 * Write embed sections to a note file and push the vault.
 */
const writeEmbedsAndPush = async (
  vaultDir: string,
  notePath: string,
  sections: EmbedSection[],
  authToken: string,
): Promise<void> => {
  const filePath = path.join(vaultDir, notePath);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Note not found in Obsidian vault: ${notePath} (looked at ${filePath})`);
  }

  let content = fs.readFileSync(filePath, "utf-8");
  let modified = false;

  for (const section of sections) {
    if (!content.includes(section.header)) {
      content = content + section.buildSection(content, section.embedHtml);
      modified = true;
    } else {
      console.log(`${section.header} already exists in Obsidian note, skipping`);
    }
  }

  if (modified) {
    fs.writeFileSync(filePath, content, "utf-8");
    await pushObsidianVault(vaultDir, { authToken });
  } else {
    console.log("No new sections to add to Obsidian note");
  }
};

// --- Argument Parsing ---

function parseArgs(): { date: string; note?: string } {
  const args = process.argv.slice(2);
  let date = getYesterdayDate();
  let note: string | undefined;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--date" && args[i + 1]) {
      date = args[i + 1] as string;
      i++;
    } else if (args[i] === "--note" && args[i + 1]) {
      note = args[i + 1] as string;
      i++;
    }
  }

  return { date, note };
}

// --- Main Pipeline ---

/**
 * Main entry point for the social posting pipeline.
 *
 * The pipeline is composed of discrete, independent phases:
 * 1. Validate environment → typed config
 * 2. Sync vault → local directory
 * 3. Read note → ReflectionData
 * 4. Generate text → post string
 * 5. Post to platforms → EmbedSection[]
 * 6. Write embeds + push vault
 */
export async function main(options?: {
  date?: string;
  note?: string;
  vaultDir?: string;
}): Promise<void> {
  const timer = new PipelineTimer();
  const date = options?.date || getYesterdayDate();
  const notePath = options?.note;
  const obsidianNotePath = notePath || `reflections/${date}.md`;

  console.log(`📄 Processing: ${obsidianNotePath}`);

  const env = validateEnvironment();

  if (!env.twitter && !env.bluesky && !env.mastodon) {
    console.warn(`⚠️  No social platform credentials configured. Set TWITTER_*, BLUESKY_*, or MASTODON_* env vars.`);
  }

  let vaultDir = options?.vaultDir || null;
  if (!vaultDir) {
    console.log(`📥 Pulling Obsidian vault (source of truth)...`);
    vaultDir = await timer.time("obsidian-pull", () => syncObsidianVault(env.obsidian));
  }

  const reflection = readNote(obsidianNotePath, vaultDir);
  if (!reflection) {
    console.log(`ℹ️  Note not found in Obsidian vault: ${obsidianNotePath}, exiting`);
    return;
  }

  console.log(`📄 Found: ${reflection.title}`);

  const allSectionsExist = reflection.hasTweetSection && reflection.hasBlueskySection && reflection.hasMastodonSection;
  if (allSectionsExist) {
    console.log(`ℹ️  Note already has all social platform sections, skipping`);
    return;
  }
  console.log(`🔍 Section check — tweet: ${reflection.hasTweetSection}, bluesky: ${reflection.hasBlueskySection}, mastodon: ${reflection.hasMastodonSection}`);

  const postText = await timer.time("gemini-generate", async () => {
    console.log(`🤖 Generating post with ${env.gemini.model}...`);
    const text = await generateTweetWithGemini(reflection, env.gemini.apiKey, env.gemini.model);
    console.log(`📝 Generated post (${calculateTweetLength(text)} chars):\n${text}`);
    return text;
  });

  const embedSections = await timer.time("social-posting", async () => {
    const tasks = collectPostingTasks(env, reflection, postText, date);
    return executePostingTasks(tasks);
  });

  if (embedSections.length > 0 && vaultDir) {
    console.log(`📝 Writing ${embedSections.length} embed section(s) to Obsidian note: ${obsidianNotePath}`);
    await timer.time("obsidian-write-push", () =>
      writeEmbedsAndPush(vaultDir!, obsidianNotePath, embedSections, env.obsidian.authToken),
    );
    console.log(`✅ Obsidian vault updated via Headless Sync (review in Obsidian and publish)`);
  } else if (embedSections.length === 0) {
    console.log(`ℹ️  No successful posts to embed`);
  }

  console.log(`🎉 Done processing ${notePath || `reflection for ${date}`}`);
  timer.printSummary();
}

// --- Entry Point ---

const isMainModule = process.argv[1]?.endsWith("tweet-reflection.ts");
if (isMainModule) {
  const { date, note } = parseArgs();
  main({ date, note }).catch((error) => {
    console.error(`❌ Error: ${error instanceof Error ? error.message : error}`);
    if (error instanceof Error && error.stack) {
      console.error(`Stack trace:\n${error.stack}`);
    }
    const e = error as { code?: number; data?: unknown; rateLimit?: unknown };
    if (e.code) console.error(`HTTP status code: ${e.code}`);
    if (e.data) console.error(`Response data: ${JSON.stringify(e.data, null, 2)}`);
    if (e.rateLimit) console.error(`Rate limit: ${JSON.stringify(e.rateLimit, null, 2)}`);
    process.exit(1);
  });
}
