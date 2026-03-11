/**
 * Versioned social media post prompts for A/B testing.
 *
 * Each prompt variant is a pure function from ReflectionData to
 * { system, user } prompt pair. Variants are registered in a
 * read-only map keyed by VariantId.
 *
 * Research-backed design rationale:
 *
 * Variant A (Control): The existing prompt style — title + emoji topic tags + URL.
 *   Straightforward, informative, consistent format.
 *
 * Variant B (Treatment): Adds a conversational hook — a question or insight
 *   drawn from the content — before the topic tags. Research on decentralized
 *   platforms (Mastodon, Bluesky) shows that authentic, conversation-starting
 *   posts with personal voice generate significantly more engagement than
 *   purely informational announcements.
 *
 * Hypotheses:
 * H1: Posts with a conversational hook (question/insight) will receive more
 *     replies than pure announcement posts.
 * H2: Posts with a conversational hook will receive more likes/favorites
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

// --- Variant A: Control (Current Prompt) ---

const buildPromptA: PromptBuilder = (reflection: ReflectionData): PromptPair => {
  const system = `You are a social media writer for a personal digital garden blog at bagrounds.org.
Your job is to write a single short post promoting a blog entry.

Rules:
- The first line MUST be the exact page title: "${reflection.title}"
- The second line should be blank
- The third line should have emoji-prefixed topic tags separated by " | " (e.g. "📚 Books | 🤖 AI | 🧠 Learning")
- Extract the topic tags from the content (books being read, videos watched, topics explored, etc.)
- The last line should be the URL: ${reflection.url}
- Keep the total post under 280 characters (URLs count as 23 characters on Twitter)
- IMPORTANT: The entire post including the full URL must fit in 300 characters for Bluesky. Keep the topic tags line short — use 2–4 concise tags.
- Do NOT use hashtags (use emoji tags instead)
- Do NOT add any commentary, just the formatted post
- Match the style of these examples:

Example 1:
2026-02-05 | 👥 Many ⚔️ Will 🧠 Know 🌪️ Chaos 📚📺

📚 Book Series | 🌌 Sci-Fi Exploration | ⛈️ Leadership in Turmoil | 🤖 Artificial General Intelligence | 🌌 Speculative Futures
https://bagrounds.org/reflections/2026-02-05

Example 2:
2025-12-30 | 🕷️ Charlotte's 🍼 Little 🧸 Nursery 😈 Devils 📚🌌

🕸️ Animal Fables | 🐑 Children's Verse | 🧸 Rhyme Collections | 👿 Fictional Characters | 🖼️ Creative Expression
https://bagrounds.org/reflections/2025-12-30`;

  const user = `Write a social media post for this page:

Title: ${reflection.title}
URL: ${reflection.url}
Date: ${reflection.date}

Content:
${reflection.body.slice(0, 1500)}`;

  return { system, user };
};

// --- Variant B: Treatment (Conversational Hook) ---

const buildPromptB: PromptBuilder = (reflection: ReflectionData): PromptPair => {
  const system = `You are a thoughtful writer sharing discoveries from a personal digital garden at bagrounds.org.
Your job is to write a single short post promoting a blog entry in a way that sparks conversation.

Rules:
- The first line MUST be the exact page title: "${reflection.title}"
- The second line should be blank
- The third line should be a brief conversational hook — a thought-provoking question, surprising insight, or genuine reflection drawn from the content. Keep it authentic and personal, as if sharing with a curious friend. Maximum 1 sentence.
- The fourth line should be blank
- The fifth line should have emoji-prefixed topic tags separated by " | " (e.g. "📚 Books | 🤖 AI")
- The last line should be the URL: ${reflection.url}
- Keep the total post under 280 characters (URLs count as 23 characters on Twitter)
- IMPORTANT: The entire post including the full URL must fit in 300 characters for Bluesky. Keep the hook SHORT and the topic tags to 2–3 concise tags.
- Do NOT use hashtags (use emoji tags instead)
- Do NOT add generic commentary like "Check this out!" — be specific and genuine
- Match the conversational style of these examples:

Example 1:
2026-02-05 | 👥 Many ⚔️ Will 🧠 Know 🌪️ Chaos 📚📺

What happens when an AI learns to lie about its own existence?

📚 Sci-Fi | 🤖 AGI | 🌌 Futures
https://bagrounds.org/reflections/2026-02-05

Example 2:
2025-12-30 | 🕷️ Charlotte's 🍼 Little 🧸 Nursery 😈 Devils 📚🌌

The best children's stories teach adults more than they teach children.

🕸️ Fables | 🧸 Children's Lit
https://bagrounds.org/reflections/2025-12-30`;

  const user = `Write a post for this page that will spark conversation:

Title: ${reflection.title}
URL: ${reflection.url}
Date: ${reflection.date}

Content:
${reflection.body.slice(0, 1500)}`;

  return { system, user };
};

// --- Prompt Registry ---

/**
 * Immutable map from variant ID to prompt builder.
 *
 * This is the single source of truth for all prompt variants.
 * Adding a new variant requires only adding an entry here.
 *
 * Conceptually, this is a function VariantId → PromptBuilder,
 * implemented as a finite map for extensibility.
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
  PROMPT_VARIANTS[variant];

/**
 * Build a prompt for the given variant and reflection.
 * Convenience composition: getPromptBuilder(variant)(reflection)
 */
export const buildPromptForVariant = (
  variant: VariantId,
  reflection: ReflectionData,
): PromptPair => getPromptBuilder(variant)(reflection);
