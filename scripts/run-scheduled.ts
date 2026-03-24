#!/usr/bin/env npx tsx

/**
 * Consolidated Scheduled Task Runner
 *
 * Single entry point for all scheduled tasks. Determines which tasks to
 * run based on the current UTC hour, then executes each task by calling
 * library functions directly — no subprocesses, no GITHUB_OUTPUT passing.
 *
 * Blog series tasks use "at or after" scheduling and check whether
 * today's post already exists, making them resilient to partial failures.
 *
 * Usage:
 *   npx tsx scripts/run-scheduled.ts                     # run tasks for current hour
 *   npx tsx scripts/run-scheduled.ts --hour 15           # simulate hour 15 UTC
 *   npx tsx scripts/run-scheduled.ts --task social-posting  # run a specific task
 *
 * @module run-scheduled
 */

import fs from "node:fs";
import path from "node:path";

import {
  getScheduledTasks,
  isValidTaskId,
  BLOG_SERIES_RUN_CONFIGS,
  blogPostExistsForToday,
  type TaskId,
} from "./lib/scheduler.ts";
import { todayPacific } from "./lib/blog-series.ts";
import { generateBlogPost } from "./generate-blog-post.ts";
import {
  processNote,
  resolveImageProvider,
  resolveImageProviders,
  backfillImages,
  syncMarkdownDir,
  syncAttachmentsDir,
} from "./lib/blog-image.ts";
import { syncObsidianVault, pushObsidianVault } from "./lib/obsidian-sync.ts";
import { copySeriesPosts } from "./pull-vault-posts.ts";
import { syncFileToVault, readPreviousPostFilename } from "./sync-series-to-vault.ts";
import { run as runLinking, DEFAULT_LINKING_MODEL } from "./lib/internal-linking.ts";
import { autoPost } from "./auto-post.ts";
import { BACKFILL_CONTENT_IDS } from "./lib/blog-series-config.ts";

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

// ---------------------------------------------------------------------------
// Shared constants
// ---------------------------------------------------------------------------

const REPO_ROOT = path.resolve(import.meta.dirname, "..");
const INTER_TASK_DELAY_MS = 30_000;

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------------------
// Inference service dashboard links (logged once at scheduler start)
// ---------------------------------------------------------------------------

const INFERENCE_DASHBOARDS: ReadonlyMap<string, string> = new Map([
  ["Gemini API", "https://aistudio.google.com/apikey"],
  ["GCP Quotas", "https://console.cloud.google.com/iam-admin/quotas"],
  ["Cloudflare AI", "https://dash.cloudflare.com/?to=/:account/ai/workers-ai"],
  ["Hugging Face", "https://huggingface.co/settings/billing"],
  ["Together AI", "https://api.together.ai/settings/billing"],
]);

// ---------------------------------------------------------------------------
// Task runners — direct library calls, no subprocesses
// ---------------------------------------------------------------------------

const runBlogSeries = async (seriesId: string): Promise<void> => {
  const taskName = `blog-series:${seriesId}`;
  log({ event: "task_start", task: taskName });

  const runConfig = BLOG_SERIES_RUN_CONFIGS.get(seriesId);
  if (!runConfig) throw new Error(`No run config for series: ${seriesId}`);

  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) throw new Error("OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error("GEMINI_API_KEY is required");

  const today = todayPacific();

  // 1. Pull vault posts for this series
  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  copySeriesPosts(vaultDir, seriesId, REPO_ROOT);

  // 2. Check if today's post already exists (idempotent "at or after" scheduling)
  const seriesDir = path.join(REPO_ROOT, seriesId);
  if (blogPostExistsForToday(seriesDir, today)) {
    log({ event: "skip_already_generated", seriesId, today });
    return;
  }

  // 3. Determine model chain: env override → per-series defaults
  const envModel = process.env.BLOG_GEMINI_MODEL?.trim();
  const models = envModel ? [envModel, ...runConfig.modelChain.filter((m) => m !== envModel)] : runConfig.modelChain;
  const priorityUser = process.env[runConfig.priorityUserEnvVar]?.trim() || undefined;

  // 5. Generate blog post
  const result = await generateBlogPost({
    seriesId,
    models,
    apiKey,
    repoRoot: REPO_ROOT,
    today,
    priorityUser,
  });

  // 6. Generate blog image (continue on error)
  if (result.postPath) {
    try {
      const notePath = path.resolve(REPO_ROOT, result.postPath);
      const provider = resolveImageProvider(process.env as Record<string, string | undefined>);
      const attachmentsDir = process.env.ATTACHMENTS_DIR ?? path.join(REPO_ROOT, "attachments");
      await processNote(notePath, attachmentsDir, provider.apiKey, provider.model, provider.generator, provider.describePrompt);
      log({ event: "image_generated", postPath: result.postPath });
    } catch (error) {
      log({ event: "image_generation_failed", postPath: result.postPath, error: error instanceof Error ? error.message : String(error) });
    }
  }

  // 7. Sync to Obsidian vault
  if (result.postPath) {
    const syncVaultDir = await syncObsidianVault({ authToken, vaultName });
    let changed = false;

    const postLocal = path.join(REPO_ROOT, result.postPath);
    changed = syncFileToVault(postLocal, result.postPath, syncVaultDir) || changed;

    const metadataPath = path.join(REPO_ROOT, seriesId, ".last-generate-metadata.json");
    const previousFilename = readPreviousPostFilename(metadataPath);
    if (previousFilename) {
      const prevPath = `${seriesId}/${previousFilename}`;
      changed = syncFileToVault(path.join(REPO_ROOT, prevPath), prevPath, syncVaultDir) || changed;
    }

    const agentsPath = `${seriesId}/AGENTS.md`;
    changed = syncFileToVault(path.join(REPO_ROOT, agentsPath), agentsPath, syncVaultDir) || changed;

    const attachmentsDir = path.join(REPO_ROOT, "attachments");
    if (fs.existsSync(attachmentsDir) && fs.readdirSync(attachmentsDir).length > 0) {
      const synced = syncAttachmentsDir(attachmentsDir, syncVaultDir);
      if (synced > 0) changed = true;
    }

    if (changed) {
      await pushObsidianVault(syncVaultDir, { authToken });
      log({ event: "vault_pushed" });
    }
  }

  log({ event: "task_complete", task: taskName });
};

const runBackfillImages = async (): Promise<void> => {
  log({ event: "task_start", task: "backfill-blog-images" });

  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) throw new Error("OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");

  // 1. Pull vault posts (all series)
  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  BACKFILL_CONTENT_IDS.forEach((id) => copySeriesPosts(vaultDir, id, REPO_ROOT));

  // 2. Backfill blog images
  const providers = resolveImageProviders(process.env as Record<string, string | undefined>);
  const primary = providers[0]!;
  const fallbacks = providers.slice(1);
  const attachmentsDir = process.env.ATTACHMENTS_DIR ?? path.join(REPO_ROOT, "attachments");
  const directories = BACKFILL_CONTENT_IDS.map((id) => ({ path: path.join(REPO_ROOT, id), id }));

  try {
    const result = await backfillImages({
      directories,
      attachmentsDir,
      apiKey: primary.apiKey,
      model: primary.model,
      generate: primary.generator,
      describePrompt: primary.describePrompt,
      providerName: primary.name,
      fallbackProviders: fallbacks,
      onProgress: log,
      maxImages: 1,
    });
    log({ event: "backfill_complete", ...result });
  } catch (error) {
    log({ event: "backfill_failed", error: error instanceof Error ? error.message : String(error) });
  }

  // 3. Sync to vault
  const syncVaultDir = await syncObsidianVault({ authToken, vaultName });
  BACKFILL_CONTENT_IDS.forEach((id) => {
    const localDir = path.join(REPO_ROOT, id);
    syncMarkdownDir(localDir, id, syncVaultDir);
  });
  syncAttachmentsDir(path.join(REPO_ROOT, "attachments"), syncVaultDir);
  await pushObsidianVault(syncVaultDir, { authToken });

  log({ event: "task_complete", task: "backfill-blog-images" });
};

const runInternalLinking = async (): Promise<void> => {
  log({ event: "task_start", task: "internal-linking" });

  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) throw new Error("OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");

  // 1. Pull Obsidian vault
  const vaultDir = await syncObsidianVault({ authToken, vaultName });

  // 2. Run internal linking directly
  const model = process.env.LINKING_MODEL ?? DEFAULT_LINKING_MODEL;
  const result = await runLinking({
    contentDir: vaultDir,
    maxInferenceRequests: 1,
    apiKey: process.env.GEMINI_API_KEY,
    model,
    dryRun: false,
  });

  log({
    event: "linking_complete",
    filesVisited: result.filesVisited,
    filesModified: result.filesModified,
    totalLinksAdded: result.totalLinksAdded,
  });

  // 3. Push vault
  await pushObsidianVault(vaultDir, { authToken });

  log({ event: "task_complete", task: "internal-linking" });
};

const runSocialPosting = async (): Promise<void> => {
  log({ event: "task_start", task: "social-posting" });

  await autoPost();

  log({ event: "task_complete", task: "social-posting" });
};

const TASK_RUNNERS: ReadonlyMap<TaskId, () => Promise<void>> = new Map([
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

const main = async (): Promise<void> => {
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

  log({
    event: "scheduler_start",
    hourUtc,
    tasks,
    hasOverride: !!cliArgs.taskOverride,
    dashboards: Object.fromEntries(INFERENCE_DASHBOARDS),
  });

  if (tasks.length === 0) {
    log({ event: "no_tasks_scheduled", hourUtc });
    return;
  }

  const results: Array<{ taskId: TaskId; success: boolean; error?: string }> = [];

  for (const taskId of tasks) {
    if (results.length > 0) {
      log({ event: "inter_task_delay", delayMs: INTER_TASK_DELAY_MS });
      await sleep(INTER_TASK_DELAY_MS);
    }

    const runner = TASK_RUNNERS.get(taskId);
    if (!runner) {
      log({ event: "unknown_task", taskId });
      results.push({ taskId, success: false, error: "no runner registered" });
      continue;
    }

    try {
      await runner();
      results.push({ taskId, success: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      log({ event: "task_failed", taskId, error: message });
      results.push({ taskId, success: false, error: message });
    }
  }

  const succeeded = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;

  log({
    event: "scheduler_complete",
    hourUtc,
    succeeded,
    failed,
    total: results.length,
    tasks: results.map(({ taskId, success, error }) => ({ taskId, success, ...(error ? { error } : {}) })),
  });

  console.log("\n--- Run Summary ---");
  results.forEach(({ taskId, success, error }) =>
    console.log(`  ${success ? "✅" : "❌"} ${taskId}${error ? ` — ${error}` : ""}`),
  );
  console.log(`  📊 ${succeeded}/${results.length} succeeded`);
  console.log("-------------------\n");
};

if (process.argv[1]?.endsWith("run-scheduled.ts")) {
  main().catch((error) => {
    console.error(JSON.stringify({
      event: "fatal_error",
      message: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    }));
    process.exit(1);
  });
}

export { main };
