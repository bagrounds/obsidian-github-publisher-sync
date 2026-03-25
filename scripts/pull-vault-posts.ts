#!/usr/bin/env npx tsx

import fs from "node:fs";
import path from "node:path";
import { syncObsidianVault } from "./lib/obsidian-sync.ts";
import { BACKFILL_CONTENT_IDS } from "./lib/blog-series-config.ts";

const DATE_POST_PATTERN = /^\d{4}-\d{2}-\d{2}.*\.md$/;

const copySeriesPosts = (
  vaultDir: string,
  seriesId: string,
  repoRoot: string,
): number => {
  const vaultSeries = path.join(vaultDir, seriesId);
  if (!fs.existsSync(vaultSeries)) {
    console.log(`  ⚠️  No vault directory for series: ${seriesId}`);
    return 0;
  }

  const posts = fs
    .readdirSync(vaultSeries)
    .filter((f) => DATE_POST_PATTERN.test(f));

  const localDir = path.join(repoRoot, seriesId);
  fs.mkdirSync(localDir, { recursive: true });
  posts.forEach((f) =>
    fs.copyFileSync(path.join(vaultSeries, f), path.join(localDir, f)),
  );

  console.log(`  📂 ${seriesId}: ${posts.length} posts`);
  return posts.length;
};

const main = async (): Promise<void> => {
  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;

  if (!authToken || !vaultName) {
    console.error(
      "❌ OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required",
    );
    process.exit(1);
  }

  const rawArgs = process.argv.slice(2);
  const seriesArgs = rawArgs.includes("--all") ? [...BACKFILL_CONTENT_IDS] : rawArgs;
  if (seriesArgs.length === 0) {
    console.error(
      "Usage: pull-vault-posts.ts [--all | <series1> [series2] ...]",
    );
    process.exit(1);
  }

  const repoRoot = path.resolve(import.meta.dirname, "..");

  console.log(`📥 Pulling vault posts: ${seriesArgs.join(", ")}`);

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  console.log(`  📁 Vault synced: ${vaultDir}`);

  const total = seriesArgs.reduce(
    (sum, seriesId) => sum + copySeriesPosts(vaultDir, seriesId, repoRoot),
    0,
  );

  console.log(`  ✅ ${total} posts copied`);
};

if (process.argv[1]?.endsWith("pull-vault-posts.ts")) {
  main().catch((error) => {
    console.error(`💀 Fatal: ${error instanceof Error ? error.message : String(error)}`);
    if (error instanceof Error && error.stack) console.error(error.stack);
    process.exit(1);
  });
}

export { main, copySeriesPosts };
