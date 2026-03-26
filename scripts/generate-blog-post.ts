#!/usr/bin/env npx tsx

import fs from "node:fs";
import path from "node:path";
import {
  BLOG_SERIES,
  buildBlogContext,
  buildBlogPrompt,
  assembleFrontmatter,
  parseGeneratedPost,
  fetchAllSeriesComments,
  todayPacific,
  appendModelSignature,
  updatePreviousPost,
} from "./lib/blog-series.ts";
import { updateDailyReflection } from "./lib/daily-reflection.ts";
import { syncObsidianVault, pushObsidianVault } from "./lib/obsidian-sync.ts";

const DEFAULT_BLOG_MODEL = "gemini-3.1-flash-lite-preview";

interface GenerateArgs {
  readonly series: string;
  readonly dryRun: boolean;
  readonly model: string;
}

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

const parseArgs = (argv: readonly string[]): GenerateArgs => {
  const args = argv.slice(2);
  const flagValue = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    return idx >= 0 && idx + 1 < args.length ? (args[idx + 1] as string) : undefined;
  };

  const series = flagValue("--series") ?? "";
  const model = flagValue("--model") ?? process.env.BLOG_GEMINI_MODEL ?? DEFAULT_BLOG_MODEL;
  const dryRun = args.includes("--dry-run");

  if (!series || !BLOG_SERIES.has(series)) {
    const available = [...BLOG_SERIES.keys()].join(", ");
    console.error(`❌ --series is required. Available: ${available}`);
    process.exit(1);
  }

  return { series, dryRun, model };
};

// ---------------------------------------------------------------------------
// Error classification
// ---------------------------------------------------------------------------

const isQuotaError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const message = String((error as { message?: string }).message ?? "");
  return message.includes("429") || message.includes("RESOURCE_EXHAUSTED") || message.includes("quota");
};

const isRetriableError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const status = (error as { status?: number }).status;
  const message = String((error as { message?: string }).message ?? "");
  return (
    isQuotaError(error) ||
    status === 429 ||
    (status !== undefined && status >= 500 && status < 600) ||
    message.includes("503") ||
    message.includes("502") ||
    message.includes("500") ||
    message.includes("504") ||
    message.includes("INTERNAL") ||
    message.includes("UNAVAILABLE")
  );
};

// ---------------------------------------------------------------------------
// Gemini API calls with retry and model fallback
// ---------------------------------------------------------------------------

const GEMINI_MAX_RETRIES = 3;
const GEMINI_BASE_DELAY_MS = 2_000;

const delay = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

const callGeminiOnce = async (
  apiKey: string,
  model: string,
  prompt: { system: string; user: string },
  grounding: boolean,
): Promise<string> => {
  const { GoogleGenAI } = await import("@google/genai");
  const ai = new GoogleGenAI({ apiKey });
  const tools = grounding ? [{ googleSearch: {} }] : undefined;
  const contents = [{ role: "user" as const, parts: [{ text: `${prompt.system}\n\n${prompt.user}` }] }];

  log({ event: "gemini_request", model, grounding });
  const result = await ai.models.generateContent({ model, contents, config: { temperature: 0.9, tools } });
  const text = (result.text ?? "").trim();
  log({ event: "gemini_response", model, responseLength: text.length, grounding });
  return text;
};

const callGeminiWithRetry = async (
  apiKey: string,
  model: string,
  prompt: { system: string; user: string },
  grounding: boolean,
): Promise<string> => {
  for (let attempt = 0; attempt <= GEMINI_MAX_RETRIES; attempt++) {
    try {
      return await callGeminiOnce(apiKey, model, prompt, grounding);
    } catch (error) {
      if (attempt < GEMINI_MAX_RETRIES && isRetriableError(error)) {
        const delayMs = GEMINI_BASE_DELAY_MS * 2 ** attempt;
        log({ event: "gemini_retry", model, attempt: attempt + 1, delayMs, error: error instanceof Error ? error.message : String(error) });
        await delay(delayMs);
        continue;
      }
      throw error;
    }
  }
  throw new Error(`Exhausted ${GEMINI_MAX_RETRIES} retries for model ${model}`);
};

/**
 * Calls Gemini with a chain of fallback models and 5XX retry.
 *
 * For each model in the chain:
 *   1. Try with grounding (if enabled)
 *   2. Fall back to no-grounding on quota errors
 *   3. Retry on transient 5XX/429 errors with exponential backoff
 *   4. Move to the next model on persistent failure
 */
const callGemini = async (
  apiKey: string,
  models: readonly string[],
  prompt: { system: string; user: string },
): Promise<{ text: string; model: string }> => {
  const groundingRequested = process.env.BLOG_ENABLE_GROUNDING !== "false";

  for (let i = 0; i < models.length; i++) {
    const model = models[i]!;
    const isLast = i === models.length - 1;

    try {
      if (groundingRequested) {
        try {
          const text = await callGeminiWithRetry(apiKey, model, prompt, true);
          return { text, model };
        } catch (error) {
          if (isQuotaError(error)) {
            log({ event: "grounding_fallback", reason: "quota_exhausted", model });
            const text = await callGeminiWithRetry(apiKey, model, prompt, false);
            return { text, model };
          }
          throw error;
        }
      }

      const text = await callGeminiWithRetry(apiKey, model, prompt, false);
      return { text, model };
    } catch (error) {
      log({ event: "model_failed", model, error: error instanceof Error ? error.message : String(error) });
      if (isLast) throw error;
      log({ event: "trying_fallback_model", failedModel: model, nextModel: models[i + 1] });
    }
  }

  throw new Error("All models exhausted");
};

// ---------------------------------------------------------------------------
// Slug generation + helpers
// ---------------------------------------------------------------------------

export const generateSlug = (title: string): string => {
  const slug = title
    .replace(/[\p{Emoji_Presentation}\p{Emoji}\u200d\ufe0f]/gu, "")
    .trim().toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "").replace(/\s+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");

  if (!slug) throw new Error("Failed to generate slug from title");
  return slug;
};

const stripCodeFences = (raw: string): string =>
  raw.replace(/^```(?:markdown|md)?\s*\n/, "").replace(/\n```\s*$/, "");

const writeGitHubOutput = (key: string, value: string): void => {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (outputPath) {
    fs.appendFileSync(outputPath, `${key}=${value}\n`);
    log({ event: "github_output_written", key, value });
  }
};

// ---------------------------------------------------------------------------
// Callable library function
// ---------------------------------------------------------------------------

export interface GenerateBlogPostConfig {
  readonly seriesId: string;
  readonly models: readonly string[];
  readonly apiKey: string;
  readonly repoRoot: string;
  readonly today: string;
  readonly priorityUser?: string;
  readonly dryRun?: boolean;
  readonly regeneratingFilename?: string;
}

export interface GenerateBlogPostResult {
  readonly postPath: string | undefined;
  readonly filename: string | undefined;
  readonly title: string | undefined;
  readonly skipped: boolean;
  readonly reason?: string;
  readonly model?: string;
}

const updateReflectionIfCredentialsAvailable = async (
  series: { readonly id: string; readonly name: string; readonly icon: string },
  today: string,
  filename: string,
  title: string,
  replacingFilename?: string,
): Promise<void> => {
  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) {
    log({ event: "reflection_skip", reason: "no_obsidian_credentials" });
    return;
  }

  const vaultDir = await syncObsidianVault({ authToken, vaultName });
  log({ event: "vault_synced_for_reflection", vaultDir });

  const seriesConfig = BLOG_SERIES.get(series.id);
  if (!seriesConfig) {
    log({ event: "reflection_skip", reason: "series_not_in_config", seriesId: series.id });
    return;
  }

  const result = updateDailyReflection(vaultDir, today, seriesConfig, filename, title, replacingFilename);
  log({ event: "reflection_updated", ...result });

  const hasChanges = result.reflectionCreated || result.sectionCreated || result.linkInserted || result.forwardLinkAdded;
  if (hasChanges) {
    await pushObsidianVault(vaultDir, { authToken });
    log({ event: "vault_pushed_reflection" });
  } else {
    log({ event: "reflection_no_changes" });
  }
};

/**
 * Generate a blog post for a series. Callable as a library function.
 *
 * Tries each model in the chain with 5XX retry and grounding fallback.
 * Returns the post path (or undefined if skipped/dry-run).
 */
export const generateBlogPost = async (config: GenerateBlogPostConfig): Promise<GenerateBlogPostResult> => {
  const series = BLOG_SERIES.get(config.seriesId);
  if (!series) throw new Error(`Unknown series: ${config.seriesId}`);

  log({ event: "generate_start", series: series.id, seriesName: series.name, today: config.today, models: config.models });

  const seriesDir = path.join(config.repoRoot, series.id);
  const existingPost = fs.existsSync(seriesDir) && fs.readdirSync(seriesDir).find((f) => f.startsWith(config.today));
  if (existingPost) {
    log({ event: "skip_duplicate", today: config.today, existingPost });
    return { postPath: undefined, filename: undefined, title: undefined, skipped: true, reason: "already_exists" };
  }

  const priorityUser = config.priorityUser ?? series.priorityUser;
  const comments = await fetchAllSeriesComments(series.id, priorityUser);
  const priorityCount = comments.filter((c) => c.isPriority).length;
  log({ event: "comments_fetched", total: comments.length, priority: priorityCount, priorityUser });

  const context = buildBlogContext(config.seriesId, config.repoRoot, comments, config.today);
  log({
    event: "context_built",
    previousPostCount: context.previousPosts.length,
    newestPost: context.previousPosts[0]?.filename,
    filteredCommentCount: context.comments.length,
    hasAgentsMd: context.agentsMd.length > 0,
  });

  const prompt = buildBlogPrompt(context);

  if (config.dryRun) {
    log({ event: "dry_run", systemPreview: prompt.system.slice(0, 200), userPreview: prompt.user.slice(0, 500) });
    return { postPath: undefined, filename: undefined, title: undefined, skipped: true, reason: "dry_run" };
  }

  const { text: raw, model: usedModel } = await callGemini(config.apiKey, config.models, prompt);
  const parsed = parseGeneratedPost(stripCodeFences(raw));
  if (!parsed) {
    log({ event: "generation_failed", rawPreview: raw.slice(0, 500) });
    throw new Error("Failed to parse generated blog post");
  }

  const slug = generateSlug(parsed.title);
  const previousPost = context.previousPosts[0];
  const frontmatter = assembleFrontmatter(series, config.today, parsed.title, slug, previousPost);
  const bodyWithSignature = appendModelSignature(parsed.body, usedModel);
  const filename = `${config.today}-${slug}.md`;
  fs.mkdirSync(seriesDir, { recursive: true });
  fs.writeFileSync(path.join(seriesDir, filename), frontmatter + bodyWithSignature + "\n", "utf-8");
  log({ event: "post_written", filename, title: parsed.title, contentLength: parsed.body.length, slug, model: usedModel });
  if (previousPost) {
    updatePreviousPost(seriesDir, previousPost, series, filename);
    const metadataPath = path.join(seriesDir, ".last-generate-metadata.json");
    fs.writeFileSync(metadataPath, JSON.stringify({ previousPostFilename: previousPost.filename, newPostFilename: filename }), "utf-8");
    log({ event: "previous_post_updated", previousPost: previousPost.filename, forwardLinkTarget: filename });
  }

  const postRelativePath = `${series.id}/${filename}`;

  await updateReflectionIfCredentialsAvailable(series, config.today, filename, parsed.title, config.regeneratingFilename);

  log({ event: "generate_complete", series: series.id, filename, model: usedModel });

  return { postPath: postRelativePath, filename, title: parsed.title, skipped: false, model: usedModel };
};

// ---------------------------------------------------------------------------
// CLI entry point (standalone use)
// ---------------------------------------------------------------------------

const generate = async (): Promise<void> => {
  const config = parseArgs(process.argv);
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) { console.error("❌ GEMINI_API_KEY is required"); process.exit(1); }

  const repoRoot = path.resolve(import.meta.dirname, "..");
  const today = todayPacific();

  const result = await generateBlogPost({
    seriesId: config.series,
    models: [config.model],
    apiKey,
    repoRoot,
    today,
    dryRun: config.dryRun,
  });

  if (result.postPath) {
    writeGitHubOutput("post", result.postPath);
  }
};

if (process.argv[1]?.endsWith("generate-blog-post.ts")) {
  generate().catch((error) => {
    console.error(JSON.stringify({
      event: "fatal_error",
      message: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    }));
    process.exit(1);
  });
}

export { generate, isRetriableError, isQuotaError };
