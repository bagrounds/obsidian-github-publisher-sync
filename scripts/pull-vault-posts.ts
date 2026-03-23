#!/usr/bin/env npx tsx

import fs from "node:fs";
import path from "node:path";
import { syncObsidianVault } from "./lib/obsidian-sync.ts";
import { BACKFILL_CONTENT_IDS } from "./lib/blog-series-config.ts";

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

const DATE_POST_PATTERN = /^\d{4}-\d{2}-\d{2}.*\.md$/;

const copySeriesPosts = (
  vaultDir: string,
  seriesId: string,
  repoRoot: string,
): number => {
  const vaultSeries = path.join(vaultDir, seriesId);
  if (!fs.existsSync(vaultSeries)) {
    log({ event: "no_vault_series_dir", series: seriesId });
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

  log({ event: "vault_posts_found", series: seriesId, count: posts.length });
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

  log({ event: "pull_start", series: seriesArgs });

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  log({ event: "vault_synced", vaultDir });

  const total = seriesArgs.reduce(
    (sum, seriesId) => sum + copySeriesPosts(vaultDir, seriesId, repoRoot),
    0,
  );

  log({ event: "pull_complete", totalPostsCopied: total });
};

if (process.argv[1]?.endsWith("pull-vault-posts.ts")) {
  main().catch((error) => {
    console.error(
      JSON.stringify({
        event: "fatal_error",
        message: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      }),
    );
    process.exit(1);
  });
}

export { main, copySeriesPosts };
