/**
 * Reflection Title Generation
 *
 * Generates creative, emoji-enriched titles for daily reflection notes
 * using Gemini AI. The title generation follows a specific creative game:
 *
 * 1. Deterministically extract linked content titles from the note body
 * 2. Deterministically extract trailing category emojis from section headings
 * 3. Ask Gemini to play the "one word per title" game — pick exactly one
 *    interesting word from each content title to form a meaningful phrase,
 *    then prefix each word with an emoji
 * 4. Append the deterministic trailing category emojis
 *
 * Pure functions handle deterministic prep (extraction, application);
 * Gemini handles only the creative "word selection + phrase building" step.
 *
 * @module reflection-title
 */

import yaml from "js-yaml";
import { isRetriableError } from "../generate-blog-post.ts";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const DEFAULT_TITLE_MODEL = "gemini-3.1-flash-lite-preview";

const GEMINI_MAX_RETRIES = 3;
const GEMINI_BASE_DELAY_MS = 2_000;

const YAML_OPTS: yaml.DumpOptions & yaml.LoadOptions = {
  lineWidth: -1,
  quotingType: '"',
  forceQuotes: false,
  schema: yaml.JSON_SCHEMA,
};

// ---------------------------------------------------------------------------
// Deterministic extraction — pure functions
// ---------------------------------------------------------------------------

/**
 * Extracts the leading emojis from a section heading line.
 * Given `## [📚 Books](...)` or `## [[books/index|📚 Books]]`, returns "📚".
 * Given `## 🤖🐲 AI Fiction`, returns "🤖🐲".
 */
export const extractHeadingEmojis = (heading: string): string => {
  const withoutHashes = heading.replace(/^#{1,6}\s+/, "");
  const linkContent = withoutHashes.match(/\[([^\]]*)\]/)
    ? (withoutHashes.match(/\[([^\]]*)\]/)?.[1] ?? withoutHashes)
    : withoutHashes;
  const pipeContent = linkContent.includes("|")
    ? linkContent.split("|").pop()!.trim()
    : linkContent.trim();
  const emojiMatch = pipeContent.match(/^([\p{Emoji_Presentation}\p{Emoji}\u200d\ufe0f\s]+)/u);
  return emojiMatch ? emojiMatch[1]!.trim() : "";
};

/**
 * Extracts trailing category emojis from all H2 section headings in a note.
 * Returns a deduplicated string of leading emojis from each section.
 */
export const extractTrailingEmojis = (noteContent: string): string => {
  const lines = noteContent.split("\n");
  const seen = new Set<string>();
  const emojis: string[] = [];

  lines
    .filter((line) => /^##\s/.test(line))
    .forEach((line) => {
      const extracted = extractHeadingEmojis(line);
      if (extracted && !seen.has(extracted)) {
        seen.add(extracted);
        emojis.push(extracted);
      }
    });

  return emojis.join("");
};

/**
 * Strips emoji prefixes and date prefixes from a linked content title.
 * `🕵️ Fugitive Telemetry` → `Fugitive Telemetry`
 * `2026-03-23 | 🐔 A Gentle Afternoon` → `A Gentle Afternoon`
 */
export const stripTitlePrefixes = (title: string): string =>
  title
    .replace(/^\d{4}-\d{2}-\d{2}\s*\|\s*/, "")
    .replace(/^[\p{Emoji_Presentation}\p{Emoji}\u200d\ufe0f\s]+/u, "")
    .trim();

/**
 * Extracts the display text of linked content from reflection list items.
 * Matches both markdown links `[Display Text](path)` and wiki links `[[path|Display Text]]`.
 * Only extracts from list items (lines starting with `-`), not headings.
 * Strips date prefixes and emoji prefixes from the extracted titles.
 */
export const extractLinkedTitles = (noteContent: string): readonly string[] => {
  const { body } = splitFrontmatter(noteContent);
  const lines = body.split("\n");

  return lines
    .filter((line) => /^-\s/.test(line.trim()))
    .flatMap((line) => {
      const titles: string[] = [];

      // Markdown links: [Display Text](path.md)
      const mdMatches = [...line.matchAll(/\[([^\]]+)\]\([^)]+\.md\)/g)];
      mdMatches.forEach((m) => titles.push(m[1]!));

      // Wiki links: [[path|Display Text]] or [[path]]
      const wikiMatches = [...line.matchAll(/\[\[([^\]]+)\]\]/g)];
      wikiMatches.forEach((m) => {
        const content = m[1]!;
        const display = content.includes("|") ? content.split("|").pop()!.trim() : content.trim();
        titles.push(display);
      });

      return titles;
    })
    .map(stripTitlePrefixes)
    .filter((t) => t.length > 0);
};

// ---------------------------------------------------------------------------
// Idempotency check
// ---------------------------------------------------------------------------

/**
 * Checks whether a reflection note still needs a creative title.
 * Returns true when the title is just the bare date (e.g. "2026-03-24").
 */
export const reflectionNeedsTitle = (content: string, date: string): boolean => {
  const titleLine = content
    .split("\n")
    .find((line) => /^title:\s/.test(line));

  if (!titleLine) return true;

  const titleValue = titleLine.replace(/^title:\s*/, "").trim();
  return titleValue === date;
};

// ---------------------------------------------------------------------------
// Prompt construction
// ---------------------------------------------------------------------------

/**
 * Builds the Gemini prompt for reflection title generation.
 *
 * The prompt gives Gemini a focused creative task: given a list of content
 * titles from the day, pick exactly one interesting word from each title
 * to form a meaningful phrase, then prefix each word with a relevant emoji.
 *
 * Trailing category emojis are computed deterministically and appended by
 * the caller — Gemini does NOT produce them.
 */
export const buildReflectionTitlePrompt = (
  linkedTitles: readonly string[],
  recentTitles: readonly string[],
): { readonly system: string; readonly user: string } => {
  const examplesBlock = recentTitles
    .map((t) => `- ${t}`)
    .join("\n");

  const system = `You create short, creative titles from a list of content titles.

THE GAME:
1. You receive a list of content titles (books, blog posts, videos, etc.)
2. Pick exactly ONE interesting or evocative word from each title
3. Arrange these words into a short, meaningful phrase or sentence fragment
4. Prefix each meaningful word with 1-2 relevant emojis (skip filler words like "and", "of", "the")
5. The result should be interesting, keyword-dense, and remind the reader of each piece of content

RULES:
- Use exactly one word from EACH content title (not zero, not two)
- The words should form something coherent — a phrase, a poetic sentence, a fun juxtaposition — NOT random word salad
- Keep it concise (typically 3-10 emoji+word pairs)
- Do NOT include any trailing category emojis — those are added separately
- Do NOT include any date prefix
- Output a single line of text only

GOOD TITLE EXAMPLES (for style reference):
${examplesBlock}`;

  const titlesBlock = linkedTitles
    .map((t, i) => `${i + 1}. ${t}`)
    .join("\n");

  const user = `Pick one word from each of these content titles and create a creative emoji-enriched title:\n\n${titlesBlock}`;

  return { system, user };
};

/**
 * Parses the raw Gemini response into a clean title string.
 * Strips code fences, quotes, leading/trailing whitespace, and date prefixes.
 */
export const parseReflectionTitle = (raw: string): string =>
  raw
    .replace(/^```(?:markdown|md)?\s*\n/, "")
    .replace(/\n```\s*$/, "")
    .replace(/^["']|["']$/g, "")
    .replace(/^\d{4}-\d{2}-\d{2}\s*\|\s*/, "")
    .split("\n")[0]!
    .trim();

/**
 * Applies a creative title to a reflection note's content.
 * Updates the frontmatter `title` and `aliases` fields and the H1 heading.
 */
export const applyReflectionTitle = (
  content: string,
  date: string,
  creativeTitle: string,
): string => {
  const fullTitle = `${date} | ${creativeTitle}`;

  // 1. Update frontmatter
  const withUpdatedFrontmatter = updateTitleFrontmatter(content, fullTitle);

  // 2. Update H1 heading
  return updateH1Heading(withUpdatedFrontmatter, date, fullTitle);
};

// ---------------------------------------------------------------------------
// Frontmatter helpers
// ---------------------------------------------------------------------------

const splitFrontmatter = (
  content: string,
): {
  readonly yamlBlock: string;
  readonly body: string;
  readonly hasFrontmatter: boolean;
} => {
  const lines = content.split("\n");
  if (lines[0]?.trim() !== "---") {
    return { yamlBlock: "", body: content, hasFrontmatter: false };
  }
  const endIndex = lines.findIndex((line, i) => i > 0 && line.trim() === "---");
  if (endIndex < 0) {
    return { yamlBlock: "", body: content, hasFrontmatter: false };
  }
  return {
    yamlBlock: lines.slice(1, endIndex).join("\n"),
    body: lines.slice(endIndex + 1).join("\n"),
    hasFrontmatter: true,
  };
};

const dumpYaml = (doc: Record<string, unknown>): string =>
  yaml
    .dump(doc, YAML_OPTS)
    .trim()
    .replace(/^(\S+): null$/gm, "$1:");

const updateTitleFrontmatter = (content: string, fullTitle: string): string => {
  const { yamlBlock, body, hasFrontmatter } = splitFrontmatter(content);
  if (!hasFrontmatter) return content;

  const doc = (yaml.load(yamlBlock, YAML_OPTS) as Record<string, unknown> | null) ?? {};
  const merged = { ...doc, title: fullTitle, aliases: [fullTitle] };
  return `---\n${dumpYaml(merged)}\n---\n${body}`;
};

const updateH1Heading = (content: string, date: string, fullTitle: string): string => {
  const dateHeadingPattern = new RegExp(`^(#\\s+)(?:🤖\\s+)?${escapeRegex(date)}(?:[ \\t].*)?$`, "m");
  return dateHeadingPattern.test(content)
    ? content.replace(dateHeadingPattern, `$1${fullTitle}`)
    : content;
};

const escapeRegex = (s: string): string =>
  s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// ---------------------------------------------------------------------------
// Gemini API — reuses isRetriableError from generate-blog-post.ts
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
    config: { temperature: 0.9 },
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
        console.log(`  ⏳ Reflection title retry: model=${model}, attempt=${attempt + 1}, delay=${delayMs}ms`);
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

export interface ReflectionTitleConfig {
  readonly apiKey: string;
  readonly models: readonly string[];
  readonly noteContent: string;
  readonly date: string;
  readonly recentTitles: readonly string[];
}

export interface ReflectionTitleResult {
  readonly title: string;
  readonly fullTitle: string;
  readonly model: string;
  readonly updatedContent: string;
}

// ---------------------------------------------------------------------------
// Main generation function (I/O)
// ---------------------------------------------------------------------------

export const generateReflectionTitle = async (
  config: ReflectionTitleConfig,
): Promise<ReflectionTitleResult> => {
  // 1. Deterministic extraction
  const linkedTitles = extractLinkedTitles(config.noteContent);
  const trailingEmojis = extractTrailingEmojis(config.noteContent);

  // 2. AI: play the "one word per title" game
  const prompt = buildReflectionTitlePrompt(linkedTitles, config.recentTitles);
  const { text, model } = await callGeminiModelChain(config.apiKey, config.models, prompt);
  const creativePart = parseReflectionTitle(text);

  // 3. Deterministic assembly: creative part + trailing category emojis
  const title = trailingEmojis ? `${creativePart} ${trailingEmojis}` : creativePart;
  const fullTitle = `${config.date} | ${title}`;
  const updatedContent = applyReflectionTitle(config.noteContent, config.date, title);

  return { title, fullTitle, model, updatedContent };
};
