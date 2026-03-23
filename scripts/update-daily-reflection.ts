#!/usr/bin/env npx tsx

/**
 * Updates the daily reflection note in the Obsidian vault.
 *
 * Creates the reflection if it doesn't exist, adds series sections,
 * and inserts post links — all deterministic, no AI required.
 *
 * Usage: npx tsx scripts/update-daily-reflection.ts --series <id> --post <path>
 *        npx tsx scripts/update-daily-reflection.ts --help
 */

import fs from "node:fs";
import path from "node:path";
import { syncObsidianVault, pushObsidianVault } from "./lib/obsidian-sync.ts";
import { lookupSeries, BLOG_SERIES } from "./lib/blog-series-config.ts";
import { parseFrontmatter } from "./lib/frontmatter.ts";
import { updateDailyReflection } from "./lib/daily-reflection.ts";
import { todayPacific } from "./lib/blog-series.ts";

const USAGE = `
Usage: update-daily-reflection --series <id> --post <path> [--dry-run]

Updates the daily reflection note in the Obsidian vault with a link
to the newly generated blog post.

Options:
  --series   Blog series ID (${[...BLOG_SERIES.keys()].join(", ")})
  --post     Path to the generated blog post file (relative to repo root)
  --dry-run  Preview without writing
  --help     Show this help message

Environment:
  OBSIDIAN_AUTH_TOKEN      Required. Obsidian API token.
  OBSIDIAN_VAULT_NAME      Required. Vault identifier.
  OBSIDIAN_VAULT_CACHE_DIR Optional. Cache dir for warm sync.
`.trim();

interface UpdateArgs {
  readonly series: string;
  readonly postFile: string;
  readonly dryRun: boolean;
}

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

const parseArgs = (argv: readonly string[]): UpdateArgs | "help" => {
  const args = argv.slice(2);
  if (args.includes("--help") || args.length === 0) return "help";

  const flagValue = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    return idx >= 0 && idx + 1 < args.length ? (args[idx + 1] as string) : undefined;
  };

  const series = flagValue("--series") ?? "";
  const postFile = flagValue("--post") ?? "";
  const dryRun = args.includes("--dry-run");

  if (!series || !BLOG_SERIES.has(series)) {
    console.error(`❌ --series is required. Available: ${[...BLOG_SERIES.keys()].join(", ")}`);
    process.exit(1);
  }

  if (!postFile) {
    console.error("❌ --post is required");
    process.exit(1);
  }

  return { series, postFile, dryRun };
};

const run = async (): Promise<void> => {
  const parsed = parseArgs(process.argv);
  if (parsed === "help") {
    console.log(USAGE);
    return;
  }

  const series = lookupSeries(parsed.series);
  const repoRoot = path.resolve(import.meta.dirname, "..");
  const postPath = path.isAbsolute(parsed.postFile)
    ? parsed.postFile
    : path.join(repoRoot, parsed.postFile);

  if (!fs.existsSync(postPath)) {
    console.error(`❌ Post file not found: ${postPath}`);
    process.exit(1);
  }

  const postContent = fs.readFileSync(postPath, "utf-8");
  const { frontmatter } = parseFrontmatter(postContent);
  const postTitle = frontmatter["title"] ?? "";
  const postFilename = path.basename(parsed.postFile);

  if (!postTitle) {
    console.error("❌ Could not extract title from post frontmatter");
    process.exit(1);
  }

  const today = todayPacific();

  log({ event: "update_reflection_start", series: series.id, postFilename, postTitle, today });

  if (parsed.dryRun) {
    log({ event: "dry_run", series: series.id, postFilename, postTitle, today });
    return;
  }

  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) {
    console.error("❌ OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");
    process.exit(1);
  }

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  log({ event: "vault_pulled", vaultDir });

  const result = updateDailyReflection(vaultDir, today, series, postFilename, postTitle);
  log({ event: "reflection_updated", ...result });

  const shouldPushVault = result.reflectionCreated || result.sectionCreated || result.linkInserted || result.forwardLinkAdded;
  if (shouldPushVault) {
    await pushObsidianVault(vaultDir, { authToken });
    log({ event: "vault_pushed" });
  } else {
    log({ event: "no_changes_needed" });
  }

  log({ event: "update_reflection_complete" });
};

if (process.argv[1]?.endsWith("update-daily-reflection.ts")) {
  run().catch((error) => {
    console.error(JSON.stringify({
      event: "fatal_error",
      message: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    }));
    process.exit(1);
  });
}

export { parseArgs, run };
