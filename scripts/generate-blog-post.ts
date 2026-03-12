/**
 * Blog Post Generator.
 *
 * Generates a new blog post for a specified series using the Gemini API.
 * Reads previous posts and Giscus comments (via GitHub Discussions) for context.
 *
 * Usage:
 *   npx tsx scripts/generate-blog-post.ts --series auto-blog-zero
 *   npx tsx scripts/generate-blog-post.ts --series chickie-loo --dry-run
 *
 * Environment variables:
 *   GEMINI_API_KEY       - Required. Google Gemini API key.
 *   BLOG_GEMINI_MODEL    - Optional. Model for blog generation (default: gemini-2.0-flash).
 *   BLOG_PRIORITY_USER   - Optional. GitHub user whose comments get priority.
 *   GITHUB_TOKEN         - Optional. For reading Giscus/GitHub Discussion comments.
 *
 * @module generate-blog-post
 */

import fs from "node:fs";
import path from "node:path";

import {
  BLOG_SERIES,
  buildBlogContext,
  buildBlogPrompt,
  parseGeneratedPost,
  fetchAllSeriesComments,
} from "./lib/blog-series.ts";

// --- Constants ---

const DEFAULT_BLOG_MODEL = "gemini-2.0-flash";

// --- Argument Parsing ---

interface GenerateArgs {
  readonly series: string;
  readonly dryRun: boolean;
  readonly model: string;
}

function parseArgs(): GenerateArgs {
  const args = process.argv.slice(2);
  let series = "";
  let dryRun = false;
  let model = process.env.BLOG_GEMINI_MODEL || DEFAULT_BLOG_MODEL;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--series" && args[i + 1]) {
      series = args[++i] as string;
    } else if (arg === "--dry-run") {
      dryRun = true;
    } else if (arg === "--model" && args[i + 1]) {
      model = args[++i] as string;
    }
  }

  if (!series) {
    const available = [...BLOG_SERIES.keys()].join(", ");
    console.error(`❌ --series is required. Available: ${available}`);
    process.exit(1);
  }

  if (!BLOG_SERIES.has(series)) {
    const available = [...BLOG_SERIES.keys()].join(", ");
    console.error(`❌ Unknown series: ${series}. Available: ${available}`);
    process.exit(1);
  }

  return { series, dryRun, model };
}

// --- Gemini API ---

async function callGeminiBlog(
  apiKey: string,
  model: string,
  prompt: { system: string; user: string },
): Promise<string> {
  const { GoogleGenerativeAI } = await import("@google/generative-ai");
  const genAI = new GoogleGenerativeAI(apiKey);
  const genModel = genAI.getGenerativeModel({ model });

  console.log(`🤖 Calling Gemini (${model})...`);

  const result = await genModel.generateContent({
    contents: [
      {
        role: "user",
        parts: [{ text: `${prompt.system}\n\n${prompt.user}` }],
      },
    ],
    generationConfig: {
      maxOutputTokens: 4096,
      temperature: 0.9,
    },
  });

  return result.response.text().trim();
}

// --- Slug Generation ---

function generateSlug(title: string): string {
  // Extract the part after the date and icon prefix
  // e.g., "2026-03-12 | 🤖 Some Title 🤖" → "some-title"
  const cleaned = title
    .replace(/^\d{4}-\d{2}-\d{2}\s*\|\s*/, "") // Remove date prefix
    .replace(/[\p{Emoji_Presentation}\p{Emoji}\u200d\ufe0f]/gu, "") // Remove emoji
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "") // Remove special chars
    .replace(/\s+/g, "-") // Spaces to hyphens
    .replace(/-+/g, "-") // Collapse hyphens
    .replace(/^-|-$/g, ""); // Trim hyphens

  return cleaned || "untitled";
}

// --- Main ---

async function generate(): Promise<void> {
  const config = parseArgs();
  const apiKey = process.env.GEMINI_API_KEY;

  if (!apiKey) {
    console.error("❌ GEMINI_API_KEY environment variable is required");
    process.exit(1);
  }

  const series = BLOG_SERIES.get(config.series)!;
  const repoRoot = path.resolve(import.meta.dirname, "..");
  const today = new Date().toISOString().split("T")[0] as string;

  console.log(`📝 Generating blog post for: ${series.icon} ${series.name}`);
  console.log(`📅 Date: ${today}`);
  console.log(`🤖 Model: ${config.model}`);

  // Fetch comments from Giscus (GitHub Discussions)
  const priorityUser = process.env.BLOG_PRIORITY_USER || series.defaultPriorityUser;
  console.log(`💬 Reading Giscus comments for series ${series.id}...`);
  const comments = await fetchAllSeriesComments(series.id, priorityUser);
  console.log(`   Found ${comments.length} comment(s)`);
  if (priorityUser && comments.length > 0) {
    const priorityCount = comments.filter((c) => c.isPriority).length;
    if (priorityCount > 0) {
      console.log(`   ⭐ ${priorityCount} comment(s) from priority user: ${priorityUser}`);
    }
  }

  // Build context from previous posts and comments
  const context = buildBlogContext(config.series, repoRoot, comments, today);
  console.log(`📚 Previous posts: ${context.previousPosts.length}`);

  // Build the prompt
  const prompt = buildBlogPrompt(context);

  if (config.dryRun) {
    console.log("\n--- DRY RUN: Prompt ---");
    console.log("System:", prompt.system.slice(0, 200) + "...");
    console.log("User:", prompt.user.slice(0, 500) + "...");
    console.log("--- END DRY RUN ---\n");
    return;
  }

  // Generate the blog post
  const raw = await callGeminiBlog(apiKey, config.model, prompt);

  // Strip markdown code fences if the model wrapped the output
  const cleaned = raw.replace(/^```(?:markdown|md)?\s*\n/, "").replace(/\n```\s*$/, "");

  // Validate the generated post
  const parsed = parseGeneratedPost(cleaned);
  if (!parsed) {
    console.error("❌ Generated post is malformed. Raw output:");
    console.error(cleaned.slice(0, 1000));
    process.exit(1);
  }

  console.log(`✅ Generated: ${parsed.title}`);
  console.log(`📏 Length: ${parsed.content.length} characters`);

  // Extract slug and write file
  const slug = generateSlug(parsed.title);
  const filename = `${today}-${slug}.md`;
  const seriesDir = path.join(repoRoot, series.id);

  // Ensure directory exists
  fs.mkdirSync(seriesDir, { recursive: true });

  const filePath = path.join(seriesDir, filename);

  // Check if a post for today already exists
  const existing = fs.readdirSync(seriesDir).find((f) => f.startsWith(today));
  if (existing) {
    console.log(`⚠️  A post for ${today} already exists: ${existing}`);
    console.log(`   Skipping to avoid duplicate. Delete the existing post to regenerate.`);
    return;
  }

  fs.writeFileSync(filePath, parsed.content + "\n", "utf-8");
  console.log(`💾 Written: ${filePath}`);
  console.log(`\n🎉 Blog post generated successfully!`);
  console.log(`📂 File: ${series.id}/${filename}`);
}

// --- Entry Point ---

const isMainModule = process.argv[1]?.endsWith("generate-blog-post.ts");
if (isMainModule) {
  generate().catch((error) => {
    console.error(`❌ Fatal error: ${error instanceof Error ? error.message : error}`);
    if (error instanceof Error && error.stack) {
      console.error(error.stack);
    }
    process.exit(1);
  });
}

export { generate, generateSlug, callGeminiBlog };
