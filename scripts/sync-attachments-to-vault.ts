#!/usr/bin/env npx tsx

import fs from "node:fs";
import path from "node:path";
import {
  syncObsidianVault,
  pushObsidianVault,
} from "./lib/obsidian-sync.ts";
import { syncAttachmentsDir } from "./lib/blog-image.ts";

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

const main = async (): Promise<void> => {
  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;

  if (!authToken || !vaultName) {
    console.error("❌ OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");
    process.exit(1);
  }

  const localDir = process.argv[2];
  if (!localDir) {
    console.error("Usage: sync-attachments-to-vault.ts <local-attachments-dir>");
    process.exit(1);
  }

  const localPath = path.resolve(localDir);
  if (!fs.existsSync(localPath)) {
    log({ event: "no_attachments_dir", localPath });
    return;
  }

  const files = fs.readdirSync(localPath);
  if (files.length === 0) {
    log({ event: "no_attachments_to_sync" });
    return;
  }

  log({ event: "sync_start", fileCount: files.length });

  const vaultDir = await syncObsidianVault({ authToken, vaultName });

  const synced = syncAttachmentsDir(localPath, vaultDir);

  if (synced > 0) {
    log({ event: "attachments_synced", count: synced });
    await pushObsidianVault(vaultDir, { authToken });
    log({ event: "vault_pushed" });
  } else {
    log({ event: "all_attachments_in_sync" });
  }
};

if (process.argv[1]?.endsWith("sync-attachments-to-vault.ts")) {
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
