/**
 * Manual test script for reflection title generation.
 *
 * Reads 5 recent reflections that already have titles, strips the title,
 * runs the title generation pipeline, and displays original vs generated
 * titles side-by-side for easy comparison.
 *
 * Usage: npx tsx scripts/test-reflection-titles.ts
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  DEFAULT_TITLE_MODEL,
  extractLinkedTitles,
  extractTrailingEmojis,
  generateReflectionTitle,
} from "./lib/reflection-title.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const REFLECTIONS_DIR = path.join(REPO_ROOT, "copy-of-reflections");

// Load .env manually (no dotenv dependency)
const envPath = path.join(REPO_ROOT, ".env");
if (fs.existsSync(envPath)) {
  fs.readFileSync(envPath, "utf-8")
    .split("\n")
    .filter((line) => line.trim() && !line.startsWith("#"))
    .forEach((line) => {
      const eqIndex = line.indexOf("=");
      if (eqIndex > 0) {
        const key = line.slice(0, eqIndex).trim();
        const value = line.slice(eqIndex + 1).trim().replace(/^["']|["']$/g, "");
        if (!process.env[key]) process.env[key] = value;
      }
    });
}

const SAMPLE_COUNT = 5;
const DELAY_BETWEEN_REQUESTS_MS = 3_000;

const delay = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

const extractCreativePart = (titleValue: string): string => {
  const pipeIndex = titleValue.indexOf(" | ");
  return pipeIndex >= 0 ? titleValue.slice(pipeIndex + 3) : "";
};

const extractRecentCreativeTitles = (excludeDate: string): readonly string[] =>
  fs.readdirSync(REFLECTIONS_DIR)
    .filter((f) => /^\d{4}-\d{2}-\d{2}\.md$/.test(f) && f < `${excludeDate}.md`)
    .sort()
    .reverse()
    .slice(0, 5)
    .flatMap((f) => {
      const content = fs.readFileSync(path.join(REFLECTIONS_DIR, f), "utf-8");
      const titleLine = content.split("\n").find((line) => /^title:\s/.test(line));
      const titleValue = titleLine?.replace(/^title:\s*/, "").trim() ?? "";
      const creative = extractCreativePart(titleValue);
      return creative ? [creative] : [];
    });

const stripExistingTitle = (content: string, date: string): string => {
  const lines = content.split("\n");
  const updatedLines = lines.map((line) => {
    if (/^title:\s/.test(line)) return `title: ${date}`;
    if (/^aliases:/.test(line)) return line;
    if (/^\s+-\s/.test(line) && lines[lines.indexOf(line) - 1]?.startsWith("aliases")) {
      return `  - ${date}`;
    }
    return line;
  });

  // Also reset H1 heading to bare date
  return updatedLines
    .map((line) => (/^#\s/.test(line) ? `# ${date}` : line))
    .join("\n");
};

const pickSamplesWithTitles = (): readonly string[] =>
  fs.readdirSync(REFLECTIONS_DIR)
    .filter((f) => /^\d{4}-\d{2}-\d{2}\.md$/.test(f))
    .sort()
    .reverse()
    .filter((f) => {
      const content = fs.readFileSync(path.join(REFLECTIONS_DIR, f), "utf-8");
      const titleLine = content.split("\n").find((line) => /^title:\s/.test(line));
      const titleValue = titleLine?.replace(/^title:\s*/, "").trim() ?? "";
      return titleValue.includes(" | ");
    })
    .slice(0, SAMPLE_COUNT);

const main = async (): Promise<void> => {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.log("⏭️  GEMINI_API_KEY not set — skipping reflection title test. Set it in .env to run locally.");
    process.exit(0);
  }

  const envModel = process.env.REFLECTION_TITLE_MODEL?.trim();
  const defaultChain = [DEFAULT_TITLE_MODEL, "gemini-2.5-flash", "gemini-2.5-flash-lite"] as const;
  const models = envModel
    ? [envModel, ...defaultChain.filter((m) => m !== envModel)]
    : [...defaultChain];

  console.log("🧪 Reflection Title Generation — Manual Test");
  console.log(`📂 Source: ${REFLECTIONS_DIR}`);
  console.log(`🤖 Model chain: ${models.join(" → ")}`);
  console.log(`⏱️  Delay between requests: ${DELAY_BETWEEN_REQUESTS_MS}ms`);
  console.log("─".repeat(80));

  const samples = pickSamplesWithTitles();
  console.log(`\n📋 Testing ${samples.length} reflections:\n`);

  for (const [i, filename] of samples.entries()) {
    const date = filename.replace(".md", "");
    const filePath = path.join(REFLECTIONS_DIR, filename);
    const originalContent = fs.readFileSync(filePath, "utf-8");

    // Extract original title
    const titleLine = originalContent.split("\n").find((line) => /^title:\s/.test(line));
    const originalTitle = titleLine?.replace(/^title:\s*/, "").trim() ?? "(none)";
    const originalCreative = extractCreativePart(originalTitle);

    // Extract linked titles for display
    const linkedTitles = extractLinkedTitles(originalContent);
    const trailingEmojis = extractTrailingEmojis(originalContent);

    // Strip the title to simulate a bare-date reflection
    const strippedContent = stripExistingTitle(originalContent, date);
    const recentTitles = extractRecentCreativeTitles(date);

    console.log(`${"═".repeat(80)}`);
    console.log(`📅 [${i + 1}/${samples.length}] ${date}`);
    console.log(`${"─".repeat(80)}`);
    console.log(`\n📖 Linked content titles (${linkedTitles.length} items):`);
    linkedTitles.forEach((t, j) => console.log(`   ${j + 1}. ${t}`));
    console.log(`\n🏷️  Trailing category emojis: ${trailingEmojis || "(none)"}`);
    console.log(`\n🏷️  Original title:  ${originalTitle}`);
    console.log(`   (Creative part): ${originalCreative}`);

    // Rate-limit: wait before calling Gemini (skip delay before first request)
    if (i > 0) {
      console.log(`\n⏳ Waiting ${DELAY_BETWEEN_REQUESTS_MS}ms before next request...`);
      await delay(DELAY_BETWEEN_REQUESTS_MS);
    }

    try {
      console.log(`\n🤖 Calling Gemini...`);
      const result = await generateReflectionTitle({
        apiKey,
        models,
        noteContent: strippedContent,
        date,
        recentTitles,
      });

      console.log(`\n✅ Generated title: ${result.fullTitle}`);
      console.log(`   (Creative part): ${result.title}`);
      console.log(`   Model used:      ${result.model}`);
      console.log(`\n   📊 Comparison:`);
      console.log(`      Original:  ${originalCreative}`);
      console.log(`      Generated: ${result.title}`);
    } catch (error) {
      console.error(`\n❌ Failed: ${error instanceof Error ? error.message : String(error)}`);
    }

    console.log();
  }

  console.log("═".repeat(80));
  console.log("🏁 Done! Review the comparisons above to evaluate title quality.");
};

main();
