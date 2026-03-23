#!/usr/bin/env npx tsx

import path from "node:path";
import {
  syncObsidianVault,
  pushObsidianVault,
} from "./lib/obsidian-sync.ts";
import {
  syncMarkdownDir,
  syncAttachmentsDir,
} from "./lib/blog-image.ts";
import { BACKFILL_CONTENT_IDS } from "./lib/blog-series-config.ts";

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

interface SyncPair {
  readonly localDir: string;
  readonly vaultSubdir: string;
}

const main = async (): Promise<void> => {
  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;

  if (!authToken || !vaultName) {
    console.error("❌ OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");
    process.exit(1);
  }

  const repoRoot = path.resolve(import.meta.dirname, "..");

  log({ event: "sync_start" });

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  log({ event: "vault_pulled", vaultDir });

  const dirs: readonly SyncPair[] = BACKFILL_CONTENT_IDS.map((id) => ({
    localDir: path.join(repoRoot, id),
    vaultSubdir: id,
  }));

  for (const { localDir, vaultSubdir } of dirs) {
    const synced = syncMarkdownDir(localDir, vaultSubdir, vaultDir);
    if (synced > 0) {
      log({ event: "files_synced", dir: vaultSubdir, count: synced });
    }
  }

  const localAttachments = path.join(repoRoot, "attachments");
  const attachmentsSynced = syncAttachmentsDir(localAttachments, vaultDir);
  if (attachmentsSynced > 0) {
    log({ event: "attachments_synced", count: attachmentsSynced });
  }

  await pushObsidianVault(vaultDir, { authToken });
  log({ event: "vault_pushed" });
};

if (process.argv[1]?.endsWith("sync-backfill-to-vault.ts")) {
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

export { main };
