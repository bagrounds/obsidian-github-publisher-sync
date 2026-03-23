#!/usr/bin/env npx tsx

import fs from "node:fs";
import path from "node:path";
import {
  syncObsidianVault,
  pushObsidianVault,
} from "./lib/obsidian-sync.ts";

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

interface SyncArgs {
  readonly series: string;
  readonly post: string | undefined;
}

const parseArgs = (argv: readonly string[]): SyncArgs => {
  const args = argv.slice(2);
  const flagValue = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    return idx >= 0 && idx + 1 < args.length ? (args[idx + 1] as string) : undefined;
  };

  const series = flagValue("--series") ?? "";
  const post = flagValue("--post");

  if (!series) {
    console.error("Usage: sync-series-to-vault.ts --series <id> [--post <path>]");
    process.exit(1);
  }

  return { series, post: post && post.length > 0 ? post : undefined };
};

const readPreviousPostFilename = (metadataPath: string): string | undefined => {
  if (!fs.existsSync(metadataPath)) return undefined;
  const raw = fs.readFileSync(metadataPath, "utf-8");
  const parsed = JSON.parse(raw) as { previousPostFilename?: string };
  return parsed.previousPostFilename;
};

const syncFileToVault = (
  localPath: string,
  vaultPath: string,
  vaultDir: string,
): boolean => {
  if (!fs.existsSync(localPath)) {
    log({ event: "file_not_found", localPath });
    return false;
  }

  const dest = path.join(vaultDir, vaultPath);
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  const localContent = fs.readFileSync(localPath, "utf-8");
  const vaultContent = fs.existsSync(dest) ? fs.readFileSync(dest, "utf-8") : null;

  if (vaultContent === localContent) {
    log({ event: "already_in_sync", vaultPath });
    return false;
  }

  fs.writeFileSync(dest, localContent, "utf-8");
  log({ event: "file_synced", vaultPath });
  return true;
};

const main = async (): Promise<void> => {
  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;

  if (!authToken || !vaultName) {
    console.error("❌ OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");
    process.exit(1);
  }

  const config = parseArgs(process.argv);
  const repoRoot = path.resolve(import.meta.dirname, "..");

  log({ event: "sync_start", series: config.series, post: config.post });

  if (!config.post) {
    log({ event: "no_post_to_sync" });
    return;
  }

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  log({ event: "vault_synced", vaultDir });

  let changed = false;

  const postLocal = path.join(repoRoot, config.post);
  changed = syncFileToVault(postLocal, config.post, vaultDir) || changed;

  const metadataPath = path.join(repoRoot, config.series, ".last-generate-metadata.json");
  const previousFilename = readPreviousPostFilename(metadataPath);
  if (previousFilename) {
    const prevPath = `${config.series}/${previousFilename}`;
    const prevLocal = path.join(repoRoot, prevPath);
    changed = syncFileToVault(prevLocal, prevPath, vaultDir) || changed;
  } else {
    log({ event: "no_previous_post", reason: "first post or missing metadata" });
  }

  const agentsPath = `${config.series}/AGENTS.md`;
  const agentsLocal = path.join(repoRoot, agentsPath);
  changed = syncFileToVault(agentsLocal, agentsPath, vaultDir) || changed;

  const attachmentsDir = path.join(repoRoot, "attachments");
  if (fs.existsSync(attachmentsDir) && fs.readdirSync(attachmentsDir).length > 0) {
    const { syncAttachmentsDir } = await import("./lib/blog-image.ts");
    const synced = syncAttachmentsDir(attachmentsDir, vaultDir);
    if (synced > 0) {
      log({ event: "attachments_synced", count: synced });
      changed = true;
    }
  }

  if (changed) {
    await pushObsidianVault(vaultDir, { authToken });
    log({ event: "vault_pushed" });
  } else {
    log({ event: "all_in_sync" });
  }

  log({ event: "sync_complete", changed });
};

if (process.argv[1]?.endsWith("sync-series-to-vault.ts")) {
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

export { main, syncFileToVault, readPreviousPostFilename };
