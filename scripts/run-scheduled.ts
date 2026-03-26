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
  nowPacificHour,
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
import { addUpdateLinksToReflection, extractTitleFromFile } from "./lib/daily-updates.ts";
import { ensureAllNavLinks, buildReflectionLinks } from "./lib/ai-blog-links.ts";
import {
  generateFiction,
  reflectionNeedsFiction,
  DEFAULT_FICTION_MODEL,
} from "./lib/ai-fiction.ts";
import {
  reflectionNeedsTitle,
  generateReflectionTitle,
  DEFAULT_TITLE_MODEL,
} from "./lib/reflection-title.ts";

// ---------------------------------------------------------------------------
// Logging helpers
// ---------------------------------------------------------------------------

const ts = (): string => new Date().toISOString();

/**
 * Format an onProgress event from blog-image backfill into a human-readable
 * log line. Returns undefined for events that should be suppressed.
 */
const formatBackfillEvent = (e: Record<string, unknown>): string | undefined => {
  switch (e["event"]) {
    case "candidates_collected":
      return `  📊 Candidates: ${e["candidates"]} (${e["skippedWithImage"]} already have images, ${e["skippedFuture"]} future)`;
    case "generating_image":
      return `  🎨 Generating: ${e["directory"]}/${e["filename"]} [${e["provider"]}]`;
    case "regenerating_image":
      return `  ♻️  Regenerating: ${e["directory"]}/${e["filename"]} [${e["provider"]}]`;
    case "image_generated":
      return `  ✅ Generated: ${e["directory"]}/${e["filename"]} → ${e["imageName"]}`;
    case "chain_updated":
      return `  📝 Updated chain: ${e["directory"]}/ (${e["chainLength"]} files)`;
    case "max_images_reached":
      return `  ⏹️  Limit reached: ${e["imagesGenerated"]}/${e["maxImages"]} images`;
    case "rate_limit_retry":
      return `  ⏳ Rate limit, retrying in ${e["waitMs"]}ms (attempt ${e["attempt"]}/${e["maxRetries"]})`;
    case "daily_quota_exhausted":
      return `  ⚠️  Daily quota exhausted for ${e["provider"]}`;
    case "quota_exhausted":
      return `  ⚠️  Quota exhausted for ${e["provider"]}`;
    case "provider_switch":
      return `  🔄 Switching provider: ${e["from"]} → ${e["to"]} (${e["reason"]})`;
    case "provider_unavailable":
      return `  ⚠️  Provider unavailable: ${e["provider"]}`;
    case "image_generation_failed":
      return `  ❌ Failed: ${e["directory"]}/${e["filename"]} — ${e["error"]}`;
    case "directory_missing":
      return `  ⚠️  Directory missing: ${e["directory"]}`;
    default:
      return undefined;
  }
};

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
  console.log(`[${ts()}] ▶️  ${taskName}`);

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
    console.log(`  ⏭️  Already generated for ${today}`);
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
      console.log(`  🖼️  Image generated for ${result.postPath}`);
    } catch (error) {
      console.log(`  ⚠️  Image generation failed for ${result.postPath}: ${error instanceof Error ? error.message : String(error)}`);
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
      console.log("  📤 Vault pushed");
    }
  }

  console.log(`[${ts()}] ✅ ${taskName}`);
};

const runBackfillImages = async (): Promise<void> => {
  console.log(`[${ts()}] ▶️  backfill-blog-images`);

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

  const backfillLog = (e: Record<string, unknown>): void => {
    const line = formatBackfillEvent(e);
    if (line) console.log(line);
  };

  let modifiedFiles: ReadonlyArray<{ readonly relativePath: string; readonly title: string }> = [];

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
      onProgress: backfillLog,
      maxImages: 1,
    });
    console.log(`  🏁 Backfill done: ${result.imagesGenerated} image(s), ${result.filesUpdated} file(s) updated${result.stoppedByQuota ? " (stopped by quota)" : ""}`);
    modifiedFiles = result.modifiedFiles;
  } catch (error) {
    console.log(`  ❌ Backfill failed: ${error instanceof Error ? error.message : String(error)}`);
  }

  // 3. Ensure ai-blog posts have navigation links (⏮️/⏭️)
  const aiBlogDir = path.join(REPO_ROOT, "ai-blog");
  const navResults = ensureAllNavLinks(aiBlogDir);
  const navModified = navResults.filter((r) => r.modified);
  if (navModified.length > 0) {
    console.log(`  🔗 Updated nav links for ${navModified.length} ai-blog post(s): ${navModified.map((r) => r.filename).join(", ")}`);
  }

  // 4. Sync to vault and add update links to daily reflection
  const syncVaultDir = await syncObsidianVault({ authToken, vaultName });
  BACKFILL_CONTENT_IDS.forEach((id) => {
    const localDir = path.join(REPO_ROOT, id);
    syncMarkdownDir(localDir, id, syncVaultDir);
  });
  syncAttachmentsDir(path.join(REPO_ROOT, "attachments"), syncVaultDir);

  const reflectionsDir = path.join(syncVaultDir, "reflections");

  if (modifiedFiles.length > 0) {
    addUpdateLinksToReflection(reflectionsDir, todayPacific(), modifiedFiles);
  }

  // 5. Link new ai-blog posts from their respective daily reflections
  const aiBlogLinks = buildReflectionLinks(aiBlogDir, navResults);
  aiBlogLinks.forEach(({ relativePath, title, date }) => {
    addUpdateLinksToReflection(reflectionsDir, date, [{ relativePath, title }]);
  });

  await pushObsidianVault(syncVaultDir, { authToken });

  console.log(`[${ts()}] ✅ backfill-blog-images`);
};

const runInternalLinking = async (): Promise<void> => {
  console.log(`[${ts()}] ▶️  internal-linking`);

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

  console.log(`  🏁 Linking done: ${result.filesVisited} visited, ${result.filesModified} modified, ${result.totalLinksAdded} links added, ${result.filesSkipped} skipped`);

  // 3. Add update links to daily reflection for modified files
  const modifiedResults = result.fileResults.filter((r) => r.modified);
  if (modifiedResults.length > 0) {
    const reflectionsDir = path.join(vaultDir, "reflections");
    const links = modifiedResults.map((r) => ({
      relativePath: r.relativePath,
      title: extractTitleFromFile(path.join(vaultDir, r.relativePath)),
    }));
    addUpdateLinksToReflection(reflectionsDir, todayPacific(), links);
  }

  // 4. Push vault
  await pushObsidianVault(vaultDir, { authToken });

  console.log(`[${ts()}] ✅ internal-linking`);
};

const runSocialPosting = async (): Promise<void> => {
  console.log(`[${ts()}] ▶️  social-posting`);

  await autoPost();

  console.log(`[${ts()}] ✅ social-posting`);
};

const RECENT_TITLE_COUNT = 20;

const extractRecentCreativeTitles = (reflectionsDir: string, today: string): readonly string[] => {
  if (!fs.existsSync(reflectionsDir)) return [];

  return fs.readdirSync(reflectionsDir)
    .filter((f) => /^\d{4}-\d{2}-\d{2}\.md$/.test(f) && f < `${today}.md`)
    .sort()
    .reverse()
    .slice(0, RECENT_TITLE_COUNT)
    .flatMap((f) => {
      const content = fs.readFileSync(path.join(reflectionsDir, f), "utf-8");
      const titleLine = content.split("\n").find((line) => /^title:\s/.test(line));
      const titleValue = titleLine?.replace(/^title:\s*/, "").trim() ?? "";
      const pipeIndex = titleValue.indexOf(" | ");
      return pipeIndex >= 0 ? [titleValue.slice(pipeIndex + 3)] : [];
    });
};

/**
 * Compute yesterday's date in Pacific time.
 */
const yesterdayPacific = (): string => {
  const now = new Date();
  const pacificDate = new Date(now.toLocaleString("en-US", { timeZone: "America/Los_Angeles" }));
  pacificDate.setDate(pacificDate.getDate() - 1);
  return pacificDate.toLocaleDateString("en-CA");
};

/**
 * Try to generate a title for the given date's reflection.
 * Returns true if a title was generated, false if skipped.
 */
const tryTitleForDate = async (
  date: string,
  reflectionsDir: string,
  vaultDir: string,
  apiKey: string,
  authToken: string,
): Promise<boolean> => {
  const reflectionPath = path.join(reflectionsDir, `${date}.md`);

  if (!fs.existsSync(reflectionPath)) {
    console.log(`  ⏭️  No reflection note for ${date}`);
    return false;
  }

  const content = fs.readFileSync(reflectionPath, "utf-8");
  if (!reflectionNeedsTitle(content, date)) {
    console.log(`  ⏭️  Reflection title already set for ${date}`);
    return false;
  }

  const recentTitles = extractRecentCreativeTitles(reflectionsDir, date);
  console.log(`  📋 Found ${recentTitles.length} recent titles for style reference`);

  const envModel = process.env.REFLECTION_TITLE_MODEL?.trim();
  const defaultChain = [DEFAULT_TITLE_MODEL, "gemini-2.5-flash-lite", "gemini-3.1-flash-lite-preview"] as const;
  const models = envModel
    ? [envModel, ...defaultChain.filter((m) => m !== envModel)]
    : [...defaultChain];

  const result = await generateReflectionTitle({
    apiKey,
    models,
    noteContent: content,
    date,
    recentTitles,
  });

  console.log(`  🏷️  Generated title: ${result.fullTitle} [${result.model}]`);

  fs.writeFileSync(reflectionPath, result.updatedContent, "utf-8");
  await pushObsidianVault(vaultDir, { authToken });
  console.log("  📤 Vault pushed");
  return true;
};

const runAiFiction = async (): Promise<void> => {
  console.log(`[${ts()}] ▶️  ai-fiction`);

  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) throw new Error("OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error("GEMINI_API_KEY is required");

  const today = todayPacific();

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  const reflectionsDir = path.join(vaultDir, "reflections");
  const reflectionPath = path.join(reflectionsDir, `${today}.md`);

  if (!fs.existsSync(reflectionPath)) {
    console.log(`  📭 No reflection for ${today}, skipping AI fiction`);
    console.log(`[${ts()}] ✅ ai-fiction (skipped)`);
    return;
  }

  const noteContent = fs.readFileSync(reflectionPath, "utf-8");

  if (!reflectionNeedsFiction(noteContent)) {
    console.log(`  ✅ Reflection ${today} already has AI fiction`);
    console.log(`[${ts()}] ✅ ai-fiction (already done)`);
    return;
  }

  const envModel = process.env.FICTION_MODEL;
  const defaultChain = [DEFAULT_FICTION_MODEL, "gemini-2.5-flash-lite", "gemini-3.1-flash-lite-preview"];
  const models = envModel ? [envModel, ...defaultChain] : defaultChain;

  const result = await generateFiction({
    apiKey,
    models,
    noteContent,
  });

  console.log(`  🤖🐲 Generated fiction (model=${result.model}, ${result.fiction.split(/\s+/).length} words)`);
  fs.writeFileSync(reflectionPath, result.updatedContent, "utf-8");
  console.log(`  ✏️  Updated ${today}.md with AI fiction`);

  await pushObsidianVault(vaultDir, { authToken });

  console.log(`[${ts()}] ✅ ai-fiction`);
};

const runReflectionTitle = async (): Promise<void> => {
  console.log(`[${ts()}] ▶️  reflection-title`);

  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) throw new Error("OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error("GEMINI_API_KEY is required");

  const today = todayPacific();
  const yesterday = yesterdayPacific();

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  const reflectionsDir = path.join(vaultDir, "reflections");

  // Try today first, then yesterday (resilient catchup)
  const todayDone = await tryTitleForDate(today, reflectionsDir, vaultDir, apiKey, authToken);
  if (!todayDone) {
    console.log(`  📅 Checking yesterday (${yesterday})...`);
    await tryTitleForDate(yesterday, reflectionsDir, vaultDir, apiKey, authToken);
  }

  console.log(`[${ts()}] ✅ reflection-title`);
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
  ["ai-fiction", runAiFiction],
  ["reflection-title", runReflectionTitle],
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
  const hourPacific = cliArgs.hourOverride ?? nowPacificHour();

  const tasks: readonly TaskId[] = cliArgs.taskOverride
    ? isValidTaskId(cliArgs.taskOverride)
      ? [cliArgs.taskOverride]
      : (() => {
          console.error(`❌ Unknown task: ${cliArgs.taskOverride}`);
          process.exit(1);
        })()
    : getScheduledTasks(hourPacific);

  console.log(`\n🕐 [${ts()}] Scheduler start — hour ${hourPacific} Pacific, ${tasks.length} task(s): ${tasks.join(", ")}`);
  console.log("📊 Inference dashboards:");
  INFERENCE_DASHBOARDS.forEach((url, name) => console.log(`   ${name}: ${url}`));

  if (tasks.length === 0) {
    console.log("  ⏭️  No tasks scheduled for this hour");
    return;
  }

  const results: Array<{ taskId: TaskId; success: boolean; error?: string }> = [];

  for (const taskId of tasks) {
    if (results.length > 0) {
      console.log(`⏳ Inter-task delay: ${INTER_TASK_DELAY_MS / 1000}s`);
      await sleep(INTER_TASK_DELAY_MS);
    }

    const runner = TASK_RUNNERS.get(taskId);
    if (!runner) {
      console.log(`  ⚠️  Unknown task: ${taskId}`);
      results.push({ taskId, success: false, error: "no runner registered" });
      continue;
    }

    try {
      await runner();
      results.push({ taskId, success: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.log(`[${ts()}] ❌ ${taskId} — ${message}`);
      results.push({ taskId, success: false, error: message });
    }
  }

  const succeeded = results.filter((r) => r.success).length;

  console.log("\n--- Run Summary ---");
  results.forEach(({ taskId, success, error }) =>
    console.log(`  ${success ? "✅" : "❌"} ${taskId}${error ? ` — ${error}` : ""}`),
  );
  console.log(`  📊 ${succeeded}/${results.length} succeeded`);
  console.log("-------------------\n");
};

if (process.argv[1]?.endsWith("run-scheduled.ts")) {
  main().catch((error) => {
    console.error(`💀 Fatal: ${error instanceof Error ? error.message : String(error)}`);
    if (error instanceof Error && error.stack) console.error(error.stack);
    process.exit(1);
  });
}

export { main };
