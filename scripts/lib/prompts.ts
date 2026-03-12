/**
 * Versioned social media post prompts for A/B testing.
 *
 * Each variant defines two pure functions:
 * 1. A prompt builder that asks the AI for ONLY the creative parts
 *    (topic tags, and for variant B also a discussion question).
 * 2. A post assembler that deterministically injects the creative
 *    output into a template string alongside the title and URL.
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
${reflection.body.slice(0, 1500)}`;

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
 * Variant B prompt: asks the model for a discussion question AND emoji topic tags.
 * Returns two lines: the question, then the tags. Title and URL are NOT generated.
 */
const buildPromptB: PromptBuilder = (reflection: ReflectionData): PromptPair => {
  const system = `You generate two components for a social media post about a blog entry from bagrounds.org.
Return ONLY two lines. Nothing else — no title, no URL, no commentary, no labels.

LINE 1 — DISCUSSION QUESTION:
Write a single, extremely concise question. Do not use any personal pronouns — the brief question should be 100% 2nd person. The goal of the question is to attract discussion engagement on a social media post about this content. It should be relatable and easy to answer with an opinion. Minimize word count and don't try to fake personality. Think Strunk and White for concision. Use fewer words. Never explicitly ask what's obvious implicitly (e.g. we are asking what they think, so we don't have to use the words "what do you think"). Never use quotation marks or hyphens. Be careful not to ask questions that are too personal. People should want to answer the question in a public forum. Also, the question should try to be relevant to the content but novel and interesting. Start the question with a single emoji. The question MUST end with a question mark.

LINE 2 — EMOJI TOPIC TAGS:
${TOPIC_TAGS_INSTRUCTIONS}

Example output (exactly 2 lines):
🤔 Ever trusted a machine more than your gut?
📚 Sci-Fi | 🤖 AGI | 🌌 Futures

Another example:
📖 Best book from childhood still worth rereading?
🕸️ Fables | 🧸 Children's Lit`;

  const user = `Generate a discussion question and emoji topic tags for this page:

Title: ${reflection.title}
URL: ${reflection.url}
Date: ${reflection.date}

Content:
${reflection.body.slice(0, 1500)}`;

  return { system, user };
};

/**
 * Parse the model's two-line output into question and tags.
 * Robust: handles extra whitespace, blank lines, and edge cases.
 */
export const parseVariantBOutput = (modelOutput: string): { question: string; tags: string } => {
  const lines = modelOutput.trim().split("\n").filter((l) => l.trim().length > 0);

  if (lines.length >= 2) {
    return { question: lines[0]!.trim(), tags: lines[1]!.trim() };
  }
  if (lines.length === 1) {
    // Only got one line — treat as question with fallback tags
    return { question: lines[0]!.trim(), tags: "" };
  }
  return { question: "", tags: "" };
};

/**
 * Variant B assembler: title + AI Discussion Prompt question + tags + URL.
 *
 * Template:
 * ```
 * $Title
 *
 * 🤖❓ AI Discussion Prompt: $Question
 *
 * $Tags
 * $URL
 * ```
 */
const assemblePostB: PostAssembler = (modelOutput: string, reflection: ReflectionData): string => {
  const { question, tags } = parseVariantBOutput(modelOutput);
  const parts = [reflection.title, ""];
  if (question) {
    parts.push(`🤖❓ AI Discussion Prompt: ${question}`, "");
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
