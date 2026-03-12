#!/usr/bin/env npx tsx
/**
 * Syncs a single file to the Obsidian vault via headless sync.
 *
 * Usage: npx tsx scripts/sync-file-to-obsidian.ts <local-path> <vault-path>
 *        npx tsx scripts/sync-file-to-obsidian.ts --help
 *        npx tsx scripts/sync-file-to-obsidian.ts --dry-run <local-path> <vault-path>
 */

import fs from "node:fs";
import path from "node:path";
import { syncObsidianVault, pushObsidianVault } from "./lib/obsidian-sync.ts";

const USAGE = `
Usage: sync-file-to-obsidian <local-path> <vault-path> [--dry-run]

Copies a single local file into the Obsidian vault via headless sync.

Arguments:
  local-path   Path to the local file (relative to repo root or absolute)
  vault-path   Destination path inside the vault (relative to vault root)

Options:
  --dry-run    Preview without writing
  --help       Show this help message

Environment:
  OBSIDIAN_AUTH_TOKEN      Required. Obsidian API token.
  OBSIDIAN_VAULT_NAME      Required. Vault identifier.
  OBSIDIAN_VAULT_CACHE_DIR Optional. Cache dir for warm sync.

Examples:
  npx tsx scripts/sync-file-to-obsidian.ts auto-blog-zero/2026-03-12-my-post.md auto-blog-zero/2026-03-12-my-post.md
  npx tsx scripts/sync-file-to-obsidian.ts chickie-loo/AGENTS.md chickie-loo/AGENTS.md --dry-run
`.trim();

interface SyncFileArgs {
  readonly localPath: string;
  readonly vaultPath: string;
  readonly dryRun: boolean;
}

const parseArgs = (argv: readonly string[]): SyncFileArgs | "help" => {
  const args = argv.slice(2);
  if (args.includes("--help") || args.length === 0) return "help";

  const dryRun = args.includes("--dry-run");
  const positional = args.filter((a) => a !== "--dry-run");

  if (positional.length !== 2) {
    console.error("❌ Expected exactly 2 positional arguments: <local-path> <vault-path>");
    console.error(USAGE);
    process.exit(1);
  }

  return {
    localPath: positional[0] as string,
    vaultPath: positional[1] as string,
    dryRun,
  };
};

const resolveLocalPath = (localPath: string, repoRoot: string): string =>
  path.isAbsolute(localPath) ? localPath : path.join(repoRoot, localPath);

const copyFileToVault = (localPath: string, vaultPath: string, vaultDir: string): boolean => {
  if (!fs.existsSync(localPath)) {
    console.error(`❌ Local file not found: ${localPath}`);
    return false;
  }

  const dest = path.join(vaultDir, vaultPath);
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  const localContent = fs.readFileSync(localPath, "utf-8");
  const vaultContent = fs.existsSync(dest) ? fs.readFileSync(dest, "utf-8") : null;

  if (vaultContent === localContent) return false;

  fs.writeFileSync(dest, localContent, "utf-8");
  return true;
};

const syncFileToObsidian = async (): Promise<void> => {
  const parsed = parseArgs(process.argv);
  if (parsed === "help") {
    console.log(USAGE);
    return;
  }

  const repoRoot = path.resolve(import.meta.dirname, "..");
  const absLocal = resolveLocalPath(parsed.localPath, repoRoot);

  console.log(JSON.stringify({
    event: "sync_start",
    localPath: parsed.localPath,
    vaultPath: parsed.vaultPath,
    dryRun: parsed.dryRun,
    timestamp: new Date().toISOString(),
  }));

  if (parsed.dryRun) {
    const exists = fs.existsSync(absLocal);
    console.log(JSON.stringify({
      event: "dry_run",
      localPath: parsed.localPath,
      vaultPath: parsed.vaultPath,
      fileExists: exists,
    }));
    return;
  }

  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) {
    console.error("❌ OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");
    process.exit(1);
  }

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  console.log(JSON.stringify({ event: "vault_pulled", vaultDir }));

  const written = copyFileToVault(absLocal, parsed.vaultPath, vaultDir);

  if (written) {
    console.log(JSON.stringify({ event: "file_written", vaultPath: parsed.vaultPath }));
    await pushObsidianVault(vaultDir, { authToken });
    console.log(JSON.stringify({ event: "vault_pushed" }));
  } else {
    console.log(JSON.stringify({ event: "already_in_sync", vaultPath: parsed.vaultPath }));
  }

  console.log(JSON.stringify({ event: "sync_complete", written }));
};

if (process.argv[1]?.endsWith("sync-file-to-obsidian.ts")) {
  syncFileToObsidian().catch((error) => {
    console.error(JSON.stringify({
      event: "fatal_error",
      message: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    }));
    process.exit(1);
  });
}

export { copyFileToVault, resolveLocalPath, parseArgs };
