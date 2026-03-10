/**
 * Obsidian Headless Sync integration.
 *
 * Manages the pull/push cycle with the Obsidian vault via the `ob` CLI.
 * Handles lock contention, process cleanup, and warm cache optimization.
 *
 * @module obsidian-sync
 */

import fs from "node:fs";
import path from "node:path";
import { execFile as execFileCb, exec as execCb } from "node:child_process";
import { promisify } from "node:util";

import type { ObsidianCredentials, EmbedSection } from "./types.ts";

const execFileAsync = promisify(execFileCb);
const execAsync = promisify(execCb);

// --- Command Execution ---

/**
 * Run the `ob` CLI command with arguments.
 */
export async function runObCommand(
  args: string[],
  options: { cwd?: string; env?: Record<string, string> } = {},
): Promise<{ stdout: string; stderr: string }> {
  const env = { ...process.env, ...options.env };
  try {
    return await execFileAsync("ob", args, { cwd: options.cwd, env });
  } catch (error) {
    const err = error as Error & { stdout?: string; stderr?: string };
    throw new Error(
      [
        `Command: ob ${args.join(" ")}`,
        `Error: ${err.message}`,
        err.stdout ? `Stdout: ${err.stdout}` : null,
        err.stderr ? `Stderr: ${err.stderr}` : null,
      ]
        .filter(Boolean)
        .join("\n"),
    );
  }
}

// --- Lock Management ---

/**
 * Remove the .sync.lock directory from an Obsidian vault.
 */
export function removeSyncLock(vaultDir: string): void {
  const lockPath = path.join(vaultDir, ".obsidian", ".sync.lock");
  if (fs.existsSync(lockPath)) {
    console.log(`🔓 Removing stale .sync.lock from vault`);
    fs.rmSync(lockPath, { recursive: true, force: true });
  }
}

// --- Process Management ---

/**
 * Log diagnostic information about the sync lock state and running processes.
 */
export async function logSyncDiagnostics(vaultDir: string): Promise<void> {
  const lockPath = path.join(vaultDir, ".obsidian", ".sync.lock");
  try {
    if (fs.existsSync(lockPath)) {
      const stat = fs.statSync(lockPath);
      const lockAgeMs = Date.now() - stat.mtimeMs;
      console.log(
        `  🔍 Lock exists: mtime=${stat.mtimeMs.toFixed(3)}, age=${lockAgeMs}ms, isDir=${stat.isDirectory()}`,
      );
    } else {
      console.log(`  🔍 Lock does not exist at ${lockPath}`);
    }
  } catch (err) {
    console.log(`  🔍 Lock stat error: ${(err as Error).message}`);
  }

  try {
    const { stdout } = await execAsync(
      `ps -u $(id -u) -o pid,args 2>/dev/null | grep -iE 'obsidian|ob |${vaultDir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}' | grep -v grep || true`,
    );
    if (stdout.trim()) {
      console.log(`  🔍 Related processes:\n${stdout.trim().split("\n").map(line => `    ${line.trim()}`).join("\n")}`);
    } else {
      console.log(`  🔍 No related processes found`);
    }
  } catch {
    // ps/grep may fail — not critical
  }
}

/**
 * Kill any lingering `ob` (obsidian-headless) processes.
 *
 * Uses full command line matching (ps -o pid,args) to find processes,
 * with graceful SIGTERM → forced SIGKILL escalation.
 */
export async function killObProcesses(vaultDir?: string): Promise<void> {
  try {
    const patterns = ["obsidian-headless"];
    if (vaultDir) {
      patterns.push(vaultDir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
    }
    const grepPattern = patterns.join("|");
    const { stdout } = await execAsync(
      `ps -u $(id -u) -o pid,args | grep -E '${grepPattern}' | grep -v grep | grep -v $$ | awk '{print $1}'`,
    );
    const pids = stdout.trim().split("\n").filter(Boolean).filter(
      (pid) => parseInt(pid, 10) !== process.pid,
    );
    if (pids.length === 0) return;

    console.log(`🔪 Killing ${pids.length} lingering ob process(es): ${pids.join(", ")}`);

    // Phase 1: SIGTERM — graceful shutdown
    for (const pid of pids) {
      try {
        process.kill(parseInt(pid, 10), "SIGTERM");
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code !== "ESRCH") {
          console.warn(`  ⚠️ Could not SIGTERM PID ${pid}: ${(err as Error).message}`);
        }
      }
    }

    // Wait up to 2s for graceful termination
    for (let i = 0; i < 10; i++) {
      await new Promise((resolve) => setTimeout(resolve, 200));
      const allDead = pids.every((pid) => {
        try {
          process.kill(parseInt(pid, 10), 0);
          return false;
        } catch {
          return true;
        }
      });
      if (allDead) return;
    }

    // Phase 2: SIGKILL — force kill survivors
    for (const pid of pids) {
      try {
        process.kill(parseInt(pid, 10), 0);
        console.warn(`  ⚠️ PID ${pid} survived SIGTERM, sending SIGKILL`);
        process.kill(parseInt(pid, 10), "SIGKILL");
      } catch {
        // already dead
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  } catch {
    // ps/grep may fail — not critical
  }
}

/**
 * Ensure no sync lock or lingering process blocks the next `ob sync`.
 */
export async function ensureSyncClean(vaultDir: string): Promise<void> {
  await killObProcesses(vaultDir);
  removeSyncLock(vaultDir);

  const lockPath = path.join(vaultDir, ".obsidian", ".sync.lock");
  if (fs.existsSync(lockPath)) {
    console.warn(`  ⚠️ Lock still exists after cleanup, removing again`);
    fs.rmSync(lockPath, { recursive: true, force: true });
  }
}

// --- Sync with Retry ---

/**
 * Run `ob sync` with retry logic for lock contention.
 */
export async function runObSyncWithRetry(
  args: string[],
  options: { env?: Record<string, string> },
  vaultDir: string,
  maxRetries = 5,
): Promise<void> {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      await runObCommand(args, options);
      return;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      if (msg.includes("Another sync instance") && attempt < maxRetries) {
        const delayMs = 2000 * 2 ** attempt;
        console.warn(
          `  ⚠️ Sync lock contention (retry ${attempt + 1}/${maxRetries}), ` +
          `cleaning up and retrying in ${delayMs / 1000}s...`,
        );
        await logSyncDiagnostics(vaultDir);
        await ensureSyncClean(vaultDir);
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      } else {
        throw error;
      }
    }
  }
}

// --- Vault Sync ---

/**
 * Sync an Obsidian vault to a local directory using Headless Sync.
 *
 * Supports warm cache fast path: skips sync-setup when the vault
 * is already configured from a previous run, avoiding lock contention.
 */
export async function syncObsidianVault(credentials: {
  authToken: string;
  vaultName: string;
  vaultPassword?: string;
}): Promise<string> {
  const cacheDir = process.env.OBSIDIAN_VAULT_CACHE_DIR;
  const vaultDir = cacheDir || path.join(
    process.env.RUNNER_TEMP || "/tmp",
    `obsidian-vault-${process.pid}-${Date.now()}`,
  );

  const isWarmCache = cacheDir && fs.existsSync(path.join(vaultDir, ".obsidian"));
  fs.mkdirSync(vaultDir, { recursive: true });

  if (isWarmCache) {
    console.log(`♻️  Re-using cached vault at ${vaultDir} (incremental sync)`);
  }

  const env: Record<string, string> = {
    OBSIDIAN_AUTH_TOKEN: credentials.authToken,
  };

  await ensureSyncClean(vaultDir);

  // Warm cache fast path: try ob sync directly without sync-setup
  if (isWarmCache) {
    console.log(`📥 Pulling latest vault content (warm cache fast path)...`);
    try {
      await runObSyncWithRetry(["sync", "--path", vaultDir], { env }, vaultDir);
      return vaultDir;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      if (msg.includes("No sync configuration") || msg.includes("Encryption key not found") || msg.includes("Run") && msg.includes("sync-setup")) {
        console.log(`⚠️  Warm cache missing config, falling back to sync-setup...`);
        await ensureSyncClean(vaultDir);
      } else {
        throw error;
      }
    }
  }

  // Cold cache / fallback: full sync-setup + sync
  const setupArgs = ["sync-setup", "--vault", credentials.vaultName, "--path", vaultDir];
  if (credentials.vaultPassword) {
    setupArgs.push("--password", credentials.vaultPassword);
  }

  console.log(`🔧 Setting up Obsidian Sync for vault: ${credentials.vaultName}`);
  await runObCommand(setupArgs, { env });
  removeSyncLock(vaultDir);

  console.log(`📥 Pulling latest vault content...`);
  await runObSyncWithRetry(["sync", "--path", vaultDir], { env }, vaultDir);

  return vaultDir;
}

/**
 * Push local changes back to the Obsidian vault via Headless Sync.
 */
export async function pushObsidianVault(
  vaultDir: string,
  credentials: { authToken: string },
): Promise<void> {
  const env: Record<string, string> = {
    OBSIDIAN_AUTH_TOKEN: credentials.authToken,
  };

  await ensureSyncClean(vaultDir);

  console.log(`📤 Pushing changes to Obsidian Sync...`);
  await runObSyncWithRetry(["sync", "--path", vaultDir], { env }, vaultDir);

  // Post-push cleanup: settling delay for child processes
  await new Promise((resolve) => setTimeout(resolve, 1000));
  await ensureSyncClean(vaultDir);
}

/**
 * Append embed sections to a note in the Obsidian vault and push.
 */
export async function appendEmbedsToObsidianNote(
  notePath: string,
  sections: EmbedSection[],
  credentials: ObsidianCredentials,
): Promise<void> {
  const vaultDir = await syncObsidianVault(credentials);

  const filePath = path.join(vaultDir, notePath);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Note not found in Obsidian vault: ${notePath} (looked at ${filePath})`);
  }

  let content = fs.readFileSync(filePath, "utf-8");
  let modified = false;

  for (const section of sections) {
    if (!content.includes(section.header)) {
      content = content + section.buildSection(content, section.embedHtml);
      modified = true;
    } else {
      console.log(`${section.header} already exists in Obsidian note, skipping`);
    }
  }

  if (!modified) {
    console.log("No new sections to add to Obsidian note");
    return;
  }

  fs.writeFileSync(filePath, content, "utf-8");
  await pushObsidianVault(vaultDir, { authToken: credentials.authToken });
}
