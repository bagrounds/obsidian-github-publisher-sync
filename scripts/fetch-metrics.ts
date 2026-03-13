/**
 * Fetch engagement metrics from social media platforms.
 *
 * Reads experiment records from the vault's data/ab-test directory
 * (or a legacy JSON file), fetches current engagement metrics from
 * Mastodon and Bluesky, and writes updated records back.
 *
 * This script bridges the gap between the posting pipeline (which logs
 * variant assignments) and the analysis script (which computes statistics).
 *
 * Usage:
 *   npx tsx scripts/fetch-metrics.ts --vault /path/to/vault
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
import { fetchAndUpdateVaultMetrics } from "./lib/experiment.ts";
import type { ExperimentRecord, EngagementMetrics } from "./lib/experiment.ts";
import type { MastodonCredentials, BlueskyCredentials } from "./lib/types.ts";

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

// --- Platform Fetcher ---

/**
 * Build a metric fetcher from available platform credentials.
 * Returns a function that dispatches to the appropriate platform API.
 */
const buildFetcher = (
  mastodonCreds: MastodonCredentials | null,
  blueskyCreds: BlueskyCredentials | null,
) => async (record: ExperimentRecord): Promise<EngagementMetrics | undefined> => {
  if (record.platform === "mastodon" && mastodonCreds && record.postId) {
    console.log(`  🐘 Fetching Mastodon metrics for ${record.postId}...`);
    const metrics = await fetchMastodonMetrics(record.postId, mastodonCreds);
    console.log(`    ❤️ ${metrics.likes} | 🔁 ${metrics.reposts} | 💬 ${metrics.replies}`);
    return metrics;
  }
  if (record.platform === "bluesky" && blueskyCreds && record.postUri) {
    console.log(`  🦋 Fetching Bluesky metrics for ${record.postUri}...`);
    const metrics = await fetchBlueskyMetrics(record.postUri, blueskyCreds);
    console.log(`    ❤️ ${metrics.likes} | 🔁 ${metrics.reposts} | 💬 ${metrics.replies}`);
    return metrics;
  }
  return undefined;
};

// --- Main ---

const main = async (): Promise<void> => {
  const args = process.argv.slice(2);
  let dataFile: string | undefined;
  let vaultDir: string | undefined;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--data" && args[i + 1]) {
      dataFile = args[i + 1] as string;
      i++;
    }
    if (args[i] === "--vault" && args[i + 1]) {
      vaultDir = args[i + 1] as string;
      i++;
    }
  }

  const mastodonCreds = getMastodonCredentials();
  const blueskyCreds = getBlueskyCredentials();

  if (!mastodonCreds && !blueskyCreds) {
    console.error("❌ No platform credentials configured. Set MASTODON_* or BLUESKY_* env vars.");
    process.exit(1);
  }

  const fetcher = buildFetcher(mastodonCreds, blueskyCreds);

  if (vaultDir) {
    console.log(`📂 Fetching metrics for vault records in ${vaultDir}...`);
    const updated = await fetchAndUpdateVaultMetrics(vaultDir, fetcher);
    console.log(`\n✅ Updated ${updated} record(s) with fresh metrics.`);
    return;
  }

  if (!dataFile) {
    dataFile = "experiment-log.json";
  }

  if (!fs.existsSync(dataFile)) {
    console.error(`❌ Experiment log not found: ${dataFile}`);
    console.error(`   Use --vault <dir> for vault-based records or --data <file> for legacy format.`);
    process.exit(1);
  }

  const records: ExperimentRecord[] = JSON.parse(
    fs.readFileSync(dataFile, "utf-8"),
  );

  console.log(`📂 Loaded ${records.length} records from ${dataFile}`);

  let updated = 0;
  let errors = 0;

  for (const record of records) {
    try {
      const metrics = await fetcher(record);
      if (metrics) {
        record.metrics = metrics;
        updated++;
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

export { getMastodonCredentials, getBlueskyCredentials, buildFetcher };
