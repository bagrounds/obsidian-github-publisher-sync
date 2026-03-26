/**
 * AI Fiction Generation for Daily Reflections
 *
 * Generates a short, engaging fiction piece for the daily reflection note.
 * The fiction is thematically inspired by the day's content — books, videos,
 * blog posts, etc. — abstracted into creative themes.
 *
 * Style rules:
 * - Each sentence begins with an emoji
 * - No quotation marks
 * - Under 100 words
 * - Evocative, slightly philosophical tone
 *
 * Pure functions handle content prep and application; Gemini handles creative
 * fiction writing.
 *
 * @module ai-fiction
 */

import { isRetriableError } from "../generate-blog-post.ts";
import {
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  MASTODON_SECTION_HEADER,
} from "./types.ts";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const FICTION_SECTION_HEADER = "## 🤖🐲 AI Fiction";
export const DEFAULT_FICTION_MODEL = "gemini-2.5-flash";

const GEMINI_MAX_RETRIES = 3;
const GEMINI_BASE_DELAY_MS = 2_000;

const EMBED_HEADERS = [
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  MASTODON_SECTION_HEADER,
] as const;

// ---------------------------------------------------------------------------
// Pure Functions
// ---------------------------------------------------------------------------

/**
 * Strip frontmatter and embed sections from reflection content,
 * leaving only the substantive content for fiction prompt construction.
 */
export const stripForPrompt = (content: string): string => {
  const lines = content.split("\n");

  // Strip frontmatter
  const hasFrontmatter = lines[0]?.trim() === "---";
  const fmEnd = hasFrontmatter
    ? lines.findIndex((l, i) => i > 0 && l.trim() === "---")
    : -1;
  const bodyLines = fmEnd >= 0 ? lines.slice(fmEnd + 1) : lines;
  const body = bodyLines.join("\n");

  // Strip embed sections (everything from first embed header onward)
  const firstEmbedIndex = EMBED_HEADERS
    .map((header) => body.indexOf(header))
    .filter((index) => index >= 0)
    .reduce((min, index) => Math.min(min, index), body.length);

  // Also strip the existing AI Fiction section if present
  const fictionIndex = body.indexOf(FICTION_SECTION_HEADER);
  const cutoff = fictionIndex >= 0
    ? Math.min(fictionIndex, firstEmbedIndex)
    : firstEmbedIndex;

  // Strip the Updates section if present
  const updatesIndex = body.indexOf("## 🔄 Updates");
  const finalCutoff = updatesIndex >= 0
    ? Math.min(updatesIndex, cutoff)
    : cutoff;

  return body.slice(0, finalCutoff).trim();
};

/**
 * Check whether a reflection note already has an AI Fiction section.
 */
export const reflectionNeedsFiction = (content: string): boolean =>
  !content.includes(FICTION_SECTION_HEADER);

/**
 * Build the Gemini prompt for fiction generation.
 */
export const buildFictionPrompt = (
  strippedContent: string,
): { readonly system: string; readonly user: string } => {
  const system = `You are a creative fiction writer. Your task is to:

1. Read the content from today's daily reflection note
2. Identify 2-4 abstract themes from the content
3. Write a short piece of engaging fiction (UNDER 100 words) inspired by those themes

RULES:
- Every sentence MUST begin with an emoji
- NEVER use quotation marks (no ", no ', no \`, no curly quotes)
- Keep it under 100 words
- The fiction should be evocative and slightly philosophical
- Abstract the themes — do NOT directly reference the specific books, videos, or articles
- Do NOT include any heading or title — just the fiction text
- Output ONLY the fiction — no explanation, no theme list, no preamble`;

  const user = `Write a short fiction piece inspired by themes from this daily reflection:\n\n${strippedContent}`;

  return { system, user };
};

/**
 * Parse and clean the raw Gemini response.
 * Strips code fences, removes quotation marks, and trims whitespace.
 */
export const parseFictionResponse = (raw: string): string =>
  raw
    .replace(/^```(?:markdown|md)?\s*\n/, "")
    .replace(/\n```\s*$/, "")
    .replace(/^## 🤖🐲 AI Fiction\s*\n*/m, "")
    .replace(/[\u0022\u0027\u0060\u2018\u2019\u201C\u201D]/g, "")
    .trim();

/**
 * Insert an AI Fiction section into the reflection note content.
 * Places it just before the first embed section, or at the end.
 */
export const applyFiction = (content: string, fiction: string): string => {
  const sectionBlock = `${FICTION_SECTION_HEADER}\n\n${fiction}`;

  // Find the first embed section to insert before
  const embedIndices = EMBED_HEADERS
    .map((header) => content.indexOf(header))
    .filter((index) => index >= 0);
  const firstEmbedIndex = embedIndices.length > 0 ? Math.min(...embedIndices) : -1;

  // Also check for Updates section — insert before it too
  const updatesIndex = content.indexOf("## 🔄 Updates");
  const candidates = [firstEmbedIndex, updatesIndex].filter((i) => i >= 0);
  const insertBeforeIndex = candidates.length > 0 ? Math.min(...candidates) : -1;

  return insertBeforeIndex >= 0
    ? `${content.slice(0, insertBeforeIndex).trimEnd()}\n\n${sectionBlock}\n\n${content.slice(insertBeforeIndex)}`
    : `${content.trimEnd()}\n\n${sectionBlock}\n`;
};

// ---------------------------------------------------------------------------
// Gemini API
// ---------------------------------------------------------------------------

const delay = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

const callGeminiOnce = async (
  apiKey: string,
  model: string,
  prompt: { readonly system: string; readonly user: string },
): Promise<string> => {
  const { GoogleGenAI } = await import("@google/genai");
  const ai = new GoogleGenAI({ apiKey });
  const contents = [
    { role: "user" as const, parts: [{ text: `${prompt.system}\n\n${prompt.user}` }] },
  ];
  const result = await ai.models.generateContent({
    model,
    contents,
    config: { temperature: 1.0 },
  });
  return (result.text ?? "").trim();
};

const callGeminiWithRetry = async (
  apiKey: string,
  model: string,
  prompt: { readonly system: string; readonly user: string },
): Promise<string> => {
  for (let attempt = 0; attempt <= GEMINI_MAX_RETRIES; attempt++) {
    try {
      return await callGeminiOnce(apiKey, model, prompt);
    } catch (error) {
      if (attempt < GEMINI_MAX_RETRIES && isRetriableError(error)) {
        const delayMs = GEMINI_BASE_DELAY_MS * 2 ** attempt;
        console.log(`  ⏳ AI fiction retry: model=${model}, attempt=${attempt + 1}, delay=${delayMs}ms`);
        await delay(delayMs);
        continue;
      }
      throw error;
    }
  }
  throw new Error(`Exhausted ${GEMINI_MAX_RETRIES} retries for model ${model}`);
};

export const callGeminiModelChain = async (
  apiKey: string,
  models: readonly string[],
  prompt: { readonly system: string; readonly user: string },
): Promise<{ readonly text: string; readonly model: string }> => {
  for (let i = 0; i < models.length; i++) {
    const model = models[i]!;
    const isLast = i === models.length - 1;
    try {
      const text = await callGeminiWithRetry(apiKey, model, prompt);
      return { text, model };
    } catch (error) {
      console.log(`  ⚠️  Model ${model} failed: ${error instanceof Error ? error.message : String(error)}`);
      if (isLast) throw error;
      console.log(`  🔄 Trying fallback: ${models[i + 1]}`);
    }
  }
  throw new Error("All models exhausted");
};

// ---------------------------------------------------------------------------
// Configuration and result types
// ---------------------------------------------------------------------------

export interface FictionConfig {
  readonly apiKey: string;
  readonly models: readonly string[];
  readonly noteContent: string;
}

export interface FictionResult {
  readonly fiction: string;
  readonly model: string;
  readonly updatedContent: string;
}

// ---------------------------------------------------------------------------
// Main generation function (I/O)
// ---------------------------------------------------------------------------

export const generateFiction = async (
  config: FictionConfig,
): Promise<FictionResult> => {
  const stripped = stripForPrompt(config.noteContent);
  const prompt = buildFictionPrompt(stripped);
  const { text, model } = await callGeminiModelChain(config.apiKey, config.models, prompt);
  const fiction = parseFictionResponse(text);
  const updatedContent = applyFiction(config.noteContent, fiction);

  return { fiction, model, updatedContent };
};
