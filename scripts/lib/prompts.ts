/**
 * Versioned social media post prompts for A/B testing.
 *
 * Each variant defines two pure functions:
 * 1. A prompt builder that asks the AI for ONLY the creative parts
 *    (topic tags for variant A; question only for variant B).
 * 2. A post assembler that deterministically injects the creative
 *    output into a template string alongside the title and URL.
 *
 * Variant B reuses prompt A for tags — the model is called twice:
 * once for tags (prompt A) and once for question (prompt B).
 * This ensures the only difference between A and B is the question.
 *
 * This separation ensures reliability: the title, URL, and structural
 * formatting are never left to the model — only the creative content.
 *
 * Research-backed design rationale:
 *
 * Variant A (Control): The existing prompt style — title + emoji topic tags + URL.
 *   Straightforward, informative, consistent format.
 *
 * Variant B (Treatment): Adds a concise AI-generated discussion question
 *   before the topic tags. The question is always 2nd person, opinion-friendly,
 *   and designed to spark engagement on social media. Research on decentralized
 *   platforms (Mastodon, Bluesky) shows that authentic, conversation-starting
 *   posts generate significantly more engagement than purely informational
 *   announcements.
 *
 * Hypotheses:
 * H1: Posts with a discussion question will receive more replies than
 *     pure announcement posts.
 * H2: Posts with a discussion question will receive more likes/favorites
 *     than pure announcement posts.
 * H3: The effect will be stronger on Mastodon (community-driven, conversation-
 *     oriented culture) than on Bluesky (more broadcast-oriented).
 *
 * @module prompts
 */

import type { ReflectionData } from "./types.ts";
import type { VariantId } from "./experiment.ts";
import { BLUESKY_MAX_LENGTH } from "./types.ts";

// --- Prompt Builder Type ---

/** A prompt builder transforms reflection data into a system/user prompt pair. */
export interface PromptPair {
  readonly system: string;
  readonly user: string;
}

export type PromptBuilder = (reflection: ReflectionData) => PromptPair;

/**
 * A post assembler deterministically combines the model's creative output
 * with the reflection's title and URL into the final post text.
 *
 * The model output contains ONLY creative parts (topic tags, question, etc.).
 * Everything structural (title, URL, formatting) is injected by the assembler.
 */
export type PostAssembler = (modelOutput: string, reflection: ReflectionData) => string;

/** Complete variant configuration: prompt + assembler. */
export interface VariantConfig {
  readonly buildPrompt: PromptBuilder;
  readonly assemblePost: PostAssembler;
}

// --- Shared Constants ---

/**
 * Prefix for AI-generated discussion questions in variant B posts.
 * Short to maximize character budget for the actual question.
 */
export const AI_QUESTION_PREFIX = "#AI Q: ";

// --- Shared Prompt Components ---

/**
 * Instructions for generating emoji topic tags.
 * Shared across both variants to ensure consistent topic tag quality.
 * Each tag MUST be "emoji Topic Label" — never bare emojis or bare pipes.
 */
const TOPIC_TAGS_INSTRUCTIONS = `\
- Each topic tag MUST be an emoji followed by a space and a short topic label (e.g. 🌐 Systems Thinking or 🤖 AI)
- Separate tags with " | "
- Do NOT output bare emojis separated by pipes — every tag needs a text label after the emoji
- Extract topics from the content (books, videos, concepts, themes, etc.)
- Use 2–4 concise tags
- IMPORTANT: Keep the total tags line short — it must fit in a post under 300 characters`;

/**
 * Calculate the maximum character budget for the AI discussion question.
 *
 * The tightest platform constraint is Bluesky (300 graphemes). We calculate
 * how many characters are available for the question after accounting for:
 * - Title line + newline
 * - Blank line
 * - AI question prefix + newline
 * - Blank line
 * - URL line
 * - A generous tag allowance (60 chars)
 *
 * This budget is communicated to the LLM in the prompt so it generates
 * questions that fit without needing post-hoc truncation.
 */
export const calculateQuestionBudget = (reflection: ReflectionData): number => {
  const titleLength = reflection.title.length;
  const urlLength = reflection.url.length;
  const prefixLength = AI_QUESTION_PREFIX.length;
  // Template overhead: title + \n\n + prefix + question + \n\n + tags + \n + url
  // title\n\n = titleLength + 2
  // prefix + question\n\n = prefixLength + question + 2
  // tags\n = 60 (generous allowance) + 1
  // url = urlLength
  const fixedOverhead = titleLength + 2 + prefixLength + 2 + 60 + 1 + urlLength;
  // Use Bluesky limit (the strictest) as the total budget
  const budget = BLUESKY_MAX_LENGTH - fixedOverhead;
  // Ensure at least 30 chars for a meaningful question
  return Math.max(30, budget);
};

// --- Title Shortening ---

/**
 * Strip the subtitle from a title by removing everything after the first colon.
 * e.g. "Prediction Machines: The Simple Economics of AI" → "Prediction Machines"
 * Returns the original title if no colon is found.
 */
export const stripSubtitle = (title: string): string => {
  const colonIndex = title.indexOf(":");
  if (colonIndex < 0) return title;
  const shortened = title.slice(0, colonIndex).trim();
  return shortened.length > 0 ? shortened : title;
};

// --- Variant A: Control (Current Prompt) ---

/**
 * Variant A prompt: asks the model for ONLY emoji topic tags.
 * The title and URL are injected deterministically by the assembler.
 */
const buildPromptA: PromptBuilder = (reflection: ReflectionData): PromptPair => {
  const system = `You generate emoji topic tags for a social media post promoting a blog entry from bagrounds.org.

Return ONLY a single line of emoji-prefixed topic tags. Nothing else — no title, no URL, no commentary.

Rules for topic tags:
${TOPIC_TAGS_INSTRUCTIONS}

Examples of good output:
📚 Book Series | 🌌 Sci-Fi Exploration | 🤖 Artificial General Intelligence
🕸️ Animal Fables | 🐑 Children's Verse | 🧸 Rhyme Collections
🧪 Experimentation | 📊 Statistics | 🤖 AI Writing`;

  const user = `Generate emoji topic tags for this page:

Title: ${reflection.title}
URL: ${reflection.url}
Date: ${reflection.date}

Content:
${reflection.body}`;

  return { system, user };
};

/**
 * Variant A assembler: title + tags + URL.
 *
 * Template:
 * ```
 * $Title
 *
 * $Tags
 * $URL
 * ```
 */
const assemblePostA: PostAssembler = (modelOutput: string, reflection: ReflectionData): string => {
  const tags = modelOutput.trim();
  return `${reflection.title}\n\n${tags}\n${reflection.url}`;
};

// --- Variant B: Treatment (Discussion Question) ---

/**
 * Variant B prompt: asks the model for ONLY a discussion question.
 * Tags are generated separately using prompt A (reused), ensuring the
 * only difference between A and B posts is the additional question.
 *
 * Returns a SINGLE line: the question. No tags, no title, no URL.
 */
const buildPromptB: PromptBuilder = (reflection: ReflectionData): PromptPair => {
  const maxChars = calculateQuestionBudget(reflection);

  const system = `You generate a discussion question for a social media post about a blog entry from bagrounds.org.
Return ONLY a single line — the question. Nothing else — no title, no URL, no commentary, no tags, no labels.

Write a single, extremely concise question. Do not use any personal pronouns — the brief question should be 100% 2nd person. The goal of the question is to attract discussion engagement on a social media post about this content. It should be relatable and easy to answer with an opinion. Minimize word count and don't try to fake personality. Think Strunk and White for concision. Use fewer words. Never explicitly ask what's obvious implicitly (e.g. we are asking what they think, so we don't have to use the words "what do you think"). Never use quotation marks or hyphens. Be careful not to ask questions that are too personal. People should want to answer the question in a public forum. Also, the question should try to be relevant to the content but novel and interesting. Start the question with a single emoji. The question MUST end with a question mark.

IMPORTANT: The question MUST be at most ${maxChars} characters total (including the leading emoji). Keep it short!

Example output (exactly 1 line):
🤔 Ever trusted a machine more than your gut?

Another example:
📖 Best book from childhood still worth rereading?`;

  const user = `Generate a discussion question for this page (max ${maxChars} characters):

Title: ${reflection.title}
URL: ${reflection.url}
Date: ${reflection.date}

Content:
${reflection.body}`;

  return { system, user };
};

/**
 * Parse the model's output for variant B.
 * Now expects a single line (question only) since tags come from prompt A.
 * Robust: handles extra whitespace, blank lines, and edge cases.
 */
export const parseVariantBOutput = (modelOutput: string): { question: string; tags: string } => {
  const lines = modelOutput.trim().split("\n").filter((l) => l.trim().length > 0);

  if (lines.length >= 2) {
    // Backward compat: if model returns two lines, first is question, second is tags
    return { question: lines[0]!.trim(), tags: lines[1]!.trim() };
  }
  if (lines.length === 1) {
    // Expected path for prompt B's question-only output — tags come from a separate prompt A call
    return { question: lines[0]!.trim(), tags: "" };
  }
  return { question: "", tags: "" };
};

/**
 * Variant B assembler: title + AI question + tags + URL.
 *
 * Template:
 * ```
 * $Title
 *
 * #AI Q: $Question
 *
 * $Tags
 * $URL
 * ```
 */
const assemblePostB: PostAssembler = (modelOutput: string, reflection: ReflectionData): string => {
  const { question, tags } = parseVariantBOutput(modelOutput);
  const parts = [reflection.title, ""];
  if (question) {
    parts.push(`${AI_QUESTION_PREFIX}${question}`, "");
  }
  if (tags) {
    parts.push(tags);
  }
  parts.push(reflection.url);
  return parts.join("\n");
};

// --- Variant Registry ---

/**
 * Immutable map from variant ID to variant configuration.
 *
 * This is the single source of truth for all prompt variants.
 * Each variant specifies both how to prompt the model (for creative parts only)
 * and how to assemble the final post deterministically.
 *
 * Conceptually, this is a function VariantId → VariantConfig.
 */
export const VARIANT_CONFIGS: Readonly<Record<VariantId, VariantConfig>> = {
  A: { buildPrompt: buildPromptA, assemblePost: assemblePostA },
  B: { buildPrompt: buildPromptB, assemblePost: assemblePostB },
};

/**
 * Legacy prompt-only registry. Maps variant ID to prompt builder.
 * @deprecated Use VARIANT_CONFIGS for both prompt and assembly.
 */
export const PROMPT_VARIANTS: Readonly<Record<VariantId, PromptBuilder>> = {
  A: buildPromptA,
  B: buildPromptB,
};

/**
 * Look up the prompt builder for a given variant.
 * Total function — every valid VariantId maps to a builder.
 */
export const getPromptBuilder = (variant: VariantId): PromptBuilder =>
  VARIANT_CONFIGS[variant].buildPrompt;

/**
 * Look up the post assembler for a given variant.
 * Total function — every valid VariantId maps to an assembler.
 */
export const getPostAssembler = (variant: VariantId): PostAssembler =>
  VARIANT_CONFIGS[variant].assemblePost;

/**
 * Build a prompt for the given variant and reflection.
 * Convenience composition: getPromptBuilder(variant)(reflection)
 */
export const buildPromptForVariant = (
  variant: VariantId,
  reflection: ReflectionData,
): PromptPair => getPromptBuilder(variant)(reflection);

/**
 * Assemble the final post from model output for the given variant.
 * Convenience composition: getPostAssembler(variant)(modelOutput, reflection)
 */
export const assemblePostForVariant = (
  variant: VariantId,
  modelOutput: string,
  reflection: ReflectionData,
): string => getPostAssembler(variant)(modelOutput, reflection);

// --- Question Shortening Prompt ---

/**
 * Build a prompt that asks the LLM to shorten a question by a specific amount.
 * Used as a last resort when the assembled post exceeds platform limits
 * even after all progressive truncation strategies have been applied.
 *
 * The prompt is context-free (no previous conversation) to avoid confusion.
 */
export const buildShortenQuestionPrompt = (
  question: string,
  overage: number,
): PromptPair => ({
  system: `You shorten social media discussion questions. Return ONLY the shortened question — nothing else.
Keep the same meaning, tone, and emoji prefix. The question MUST end with a question mark.
Remove unnecessary words. Think Strunk and White for concision.`,
  user: `Shorten this question by at least ${overage} characters. Current length: ${question.length} characters. Target: at most ${question.length - overage} characters.

Question: ${question}`,
});
