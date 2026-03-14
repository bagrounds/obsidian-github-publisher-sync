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
} from "./lib/blog-series.ts";

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

const callGemini = async (
  apiKey: string,
  model: string,
  prompt: { system: string; user: string },
): Promise<string> => {
  const { GoogleGenerativeAI } = await import("@google/generative-ai");
  const genModel = new GoogleGenerativeAI(apiKey).getGenerativeModel({ model });
  log({ event: "gemini_call", model, systemLength: prompt.system.length, userLength: prompt.user.length });

  const maxOutputTokens = parseInt(process.env.BLOG_MAX_OUTPUT_TOKENS ?? "4096", 10);
  const result = await genModel.generateContent({
    contents: [{ role: "user", parts: [{ text: `${prompt.system}\n\n${prompt.user}` }] }],
    generationConfig: { maxOutputTokens, temperature: 0.9 },
  });

  const text = result.response.text().trim();
  log({ event: "gemini_response", model, responseLength: text.length });
  return text;
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
  log({ event: "context_built", previousPosts: context.previousPosts.length, hasAgentsMd: context.agentsMd.length > 0 });

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
  const frontmatter = assembleFrontmatter(series, today, parsed.title, slug);
  const bodyWithSignature = appendModelSignature(parsed.body, config.model);
  const filename = `${today}-${slug}.md`;
  fs.mkdirSync(seriesDir, { recursive: true });
  fs.writeFileSync(path.join(seriesDir, filename), frontmatter + bodyWithSignature + "\n", "utf-8");

  log({ event: "post_written", filename, title: parsed.title, contentLength: parsed.body.length });
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
