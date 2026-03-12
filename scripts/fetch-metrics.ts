/**
 * Fetch engagement metrics from social media platforms.
 *
 * Reads an experiment log, fetches current engagement metrics from
 * Mastodon and Bluesky, and writes updated records back to the log.
 *
 * This script bridges the gap between the posting pipeline (which logs
 * variant assignments) and the analysis script (which computes statistics).
 *
 * Usage:
 *   npx tsx scripts/fetch-metrics.ts --data experiment-log.json
 *
 * Environment variables required:
 *   MASTODON_INSTANCE_URL, MASTODON_ACCESS_TOKEN (for Mastodon metrics)
 *   BLUESKY_IDENTIFIER, BLUESKY_APP_PASSWORD (for Bluesky metrics)
 *
 * @module fetch-metrics
 */

import fs from "node:fs";

import { fetchMastodonMetrics, fetchBlueskyMetrics } from "./lib/analytics.ts";
import type { MastodonCredentials, BlueskyCredentials } from "./lib/types.ts";
import type { EngagementMetrics } from "./lib/experiment.ts";

// --- Types ---

interface ExperimentRecord {
  readonly variant: string;
  readonly notePath: string;
  readonly platform: "mastodon" | "bluesky";
  readonly postUrl: string;
  readonly postId: string;
  readonly postUri?: string;
  readonly timestamp: string;
  metrics?: EngagementMetrics;
}

// --- Credential Resolution ---

const getMastodonCredentials = (): MastodonCredentials | null => {
  const instanceUrl = process.env.MASTODON_INSTANCE_URL;
  const accessToken = process.env.MASTODON_ACCESS_TOKEN;
  if (!instanceUrl || !accessToken) return null;
  return { instanceUrl, accessToken };
};

const getBlueskyCredentials = (): BlueskyCredentials | null => {
  const identifier = process.env.BLUESKY_IDENTIFIER;
  const password = process.env.BLUESKY_APP_PASSWORD;
  if (!identifier || !password) return null;
  return { identifier, password };
};

// --- Main ---

const main = async (): Promise<void> => {
  const args = process.argv.slice(2);
  let dataFile = "experiment-log.json";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--data" && args[i + 1]) {
      dataFile = args[i + 1] as string;
      i++;
    }
  }

  if (!fs.existsSync(dataFile)) {
    console.error(`❌ Experiment log not found: ${dataFile}`);
    process.exit(1);
  }

  const records: ExperimentRecord[] = JSON.parse(
    fs.readFileSync(dataFile, "utf-8"),
  );

  console.log(`📂 Loaded ${records.length} records from ${dataFile}`);

  const mastodonCreds = getMastodonCredentials();
  const blueskyCreds = getBlueskyCredentials();

  if (!mastodonCreds && !blueskyCreds) {
    console.error("❌ No platform credentials configured. Set MASTODON_* or BLUESKY_* env vars.");
    process.exit(1);
  }

  let updated = 0;
  let errors = 0;

  for (const record of records) {
    try {
      if (record.platform === "mastodon" && mastodonCreds) {
        console.log(`  🐘 Fetching Mastodon metrics for ${record.postId}...`);
        const metrics = await fetchMastodonMetrics(record.postId, mastodonCreds);
        record.metrics = metrics;
        console.log(`    ❤️ ${metrics.likes} | 🔁 ${metrics.reposts} | 💬 ${metrics.replies}`);
        updated++;
      } else if (record.platform === "bluesky" && blueskyCreds && record.postUri) {
        console.log(`  🦋 Fetching Bluesky metrics for ${record.postId}...`);
        const metrics = await fetchBlueskyMetrics(record.postUri, blueskyCreds);
        record.metrics = metrics;
        console.log(`    ❤️ ${metrics.likes} | 🔁 ${metrics.reposts} | 💬 ${metrics.replies}`);
        updated++;
      } else {
        console.log(`  ⏭️ Skipping ${record.platform} (no credentials or missing URI)`);
      }
    } catch (error) {
      console.error(`  ⚠️ Failed to fetch metrics for ${record.postId}: ${error}`);
      errors++;
    }
  }

  fs.writeFileSync(dataFile, JSON.stringify(records, null, 2), "utf-8");
  console.log(`\n✅ Updated ${updated} records (${errors} errors). Written to ${dataFile}`);
};

// Entry point guard
const isMainModule = process.argv[1]?.endsWith("fetch-metrics.ts");
if (isMainModule) {
  main().catch((error) => {
    console.error(`❌ Error: ${error}`);
    process.exit(1);
  });
}

export { getMastodonCredentials, getBlueskyCredentials };
