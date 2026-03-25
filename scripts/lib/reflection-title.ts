/**
 * Reflection Title Generation
 *
 * Generates creative, emoji-enriched titles for daily reflection notes
 * using Gemini AI. Reads the note content, produces a thematic title
 * capturing the day's key themes as emoji+keyword pairs, and writes it
 * to the H1 heading plus the title and aliases frontmatter fields.
 *
 * Pure functions handle prompt construction and title application;
 * I/O functions handle Gemini calls and filesystem operations.
 *
 * @module reflection-title
 */

import yaml from "js-yaml";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const DEFAULT_TITLE_MODEL = "gemini-2.5-flash";

const GEMINI_MAX_RETRIES = 3;
const GEMINI_BASE_DELAY_MS = 2_000;

const YAML_OPTS: yaml.DumpOptions & yaml.LoadOptions = {
  lineWidth: -1,
  quotingType: '"',
  forceQuotes: false,
  schema: yaml.JSON_SCHEMA,
};

// ---------------------------------------------------------------------------
// Pure functions
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

/**
 * Builds the Gemini prompt for reflection title generation.
 *
 * The prompt instructs the model to read the reflection note content and
 * produce a single-line emoji-enriched title capturing the day's themes.
 */
export const buildReflectionTitlePrompt = (
  noteContent: string,
  recentTitles: readonly string[],
): { readonly system: string; readonly user: string } => {
  const examplesBlock = recentTitles
    .map((t) => `- ${t}`)
    .join("\n");

  const system = `You generate short, creative, emoji-enriched titles for daily reflection notes.

TITLE FORMAT RULES:
- A sequence of emoji+keyword pairs capturing the day's key themes
- Each concept gets 1–3 relevant emojis immediately followed by 1–2 words
- Vary style: sometimes create poetic connections between concepts, other times use terse keyword pairs
- End with a trailing cluster of category emojis indicating which content sections appeared
- Keep the title concise: typically 3–10 emoji+keyword pairs plus trailing category emojis
- Draw keywords from blog post titles/themes, book titles, video topics, news items, and personal activities in the note
- Do NOT include the date prefix — output only the creative part

CATEGORY EMOJIS (append all that apply):
📚 = Books section present
🐔 = Chickie Loo section present (chicken/ranch stories)
🤖 = Auto Blog Zero section present (AI/tech content)
🏛️ = Systems for Public Good section present (governance/policy)
📺 = Videos section present
📰 = News section present
📄 = Articles or documents section present
🎮 = Games section present
🎤 = Audio/podcast section present
💻 = Programming/coding section present

RECENT TITLE EXAMPLES (for style reference):
${examplesBlock}

OUTPUT: A single line of text — only the creative title. No date prefix, no quotes, no markdown formatting.`;

  const user = `Generate a creative emoji-enriched title for the following daily reflection note:\n\n${noteContent}`;

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
// Gemini API (simple single-call with retry and model chain)
// ---------------------------------------------------------------------------

const delay = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

const isRetriableError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const status = (error as { status?: number }).status;
  const message = String((error as { message?: string }).message ?? "");
  return (
    message.includes("429") ||
    message.includes("RESOURCE_EXHAUSTED") ||
    message.includes("quota") ||
    status === 429 ||
    (status !== undefined && status >= 500 && status < 600) ||
    message.includes("503") ||
    message.includes("502") ||
    message.includes("500") ||
    message.includes("INTERNAL") ||
    message.includes("UNAVAILABLE")
  );
};

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
  const prompt = buildReflectionTitlePrompt(config.noteContent, config.recentTitles);
  const { text, model } = await callGeminiModelChain(config.apiKey, config.models, prompt);
  const title = parseReflectionTitle(text);
  const fullTitle = `${config.date} | ${title}`;
  const updatedContent = applyReflectionTitle(config.noteContent, config.date, title);

  return { title, fullTitle, model, updatedContent };
};
