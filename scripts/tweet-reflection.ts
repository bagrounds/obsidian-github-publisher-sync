/**
 * Tweet Reflection Automation Script
 *
 * Reads yesterday's reflection from the repo, generates a tweet via Gemini,
 * posts it to Twitter, fetches the embed code, and writes the updated note
 * back to the Obsidian vault via Obsidian Headless Sync.
 *
 * The user reviews the change in Obsidian and publishes it to this repo
 * via the Enveloppe plugin (one-way sync: Obsidian → GitHub).
 *
 * Usage:
 *   npx tsx scripts/tweet-reflection.ts [--date YYYY-MM-DD] [--dry-run]
 *
 * Environment variables:
 *   TWITTER_API_KEY       - OAuth 1.0a Consumer Key (from X Developer Portal → Keys and Tokens)
 *   TWITTER_API_SECRET    - OAuth 1.0a Consumer Secret
 *   TWITTER_ACCESS_TOKEN  - OAuth 1.0a Access Token (generated with Read+Write permissions)
 *   TWITTER_ACCESS_SECRET - OAuth 1.0a Access Token Secret
 *   GEMINI_API_KEY        - Google Gemini API key (from Google AI Studio)
 *   GEMINI_MODEL          - (Optional) Gemini model name, defaults to gemma-3-27b-it
 *   OBSIDIAN_AUTH_TOKEN   - Obsidian account auth token (from `ob login`)
 *   OBSIDIAN_VAULT_NAME   - Remote vault name or ID in Obsidian Sync
 *   OBSIDIAN_VAULT_PASSWORD - (Optional) E2EE vault password, if vault uses end-to-end encryption
 *
 * @see https://github.com/PLhery/node-twitter-api-v2 — twitter-api-v2 docs
 * @see https://ai.google.dev/gemini-api/docs — Google Gemini API docs
 * @see https://help.obsidian.md/sync/headless — Obsidian Headless Sync docs
 * @see https://github.com/obsidianmd/obsidian-headless — obsidian-headless CLI
 * @see https://developer.x.com/en/docs/twitter-api — X/Twitter API v2 docs
 */

import fs from "node:fs";
import path from "node:path";
import { execFile as execFileCb } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFileCb);

// --- Types ---

export interface ReflectionData {
  /** The date string YYYY-MM-DD */
  date: string;
  /** Full title from frontmatter */
  title: string;
  /** URL from frontmatter */
  url: string;
  /** Raw markdown body (after frontmatter) */
  body: string;
  /** Full file path */
  filePath: string;
  /** Whether a tweet section already exists */
  hasTweetSection: boolean;
}

export interface TweetResult {
  /** Tweet ID returned by Twitter */
  id: string;
  /** Full tweet text that was posted */
  text: string;
}

export interface EmbedResult {
  /** HTML embed code */
  html: string;
}

// --- Constants ---

const CONTENT_DIR = path.join(process.cwd(), "content", "reflections");
const TWITTER_HANDLE = "bagrounds";
const TWITTER_DISPLAY_NAME = "Bryan Grounds";
const TWEET_SECTION_HEADER = "## 🐦 Tweet";
/** Twitter counts all URLs as 23 characters */
const TWITTER_URL_LENGTH = 23;
const TWITTER_MAX_LENGTH = 280;
/** Default Gemini model — Gemma 3 27B has a generous free tier (14,400 RPD) */
const DEFAULT_GEMINI_MODEL = "gemma-3-27b-it";

// --- Reflection File Operations ---

/**
 * Get the file path for a reflection by date.
 */
export function getReflectionPath(
  date: string,
  contentDir: string = CONTENT_DIR,
): string {
  return path.join(contentDir, `${date}.md`);
}

/**
 * Parse frontmatter from a markdown string.
 * Returns the frontmatter key-value pairs and the body after frontmatter.
 */
export function parseFrontmatter(content: string): {
  frontmatter: Record<string, string>;
  body: string;
} {
  const frontmatter: Record<string, string> = {};
  const lines = content.split("\n");

  if (lines[0]?.trim() !== "---") {
    return { frontmatter, body: content };
  }

  let endIndex = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i]?.trim() === "---") {
      endIndex = i;
      break;
    }
    const match = lines[i]?.match(/^(\w+):\s*(.*)$/);
    if (match) {
      const key = match[1] as string;
      const value = match[2] as string;
      frontmatter[key] = value.replace(/^["']|["']$/g, "");
    }
  }

  const body = endIndex >= 0 ? lines.slice(endIndex + 1).join("\n") : content;
  return { frontmatter, body };
}

/**
 * Read and parse a reflection file.
 */
export function readReflection(
  date: string,
  contentDir: string = CONTENT_DIR,
): ReflectionData | null {
  const filePath = getReflectionPath(date, contentDir);

  if (!fs.existsSync(filePath)) {
    return null;
  }

  const content = fs.readFileSync(filePath, "utf-8");
  const { frontmatter, body } = parseFrontmatter(content);

  return {
    date,
    title: frontmatter["title"] || date,
    url: frontmatter["URL"] || `https://bagrounds.org/reflections/${date}`,
    body,
    filePath,
    hasTweetSection: content.includes(TWEET_SECTION_HEADER),
  };
}

/**
 * Calculate effective tweet length accounting for Twitter's t.co URL shortening.
 * URLs are always counted as 23 characters by Twitter.
 */
export function calculateTweetLength(text: string): number {
  // Match URLs in the text
  const urlRegex = /https?:\/\/[^\s]+/g;
  let length = text.length;
  const urls = text.match(urlRegex);
  if (urls) {
    for (const url of urls) {
      // Replace actual URL length with Twitter's fixed URL length
      length = length - url.length + TWITTER_URL_LENGTH;
    }
  }
  return length;
}

/**
 * Validate that tweet text is within Twitter's character limit.
 */
export function validateTweetLength(text: string): {
  valid: boolean;
  length: number;
} {
  const length = calculateTweetLength(text);
  return { valid: length <= TWITTER_MAX_LENGTH, length };
}

// --- Gemini Integration ---

/**
 * Build the prompt for Gemini to generate a tweet.
 */
export function buildGeminiPrompt(reflection: ReflectionData): {
  system: string;
  user: string;
} {
  const system = `You are a tweet writer for a personal digital garden blog at bagrounds.org.
Your job is to write a single tweet promoting today's daily reflection blog post.

Rules:
- The first line MUST be the exact reflection title: "${reflection.title}"
- The second line should be blank
- The third line should have emoji-prefixed topic tags separated by " | " (e.g. "📚 Books | 🤖 AI | 🧠 Learning")
- Extract the topic tags from the content of the reflection (books being read, videos watched, topics explored)
- The last line should be the URL: ${reflection.url}
- Keep the total tweet under 280 characters (URLs count as 23 characters)
- Do NOT use hashtags (use emoji tags instead)
- Do NOT add any commentary, just the formatted tweet
- Match the style of these examples:

Example 1:
2026-02-05 | 👥 Many ⚔️ Will 🧠 Know 🌪️ Chaos 📚📺

📚 Book Series | 🌌 Sci-Fi Exploration | ⛈️ Leadership in Turmoil | 🤖 Artificial General Intelligence | 🌌 Speculative Futures
https://bagrounds.org/reflections/2026-02-05

Example 2:
2025-12-30 | 🕷️ Charlotte's 🍼 Little 🧸 Nursery 😈 Devils 📚🌌

🕸️ Animal Fables | 🐑 Children's Verse | 🧸 Rhyme Collections | 👿 Fictional Characters | 🖼️ Creative Expression
https://bagrounds.org/reflections/2025-12-30`;

  const user = `Write a tweet for this reflection:

Title: ${reflection.title}
URL: ${reflection.url}
Date: ${reflection.date}

Content:
${reflection.body.slice(0, 1500)}`;

  return { system, user };
}

/**
 * Generate tweet text using Google Gemini API.
 */
export async function generateTweetWithGemini(
  reflection: ReflectionData,
  apiKey: string,
  modelName: string = DEFAULT_GEMINI_MODEL,
): Promise<string> {
  const { GoogleGenerativeAI } = await import("@google/generative-ai");
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: modelName,
  });

  const prompt = buildGeminiPrompt(reflection);

  const result = await model.generateContent({
    contents: [
      {
        role: "user",
        parts: [{ text: `${prompt.system}\n\n${prompt.user}` }],
      },
    ],
  });

  const text = result.response.text().trim();

  // Validate length
  const { valid, length } = validateTweetLength(text);
  if (!valid) {
    throw new Error(
      `Generated tweet exceeds 280 characters (${length} effective chars). Tweet: ${text}`,
    );
  }

  return text;
}

// --- Retry Utility ---

/** HTTP status codes that indicate a transient server error worth retrying. */
const TRANSIENT_HTTP_CODES = new Set([429, 502, 503, 504]);

/**
 * Retry an async operation with exponential backoff for transient errors.
 * Only retries when the error has an HTTP `code` in TRANSIENT_HTTP_CODES.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  {
    maxRetries = 3,
    baseDelayMs = 1000,
    onRetry,
  }: {
    maxRetries?: number;
    baseDelayMs?: number;
    onRetry?: (error: unknown, attempt: number, delayMs: number) => void;
  } = {},
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err: unknown) {
      lastError = err;
      const code =
        typeof err === "object" && err !== null && "code" in err
          ? (err as { code: number }).code
          : undefined;

      if (attempt < maxRetries && code !== undefined && TRANSIENT_HTTP_CODES.has(code)) {
        const delayMs = baseDelayMs * 2 ** attempt;
        onRetry?.(err, attempt + 1, delayMs);
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      } else {
        throw err;
      }
    }
  }
  /* istanbul ignore next — unreachable, but satisfies TypeScript */
  throw lastError;
}

// --- Twitter Integration ---

/**
 * Post a tweet using the Twitter API v2.
 * Retries on transient HTTP errors (429, 502, 503, 504) with exponential backoff.
 */
export async function postTweet(
  text: string,
  credentials: {
    apiKey: string;
    apiSecret: string;
    accessToken: string;
    accessSecret: string;
  },
): Promise<TweetResult> {
  const { TwitterApi } = await import("twitter-api-v2");
  const client = new TwitterApi({
    appKey: credentials.apiKey,
    appSecret: credentials.apiSecret,
    accessToken: credentials.accessToken,
    accessSecret: credentials.accessSecret,
  });

  const { data } = await withRetry(() => client.v2.tweet(text), {
    onRetry: (err, attempt, delayMs) => {
      const code = (err as { code?: number }).code;
      console.warn(
        `⚠️ Twitter API returned ${code}, retry ${attempt}/3 after ${delayMs}ms...`,
      );
    },
  });

  return {
    id: data.id,
    text: data.text ?? text,
  };
}

/**
 * Delete a tweet (used for test cleanup).
 */
export async function deleteTweet(
  tweetId: string,
  credentials: {
    apiKey: string;
    apiSecret: string;
    accessToken: string;
    accessSecret: string;
  },
): Promise<void> {
  const { TwitterApi } = await import("twitter-api-v2");
  const client = new TwitterApi({
    appKey: credentials.apiKey,
    appSecret: credentials.apiSecret,
    accessToken: credentials.accessToken,
    accessSecret: credentials.accessSecret,
  });

  await client.v2.deleteTweet(tweetId);
}

// --- oEmbed Integration ---

/**
 * Fetch tweet embed HTML from Twitter's oEmbed API.
 */
export async function fetchOEmbed(
  tweetUrl: string,
  options: { theme?: string } = {},
): Promise<EmbedResult> {
  const theme = options.theme || "dark";
  const params = new URLSearchParams({
    url: tweetUrl,
    theme,
    omit_script: "false",
  });

  const response = await fetch(`https://publish.twitter.com/oembed?${params}`);

  if (!response.ok) {
    throw new Error(
      `oEmbed API returned ${response.status}: ${response.statusText}`,
    );
  }

  const data = (await response.json()) as { html: string };
  return { html: data.html };
}

/**
 * Generate embed HTML locally as a fallback when oEmbed is unavailable.
 */
export function generateLocalEmbed(
  tweetId: string,
  tweetText: string,
  date: string,
): string {
  // HTML-encode the tweet text
  const htmlText = tweetText
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/\n/g, "<br>");

  // Format the date for display
  const dateObj = new Date(date + "T00:00:00Z");
  const monthNames = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  const displayDate = `${monthNames[dateObj.getUTCMonth()]} ${dateObj.getUTCDate()}, ${dateObj.getUTCFullYear()}`;

  return (
    `<blockquote class="twitter-tweet" data-theme="dark">` +
    `<p lang="en" dir="ltr">${htmlText}</p>` +
    `&mdash; ${TWITTER_DISPLAY_NAME} (@${TWITTER_HANDLE}) ` +
    `<a href="https://twitter.com/${TWITTER_HANDLE}/status/${tweetId}?ref_src=twsrc%5Etfw">${displayDate}</a>` +
    `</blockquote> ` +
    `<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>`
  );
}

/**
 * Get embed HTML, trying oEmbed first, then falling back to local generation.
 */
export async function getEmbedHtml(
  tweetId: string,
  tweetText: string,
  date: string,
): Promise<string> {
  const tweetUrl = `https://twitter.com/${TWITTER_HANDLE}/status/${tweetId}`;

  try {
    const { html } = await fetchOEmbed(tweetUrl, { theme: "dark" });
    return html;
  } catch (error) {
    console.warn(`oEmbed API failed, using local embed generation: ${error}`);
    return generateLocalEmbed(tweetId, tweetText, date);
  }
}

// --- File Update Operations ---

/**
 * Build the tweet section content to append to a note.
 * Handles separator logic: ensures a blank line before the section.
 */
export function buildTweetSection(
  existingContent: string,
  embedHtml: string,
): string {
  const separator = existingContent.endsWith("\n") ? "\n" : "\n\n";
  return `${separator}${TWEET_SECTION_HEADER}  \n${embedHtml}`;
}

/**
 * Append the tweet section to a local reflection file (used in tests).
 */
export function appendTweetSection(filePath: string, embedHtml: string): void {
  const content = fs.readFileSync(filePath, "utf-8");

  if (content.includes(TWEET_SECTION_HEADER)) {
    console.log("Tweet section already exists, skipping update");
    return;
  }

  fs.writeFileSync(filePath, content + buildTweetSection(content, embedHtml), "utf-8");
}

// --- Obsidian Headless Sync Integration ---

/**
 * Run the `ob` CLI command with arguments.
 * Uses OBSIDIAN_AUTH_TOKEN for non-interactive authentication.
 *
 * @see https://help.obsidian.md/sync/headless
 * @see https://github.com/obsidianmd/obsidian-headless
 */
export async function runObCommand(
  args: string[],
  options: { cwd?: string; env?: Record<string, string> } = {},
): Promise<{ stdout: string; stderr: string }> {
  const env = { ...process.env, ...options.env };
  try {
    const { stdout, stderr } = await execFileAsync("ob", args, {
      cwd: options.cwd,
      env,
    });
    return { stdout, stderr };
  } catch (error) {
    const err = error as Error & { stdout?: string; stderr?: string };
    throw new Error(
      [
        `Command: ob ${args.join(" ")}`,
        `Error: ${err.message}`,
        err.stdout ? `Stdout: ${err.stdout}` : null,
        err.stderr ? `Stderr: ${err.stderr}` : null,
      ]
        .filter(Boolean)
        .join("\n"),
    );
  }
}

/**
 * Set up and sync an Obsidian vault to a local directory using Headless Sync.
 * Pulls the latest vault content from Obsidian Sync.
 *
 * @returns The local vault path where files were synced
 */
export async function syncObsidianVault(credentials: {
  authToken: string;
  vaultName: string;
  vaultPassword?: string;
}): Promise<string> {
  const vaultDir = path.join(
    process.env.RUNNER_TEMP || "/tmp",
    `obsidian-vault-${process.pid}-${Date.now()}`,
  );
  fs.mkdirSync(vaultDir, { recursive: true });

  const env: Record<string, string> = {
    OBSIDIAN_AUTH_TOKEN: credentials.authToken,
  };

  // Set up the vault for syncing
  const setupArgs = [
    "sync-setup",
    "--vault",
    credentials.vaultName,
    "--path",
    vaultDir,
  ];
  if (credentials.vaultPassword) {
    setupArgs.push("--password", credentials.vaultPassword);
  }

  console.log(`🔧 Setting up Obsidian Sync for vault: ${credentials.vaultName}`);
  await runObCommand(setupArgs, { env });

  // Pull latest content
  console.log(`📥 Pulling latest vault content...`);
  await runObCommand(["sync", "--path", vaultDir], { env });

  return vaultDir;
}

/**
 * Push local changes back to the Obsidian vault via Headless Sync.
 */
export async function pushObsidianVault(
  vaultDir: string,
  credentials: { authToken: string },
): Promise<void> {
  const env: Record<string, string> = {
    OBSIDIAN_AUTH_TOKEN: credentials.authToken,
  };

  console.log(`📤 Pushing changes to Obsidian Sync...`);
  await runObCommand(["sync", "--path", vaultDir], { env });
}

/**
 * Update a note in the Obsidian vault via Headless Sync.
 * Pulls vault → modifies file → pushes back.
 */
export async function appendTweetToObsidianNote(
  notePath: string,
  embedHtml: string,
  credentials: {
    authToken: string;
    vaultName: string;
    vaultPassword?: string;
  },
): Promise<void> {
  // Pull vault
  const vaultDir = await syncObsidianVault(credentials);

  // Read note from synced vault
  const filePath = path.join(vaultDir, notePath);
  if (!fs.existsSync(filePath)) {
    throw new Error(
      `Note not found in Obsidian vault: ${notePath} (looked at ${filePath})`,
    );
  }

  const content = fs.readFileSync(filePath, "utf-8");

  if (content.includes(TWEET_SECTION_HEADER)) {
    console.log(
      "Tweet section already exists in Obsidian note, skipping update",
    );
    return;
  }

  // Update the file
  fs.writeFileSync(
    filePath,
    content + buildTweetSection(content, embedHtml),
    "utf-8",
  );

  // Push changes back
  await pushObsidianVault(vaultDir, {
    authToken: credentials.authToken,
  });
}

// --- Main Pipeline ---

/**
 * Get yesterday's date in YYYY-MM-DD format (UTC).
 * We post the previous day's reflection to ensure the note is finalized.
 */
export function getYesterdayDate(): string {
  const now = new Date();
  now.setUTCDate(now.getUTCDate() - 1);
  return now.toISOString().split("T")[0] as string;
}

/**
 * Parse command line arguments.
 */
function parseArgs(): { date: string; dryRun: boolean } {
  const args = process.argv.slice(2);
  let date = getYesterdayDate();
  let dryRun = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--date" && args[i + 1]) {
      date = args[i + 1] as string;
      i++;
    } else if (args[i] === "--dry-run") {
      dryRun = true;
    }
  }

  return { date, dryRun };
}

/**
 * Validate that all required environment variables are set.
 */
export function validateEnvironment(): {
  twitter: {
    apiKey: string;
    apiSecret: string;
    accessToken: string;
    accessSecret: string;
  };
  gemini: { apiKey: string; model: string };
  obsidian: {
    authToken: string;
    vaultName: string;
    vaultPassword?: string;
  };
} {
  const required = [
    "TWITTER_API_KEY",
    "TWITTER_API_SECRET",
    "TWITTER_ACCESS_TOKEN",
    "TWITTER_ACCESS_SECRET",
    "GEMINI_API_KEY",
    "OBSIDIAN_AUTH_TOKEN",
    "OBSIDIAN_VAULT_NAME",
  ];

  const missing = required.filter((key) => !process.env[key]);
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(", ")}`,
    );
  }

  return {
    twitter: {
      apiKey: process.env.TWITTER_API_KEY as string,
      apiSecret: process.env.TWITTER_API_SECRET as string,
      accessToken: process.env.TWITTER_ACCESS_TOKEN as string,
      accessSecret: process.env.TWITTER_ACCESS_SECRET as string,
    },
    gemini: {
      apiKey: process.env.GEMINI_API_KEY as string,
      model: process.env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL,
    },
    obsidian: {
      authToken: process.env.OBSIDIAN_AUTH_TOKEN as string,
      vaultName: process.env.OBSIDIAN_VAULT_NAME as string,
      vaultPassword: process.env.OBSIDIAN_VAULT_PASSWORD || undefined,
    },
  };
}

/**
 * Main entry point for the tweet reflection pipeline.
 */
export async function main(options?: {
  date?: string;
  dryRun?: boolean;
  contentDir?: string;
}): Promise<void> {
  const date = options?.date || getYesterdayDate();
  const dryRun = options?.dryRun || false;
  const contentDir = options?.contentDir || CONTENT_DIR;

  console.log(
    `📅 Processing reflection for ${date}${dryRun ? " (DRY RUN)" : ""}`,
  );

  // Step 1: Read the reflection from the repo (checked out by GitHub Actions)
  const reflection = readReflection(date, contentDir);
  if (!reflection) {
    console.log(`ℹ️  No reflection found for ${date}, exiting`);
    return;
  }

  console.log(`📄 Found reflection: ${reflection.title}`);

  // Check idempotency
  if (reflection.hasTweetSection) {
    console.log(`ℹ️  Reflection already has a tweet section, skipping`);
    return;
  }

  // Step 2: Validate credentials
  const env = validateEnvironment();

  // Step 3: Generate tweet text with Gemini
  console.log(`🤖 Generating tweet with ${env.gemini.model}...`);
  const tweetText = await generateTweetWithGemini(
    reflection,
    env.gemini.apiKey,
    env.gemini.model,
  );
  console.log(
    `📝 Generated tweet (${calculateTweetLength(tweetText)} chars):\n${tweetText}`,
  );

  if (dryRun) {
    console.log(`🏁 Dry run complete, would have posted the above tweet`);
    return;
  }

  // Step 4: Post tweet to Twitter
  console.log(`🐦 Posting tweet to Twitter...`);
  const tweet = await postTweet(tweetText, env.twitter);
  console.log(
    `✅ Tweet posted: https://twitter.com/${TWITTER_HANDLE}/status/${tweet.id}`,
  );

  // Step 5: Get embed HTML
  console.log(`🔗 Fetching embed code...`);
  const embedHtml = await getEmbedHtml(tweet.id, tweet.text, date);
  console.log(`📋 Got embed HTML (${embedHtml.length} chars)`);

  // Step 6: Write tweet section to Obsidian vault via Headless Sync
  const obsidianNotePath = `reflections/${date}.md`;
  console.log(`📝 Writing tweet section to Obsidian note: ${obsidianNotePath}`);
  await appendTweetToObsidianNote(obsidianNotePath, embedHtml, env.obsidian);
  console.log(`✅ Obsidian vault updated via Headless Sync (review in Obsidian and publish)`);

  console.log(`🎉 Done! Tweet posted and Obsidian note updated for ${date}`);
}

// Run if executed directly
const isMainModule = process.argv[1]?.endsWith("tweet-reflection.ts");
if (isMainModule) {
  const { date, dryRun } = parseArgs();
  main({ date, dryRun }).catch((error) => {
    console.error(
      `❌ Error: ${error instanceof Error ? error.message : error}`,
    );
    process.exit(1);
  });
}
