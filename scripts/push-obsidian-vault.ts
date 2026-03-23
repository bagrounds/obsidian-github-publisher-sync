#!/usr/bin/env npx tsx

import { pushObsidianVault } from "./lib/obsidian-sync.ts";

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

const main = async (): Promise<void> => {
  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultDir = process.env.VAULT_DIR ?? process.argv[2];

  if (!authToken) {
    console.error("❌ OBSIDIAN_AUTH_TOKEN is required");
    process.exit(1);
  }

  if (!vaultDir) {
    console.error("Usage: push-obsidian-vault.ts <vault-dir> or set VAULT_DIR env var");
    process.exit(1);
  }

  log({ event: "push_start", vaultDir });

  await pushObsidianVault(vaultDir, { authToken });

  log({ event: "vault_pushed" });
};

if (process.argv[1]?.endsWith("push-obsidian-vault.ts")) {
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
