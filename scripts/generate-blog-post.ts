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

const isQuotaError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const message = String((error as { message?: string }).message ?? "");
  return message.includes("429") || message.includes("RESOURCE_EXHAUSTED") || message.includes("quota");
};

const callGemini = async (
  apiKey: string,
  model: string,
  prompt: { system: string; user: string },
): Promise<string> => {
  const { GoogleGenAI } = await import("@google/genai");
  const ai = new GoogleGenAI({ apiKey });

  const groundingRequested = process.env.BLOG_ENABLE_GROUNDING !== "false";
  const contents = [{ role: "user" as const, parts: [{ text: `${prompt.system}\n\n${prompt.user}` }] }];

  const attempt = async (grounding: boolean): Promise<string> => {
    const tools = grounding ? [{ googleSearch: {} }] : undefined;
    log({ event: "gemini_request_body", model, temperature: 0.9, grounding, systemPrompt: prompt.system, userPrompt: prompt.user });
    const result = await ai.models.generateContent({ model, contents, config: { temperature: 0.9, tools } });
    const text = (result.text ?? "").trim();
    log({ event: "gemini_response", model, responseLength: text.length, grounding });
    return text;
  };

  if (groundingRequested) {
    try {
      return await attempt(true);
    } catch (error) {
      if (isQuotaError(error)) {
        log({ event: "grounding_fallback", reason: "quota_exhausted", model });
        return await attempt(false);
      }
      throw error;
    }
  }

  return await attempt(false);
};

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

const updateReflectionIfCredentialsAvailable = async (
  series: { readonly id: string; readonly name: string; readonly icon: string },
  today: string,
  filename: string,
  title: string,
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

  const result = updateDailyReflection(vaultDir, today, seriesConfig, filename, title);
  log({ event: "reflection_updated", ...result });

  const hasChanges = result.reflectionCreated || result.sectionCreated || result.linkInserted || result.forwardLinkAdded;
  if (hasChanges) {
    await pushObsidianVault(vaultDir, { authToken });
    log({ event: "vault_pushed_reflection" });
  } else {
    log({ event: "reflection_no_changes" });
  }
};

const generate = async (): Promise<void> => {
  const config = parseArgs(process.argv);
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) { console.error("❌ GEMINI_API_KEY is required"); process.exit(1); }

  const series = BLOG_SERIES.get(config.series);
  if (!series) { console.error("❌ Series not found"); process.exit(1); }

  const repoRoot = path.resolve(import.meta.dirname, "..");
  const today = todayPacific();

  log({ event: "generate_start", series: series.id, seriesName: series.name, today, model: config.model });

  const seriesDir = path.join(repoRoot, series.id);
  const existingPost = fs.existsSync(seriesDir) && fs.readdirSync(seriesDir).find((f) => f.startsWith(today));
  if (existingPost) {
    log({ event: "skip_duplicate", today, existingPost });
    return;
  }

  const priorityUser = process.env.BLOG_PRIORITY_USER ?? series.priorityUser;
  const comments = await fetchAllSeriesComments(series.id, priorityUser);
  const priorityCount = comments.filter((c) => c.isPriority).length;
  log({ event: "comments_fetched", total: comments.length, priority: priorityCount, priorityUser });

  const context = buildBlogContext(config.series, repoRoot, comments, today);
  const commentCutoff = context.previousPosts.length > 0
    ? `${context.previousPosts[0]!.date}T${series.postTimeUtc}:00Z`
    : undefined;
  log({
    event: "context_built",
    previousPostCount: context.previousPosts.length,
    newestPost: context.previousPosts[0]?.filename,
    newestPostDate: context.previousPosts[0]?.date,
    commentCutoff,
    rawCommentCount: comments.length,
    filteredCommentCount: context.comments.length,
    hasAgentsMd: context.agentsMd.length > 0,
  });

  const prompt = buildBlogPrompt(context);

  if (config.dryRun) {
    log({ event: "dry_run", systemPreview: prompt.system.slice(0, 200), userPreview: prompt.user.slice(0, 500) });
    return;
  }

  const raw = await callGemini(apiKey, config.model, prompt);
  const parsed = parseGeneratedPost(stripCodeFences(raw));
  if (!parsed) {
    log({ event: "generation_failed", rawPreview: raw.slice(0, 500) });
    process.exit(1);
  }

  const slug = generateSlug(parsed.title);
  const previousPost = context.previousPosts[0];
  const frontmatter = assembleFrontmatter(series, today, parsed.title, slug, previousPost);
  const bodyWithSignature = appendModelSignature(parsed.body, config.model);
  const filename = `${today}-${slug}.md`;
  fs.mkdirSync(seriesDir, { recursive: true });
  fs.writeFileSync(path.join(seriesDir, filename), frontmatter + bodyWithSignature + "\n", "utf-8");
  log({ event: "post_written", filename, title: parsed.title, contentLength: parsed.body.length, slug });
  if (previousPost) {
    updatePreviousPost(seriesDir, previousPost, series, filename);
    const metadataPath = path.join(seriesDir, ".last-generate-metadata.json");
    fs.writeFileSync(metadataPath, JSON.stringify({ previousPostFilename: previousPost.filename, newPostFilename: filename }), "utf-8");
    log({ event: "previous_post_updated", previousPost: previousPost.filename, forwardLinkTarget: filename });
  } else {
    log({ event: "no_previous_post", reason: "first post in series" });
  }

  const postRelativePath = `${series.id}/${filename}`;
  writeGitHubOutput("post", postRelativePath);

  await updateReflectionIfCredentialsAvailable(series, today, filename, parsed.title);

  log({ event: "generate_complete", series: series.id, filename, backLinkTarget: previousPost?.filename });
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

export { generate, callGemini };
