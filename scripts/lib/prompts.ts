/**
 * Social media post prompt generation.
 *
 * Two prompt builders produce the creative content for each post:
 * 1. A tags prompt asks the AI for emoji topic tags.
 * 2. A question prompt asks the AI for a discussion question.
 *
 * A post assembler deterministically combines the AI-generated question
 * and tags with the title and URL into the final post text.
 *
 * This separation ensures reliability: the title, URL, and structural
 * formatting are never left to the model — only the creative content.
 *
 * @module prompts
 */

import type { ReflectionData } from "./types.ts";
import { BLUESKY_MAX_LENGTH } from "./types.ts";

// --- Prompt Builder Type ---

export interface PromptPair {
  readonly system: string;
  readonly user: string;
}

export type PromptBuilder = (reflection: ReflectionData) => PromptPair;

export type PostAssembler = (modelOutput: string, reflection: ReflectionData) => string;

// --- Shared Constants ---

export const AI_QUESTION_PREFIX = "#AI Q: ";

// --- Shared Prompt Components ---

const TOPIC_TAGS_INSTRUCTIONS = `\
- Each topic tag MUST be an emoji followed by a space and a short topic label (e.g. 🌐 Systems Thinking or 🤖 AI)
- Separate tags with " | "
- Do NOT output bare emojis separated by pipes — every tag needs a text label after the emoji
- Extract topics from the content (books, videos, concepts, themes, etc.)
- Use 2–4 concise tags
- Avoid using words that are in the title
- IMPORTANT: Keep the total tags line short — it must fit in a post under 300 characters`;

export const calculateQuestionBudget = (reflection: ReflectionData): number => {
  const titleLength = reflection.title.length;
  const urlLength = reflection.url.length;
  const prefixLength = AI_QUESTION_PREFIX.length;
  const TAG_LINE_ALLOWANCE = 60;
  const fixedOverhead = titleLength + 2 + prefixLength + 2 + TAG_LINE_ALLOWANCE + 1 + urlLength;
  const budget = BLUESKY_MAX_LENGTH - fixedOverhead;
  return Math.max(30, budget);
};

// --- Title Shortening ---

export const stripSubtitle = (title: string): string => {
  const colonIndex = title.indexOf(":");
  if (colonIndex < 0) return title;
  const shortened = title.slice(0, colonIndex).trim();
  return shortened.length > 0 ? shortened : title;
};

// --- Tags Prompt ---

export const buildTagsPrompt: PromptBuilder = (reflection: ReflectionData): PromptPair => {
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

// --- Question Prompt ---

export const buildQuestionPrompt: PromptBuilder = (reflection: ReflectionData): PromptPair => {
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

// --- Model Output Parsing ---

export const parseQuestionAndTags = (modelOutput: string): { question: string; tags: string } => {
  const lines = modelOutput.trim().split("\n").filter((l) => l.trim().length > 0);

  if (lines.length >= 2) {
    return { question: lines[0]!.trim(), tags: lines[1]!.trim() };
  }
  if (lines.length === 1) {
    return { question: lines[0]!.trim(), tags: "" };
  }
  return { question: "", tags: "" };
};

// --- Post Assembly ---

export const assemblePost: PostAssembler = (modelOutput: string, reflection: ReflectionData): string => {
  const { question, tags } = parseQuestionAndTags(modelOutput);
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

// --- Question Shortening Prompt ---

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
