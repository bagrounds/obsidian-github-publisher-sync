#!/usr/bin/env npx tsx

/**
 * Consolidated Scheduled Task Runner
 *
 * Single entry point for all scheduled tasks. Determines which tasks to
 * run based on the current UTC hour, then executes each task's pipeline
 * by spawning the existing CLI scripts as subprocesses.
 *
 * Usage:
 *   npx tsx scripts/run-scheduled.ts                     # run tasks for current hour
 *   npx tsx scripts/run-scheduled.ts --hour 15           # simulate hour 15 UTC
 *   npx tsx scripts/run-scheduled.ts --task social-posting  # run a specific task
 *
 * @module run-scheduled
 */

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  getScheduledTasks,
  isValidTaskId,
  extractSeriesId,
  BLOG_SERIES_RUN_CONFIGS,
  type TaskId,
} from "./lib/scheduler.ts";

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

// ---------------------------------------------------------------------------
// Subprocess helpers
// ---------------------------------------------------------------------------

const REPO_ROOT = path.resolve(import.meta.dirname, "..");

const runScript = (
  script: string,
  args: readonly string[],
  options?: {
    readonly continueOnError?: boolean;
    readonly extraEnv?: Readonly<Record<string, string>>;
  },
): void => {
  const { continueOnError = false, extraEnv = {} } = options ?? {};

  log({ event: "script_start", script, args });

  const result = spawnSync("npx", ["tsx", script, ...args], {
    stdio: "inherit",
    env: { ...process.env, ...extraEnv },
    cwd: REPO_ROOT,
  });

  if (result.status !== 0) {
    const msg = `${script} exited with code ${result.status}`;
    if (continueOnError) {
      log({ event: "script_failed_continuing", script, exitCode: result.status });
    } else {
      throw new Error(msg);
    }
  } else {
    log({ event: "script_complete", script });
  }
};

const parseGitHubOutputs = (filePath: string): Readonly<Record<string, string>> => {
  const content = fs.existsSync(filePath)
    ? fs.readFileSync(filePath, "utf-8")
    : "";

  return Object.fromEntries(
    content
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const eqIndex = line.indexOf("=");
        return eqIndex > 0
          ? [line.slice(0, eqIndex), line.slice(eqIndex + 1)]
          : [];
      })
      .filter((pair): pair is [string, string] => pair.length === 2),
  );
};

const runScriptWithOutputs = (
  script: string,
  args: readonly string[],
  extraEnv: Readonly<Record<string, string>> = {},
): Readonly<Record<string, string>> => {
  const tmpFile = path.join(os.tmpdir(), `github-output-${Date.now()}`);
  fs.writeFileSync(tmpFile, "");

  try {
    runScript(script, args, {
      extraEnv: { ...extraEnv, GITHUB_OUTPUT: tmpFile },
    });
    return parseGitHubOutputs(tmpFile);
  } finally {
    fs.existsSync(tmpFile) && fs.unlinkSync(tmpFile);
  }
};

// ---------------------------------------------------------------------------
// Task runners
// ---------------------------------------------------------------------------

const runBlogSeries = (seriesId: string): void => {
  const taskName = `blog-series:${seriesId}`;
  log({ event: "task_start", task: taskName });

  const runConfig = BLOG_SERIES_RUN_CONFIGS.get(seriesId);
  if (!runConfig) throw new Error(`No run config for series: ${seriesId}`);

  const model =
    process.env.BLOG_GEMINI_MODEL?.trim() || runConfig.defaultModel;
  const priorityUser = process.env[runConfig.priorityUserEnvVar]?.trim() || undefined;

  const seriesEnv: Record<string, string> = { BLOG_GEMINI_MODEL: model };
  if (priorityUser) seriesEnv.BLOG_PRIORITY_USER = priorityUser;

  // 1. Pull vault posts
  runScript("scripts/pull-vault-posts.ts", [seriesId]);

  // 2. Check Gemini quota (before)
  runScript("scripts/check-gemini-quota.ts", [
    "--label",
    `before ${seriesId}`,
  ]);

  // 3. Generate blog post — capture the "post" output
  const outputs = runScriptWithOutputs(
    "scripts/generate-blog-post.ts",
    ["--series", seriesId],
    seriesEnv,
  );
  const postPath = outputs.post?.trim();

  // 4. Generate blog image (continue-on-error)
  if (postPath) {
    runScript("scripts/generate-blog-image.ts", ["--note", postPath], {
      continueOnError: true,
    });
  }

  // 5. Check Gemini quota (after — always)
  runScript(
    "scripts/check-gemini-quota.ts",
    ["--label", `after ${seriesId}`],
    { continueOnError: true },
  );

  // 6. Sync to Obsidian vault
  if (postPath) {
    runScript("scripts/sync-series-to-vault.ts", [
      "--series",
      seriesId,
      "--post",
      postPath,
    ]);
  }

  log({ event: "task_complete", task: taskName });
};

const runBackfillImages = (): void => {
  log({ event: "task_start", task: "backfill-blog-images" });

  // 1. Pull vault posts (all series)
  runScript("scripts/pull-vault-posts.ts", ["--all"]);

  // 2. Check Gemini quota (before)
  runScript("scripts/check-gemini-quota.ts", [
    "--label",
    "before image backfill",
  ]);

  // 3. Backfill blog images (continue-on-error)
  runScript("scripts/backfill-blog-images.ts", [], { continueOnError: true });

  // 4. Check Gemini quota (after — always)
  runScript("scripts/check-gemini-quota.ts", [
    "--label",
    "after image backfill",
  ], { continueOnError: true });

  // 5. Sync backfilled content to Obsidian vault
  runScript("scripts/sync-backfill-to-vault.ts", []);

  log({ event: "task_complete", task: "backfill-blog-images" });
};

const runInternalLinking = (): void => {
  log({ event: "task_start", task: "internal-linking" });

  // 1. Pull Obsidian vault — capture vault_dir output
  const outputs = runScriptWithOutputs("scripts/pull-obsidian-vault.ts", []);
  const vaultDir = outputs.vault_dir?.trim();

  if (!vaultDir) {
    throw new Error("pull-obsidian-vault.ts did not output vault_dir");
  }

  // 2. Run internal linking (default max-files=10, no dry-run)
  runScript("scripts/internal-linking.ts", [
    "--max-files",
    "10",
    "--content-dir",
    vaultDir,
  ]);

  // 3. Push vault
  runScript("scripts/push-obsidian-vault.ts", [], {
    extraEnv: { VAULT_DIR: vaultDir },
  });

  log({ event: "task_complete", task: "internal-linking" });
};

const runSocialPosting = (): void => {
  log({ event: "task_start", task: "social-posting" });

  // 1. Check Gemini quota (before)
  runScript("scripts/check-gemini-quota.ts", [
    "--label",
    "before social posting",
  ]);

  // 2. Run auto-post (the scheduled discovery + posting pipeline)
  runScript("scripts/auto-post.ts", []);

  // 3. Check Gemini quota (after — always)
  runScript("scripts/check-gemini-quota.ts", [
    "--label",
    "after social posting",
  ], { continueOnError: true });

  log({ event: "task_complete", task: "social-posting" });
};

const TASK_RUNNERS: ReadonlyMap<TaskId, () => void> = new Map([
  ["blog-series:chickie-loo", () => runBlogSeries("chickie-loo")],
  ["blog-series:auto-blog-zero", () => runBlogSeries("auto-blog-zero")],
  [
    "blog-series:systems-for-public-good",
    () => runBlogSeries("systems-for-public-good"),
  ],
  ["backfill-blog-images", runBackfillImages],
  ["internal-linking", runInternalLinking],
  ["social-posting", runSocialPosting],
]);

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

interface CliArgs {
  readonly hourOverride: number | undefined;
  readonly taskOverride: string | undefined;
}

export const parseArgs = (argv: readonly string[]): CliArgs => {
  const args = argv.slice(2);
  const flagValue = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    return idx >= 0 && idx + 1 < args.length
      ? (args[idx + 1] as string)
      : undefined;
  };

  const hourStr = flagValue("--hour");
  const taskOverride = flagValue("--task");

  return {
    hourOverride: hourStr !== undefined ? parseInt(hourStr, 10) : undefined,
    taskOverride,
  };
};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const main = (): void => {
  const cliArgs = parseArgs(process.argv);
  const hourUtc = cliArgs.hourOverride ?? new Date().getUTCHours();

  const tasks: readonly TaskId[] = cliArgs.taskOverride
    ? isValidTaskId(cliArgs.taskOverride)
      ? [cliArgs.taskOverride]
      : (() => {
          console.error(`❌ Unknown task: ${cliArgs.taskOverride}`);
          process.exit(1);
        })()
    : getScheduledTasks(hourUtc);

  log({ event: "scheduler_start", hourUtc, tasks, hasOverride: !!cliArgs.taskOverride });

  if (tasks.length === 0) {
    log({ event: "no_tasks_scheduled", hourUtc });
    return;
  }

  const results: Array<{ taskId: TaskId; success: boolean; error?: string }> = [];

  tasks.forEach((taskId) => {
    const runner = TASK_RUNNERS.get(taskId);
    if (!runner) {
      log({ event: "unknown_task", taskId });
      results.push({ taskId, success: false, error: "no runner registered" });
      return;
    }

    try {
      runner();
      results.push({ taskId, success: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      log({ event: "task_failed", taskId, error: message });
      results.push({ taskId, success: false, error: message });
    }
  });

  const succeeded = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;

  log({ event: "scheduler_complete", hourUtc, succeeded, failed, total: results.length });

  if (failed > 0) {
    log({ event: "some_tasks_failed", failures: results.filter((r) => !r.success) });
  }
};

if (process.argv[1]?.endsWith("run-scheduled.ts")) {
  main();
}

export { main, runScript, runScriptWithOutputs, parseGitHubOutputs };
