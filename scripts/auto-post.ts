/**
 * Social Media Auto-Posting Orchestrator
 *
 * Discovers content that hasn't been posted to social media and posts it.
 * All content is read from the Obsidian vault — the single source of truth.
 *
 * Strategy:
 * 1. Pull the Obsidian vault (shared across BFS discovery and posting).
 * 2. If past the posting hour and yesterday's reflection hasn't been posted, post that.
 * 3. Otherwise, use BFS from the most recent reflection to find unposted content.
 * 4. Post at most 1 item per platform per run.
 * 5. If all content has been posted everywhere, log a success message.
 *
 * Usage:
 *   npx tsx scripts/auto-post.ts [--posting-hour 17]
 *
 * This script is the entry point for the scheduled GitHub Action.
 * It delegates actual posting to tweet-reflection.ts via the main() function.
 *
 * @module auto-post
 */

import {
  discoverContentToPost,
  isPastPostingHourUTC,
  type Platform,
  type FindContentConfig,
  type ContentToPost,
} from "./find-content-to-post.ts";
import { main, validateEnvironment, syncObsidianVault } from "./tweet-reflection.ts";

// --- Types ---

interface AutoPostConfig {
  readonly postingHourUTC: number;
}

// --- Argument Parsing ---

function parseArgs(): AutoPostConfig {
  const args = process.argv.slice(2);
  let postingHourUTC = 17; // 5 PM UTC = 9 AM PST / 10 AM PDT

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--posting-hour" && args[i + 1]) {
      postingHourUTC = parseInt(args[i + 1] as string, 10);
      if (postingHourUTC < 0 || postingHourUTC > 23 || Number.isNaN(postingHourUTC)) {
        throw new Error(`Invalid posting hour: ${args[i + 1]} (must be 0-23)`);
      }
      i++;
    }
  }

  return { postingHourUTC };
}

// --- Platform Detection ---

/**
 * Determine which platforms have credentials configured.
 */
function getConfiguredPlatforms(): readonly Platform[] {
  const env = validateEnvironment();
  const platforms: Platform[] = [];

  if (env.twitter) platforms.push("twitter");
  if (env.bluesky) platforms.push("bluesky");
  if (env.mastodon) platforms.push("mastodon");

  return platforms;
}

// --- Main Orchestration ---

/**
 * Group content-to-post items by note path.
 * When the same note needs posting to multiple platforms, we only
 * call main() once for that note (it handles all platforms internally).
 */
function groupByNote(
  items: readonly ContentToPost[],
): Map<string, ContentToPost[]> {
  const groups = new Map<string, ContentToPost[]>();
  for (const item of items) {
    const key = item.note.relativePath;
    const existing = groups.get(key) || [];
    existing.push(item);
    groups.set(key, existing);
  }
  return groups;
}

/**
 * Main auto-post orchestration.
 *
 * Pulls the Obsidian vault once, then discovers what to post (BFS reads from
 * the vault), and delegates posting to tweet-reflection.ts main() — passing
 * the pre-pulled vault dir so it doesn't pull again.
 */
async function autoPost(): Promise<void> {
  const config = parseArgs();

  console.log(`🤖 Auto-Post Orchestrator`);
  console.log(`📅 ${new Date().toISOString()}`);
  console.log(`⏰ Posting hour (UTC): ${config.postingHourUTC}`);
  console.log();

  // Determine which platforms have credentials
  const platforms = getConfiguredPlatforms();
  if (platforms.length === 0) {
    console.warn("⚠️  No social platform credentials configured. Exiting.");
    return;
  }
  console.log(`📡 Configured platforms: ${platforms.join(", ")}`);

  // Pull the Obsidian vault — shared across BFS discovery and posting.
  // This is the single source of truth for all content.
  const env = validateEnvironment();
  console.log(`📥 Pulling Obsidian vault (source of truth)...`);
  const vaultDir = await syncObsidianVault(env.obsidian);

  // Check if we're past the posting hour
  const pastPostingHour = isPastPostingHourUTC(config.postingHourUTC);
  console.log(
    `⏰ Past posting hour (${config.postingHourUTC}:00 UTC): ${pastPostingHour}`,
  );
  console.log();

  // Discover what to post — BFS reads from the vault
  const findConfig: FindContentConfig = {
    contentDir: vaultDir,
    platforms,
    postingHourUTC: config.postingHourUTC,
  };

  const contentToPost = discoverContentToPost(findConfig, pastPostingHour);

  if (contentToPost.length === 0) {
    console.log();
    console.log(
      `🎉 Nothing to post! All reachable content has been shared on all platforms.`,
    );
    console.log(`💡 Time to create more content! 🖊️`);
    return;
  }

  console.log();
  console.log(`📋 Content to post:`);
  for (const item of contentToPost) {
    console.log(`  • [${item.platform}] ${item.note.title} (${item.note.relativePath})`);
  }
  console.log();

  // Group by note — each unique note only needs one main() call
  const grouped = groupByNote(contentToPost);

  for (const [notePath, items] of grouped) {
    const platforms = items.map((i) => i.platform);
    console.log(`\n${"═".repeat(60)}`);
    console.log(`📝 Posting: ${items[0]!.note.title}`);
    console.log(`📂 Path: ${notePath}`);
    console.log(`📡 Platforms: ${platforms.join(", ")}`);
    console.log(`${"═".repeat(60)}\n`);

    try {
      await main({
        note: notePath,
        vaultDir,
      });
    } catch (error) {
      console.error(
        `❌ Failed to post ${notePath}: ${error instanceof Error ? error.message : error}`,
      );
      // Continue with other notes — don't let one failure stop everything
    }
  }

  console.log(`\n🏁 Auto-post complete!`);
}

// --- Entry Point ---

const isMainModule = process.argv[1]?.endsWith("auto-post.ts");
if (isMainModule) {
  autoPost().catch((error) => {
    console.error(
      `❌ Fatal error: ${error instanceof Error ? error.message : error}`,
    );
    if (error instanceof Error && error.stack) {
      console.error(`Stack trace:\n${error.stack}`);
    }
    process.exit(1);
  });
}

export { autoPost, groupByNote, getConfiguredPlatforms };
