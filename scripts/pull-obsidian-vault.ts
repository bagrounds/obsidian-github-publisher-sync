#!/usr/bin/env npx tsx

import fs from "node:fs";
import { syncObsidianVault } from "./lib/obsidian-sync.ts";

const main = async (): Promise<void> => {
  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;

  if (!authToken || !vaultName) {
    console.error("❌ OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");
    process.exit(1);
  }

  const vaultDir = await syncObsidianVault({ authToken, vaultName });

  const outputPath = process.env.GITHUB_OUTPUT;
  if (outputPath) {
    fs.appendFileSync(outputPath, `vault_dir=${vaultDir}\n`);
  }

  console.log(JSON.stringify({ event: "vault_synced", vaultDir }));
};

if (process.argv[1]?.endsWith("pull-obsidian-vault.ts")) {
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
