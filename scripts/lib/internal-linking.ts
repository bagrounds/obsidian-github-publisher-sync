/**
 * Internal Linking — BFS-driven wikilink insertion.
 *
 * Traverses the content graph starting from the most recent reflection,
 * identifies plain-text references to content pages, validates them with
 * Gemini, and inserts wikilinks.
 *
 * Design principles:
 * - Correctness over coverage: better to miss links than insert wrong ones
 * - Pure functions where possible (functional/declarative style)
 * - Strong static types
 * - Deterministic discovery + AI validation hybrid
 *
 * @module internal-linking
 */

import fs from "node:fs";
import path from "node:path";

// --- Constants ---

/** Minimum plain-title length to consider for matching (avoids false positives with short names) */
export const MIN_TITLE_LENGTH = 8;

/** Minimum word count for a title to be eligible for matching without AI validation */
export const MIN_WORD_COUNT_WITHOUT_AI = 2;

/** Default Gemini model for link identification */
export const DEFAULT_LINKING_MODEL = "gemini-3.1-flash-lite-preview";

/** Maximum retries on rate-limit errors before propagating */
export const MAX_GEMINI_RETRIES = 3;

/** Initial backoff in milliseconds for rate-limit retries */
export const INITIAL_BACKOFF_MS = 5_000;

/** Maximum backoff in milliseconds */
export const MAX_BACKOFF_MS = 60_000;

/** Content subdirectories to index as link targets (excludes date-based content) */
export const INDEXABLE_DIRS = [
  "books",
  "articles",
  "topics",
  "software",
  "people",
  "products",
  "games",
  "videos",
  "presentations",
  "tools",
] as const;

/** Directories whose pages are eligible for wikilink insertion (books-only for precision) */
export const LINKABLE_DIRS = ["books"] as const;

/** All content directories for BFS traversal (includes date-based content) */
export const TRAVERSABLE_DIRS = [
  ...INDEXABLE_DIRS,
  "reflections",
  "chickie-loo",
  "auto-blog-zero",
] as const;

// --- Error Types ---

/** Thrown when Gemini API daily quota is exhausted. Halts the pipeline. */
export class QuotaExhaustedError extends Error {
  constructor(message: string = "Gemini API daily quota exhausted") {
    super(message);
    this.name = "QuotaExhaustedError";
  }
}

// --- Rate Limit Utilities ---

/** Check if an error is a rate-limit / quota error */
export const isRateLimitError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const message = (error as { message?: string }).message ?? "";
  return (
    message.includes("429") ||
    message.includes("RESOURCE_EXHAUSTED") ||
    message.includes("quota")
  );
};

/** Check if error indicates daily quota exhaustion (not just per-minute) */
export const isDailyQuotaError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const message = (error as { message?: string }).message ?? "";
  return (
    message.includes("quota") &&
    (message.includes("daily") ||
     message.includes("per day") ||
     message.includes("PerDay"))
  );
};

/** Parse retry delay from Gemini error response */
export const parseRetryDelay = (error: unknown): number | null => {
  if (!error || typeof error !== "object") return null;
  const message = (error as { message?: string }).message ?? "";

  // Match "retry in 14.47s" or "retry in 30s"
  const retryInMatch = message.match(/retry\s+in\s+(\d+(?:\.\d+)?)\s*s/i);
  if (retryInMatch) return Math.ceil(parseFloat(retryInMatch[1]!) * 1000);

  // Match 'retryDelay: "30s"' or 'retryDelay":"14s"'
  const delayMatch = message.match(/retryDelay["\s:]*["']?(\d+(?:\.\d+)?)\s*s/i);
  if (delayMatch) return Math.ceil(parseFloat(delayMatch[1]!) * 1000);

  return null;
};

/** Sleep for a given number of milliseconds */
const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

// --- Types ---

/** A content page in the index */
export interface ContentEntry {
  /** Path relative to content dir, e.g. "books/thinking-fast-and-slow.md" */
  readonly relativePath: string;
  /** Full title from frontmatter (with emojis), e.g. "🤔🐇🐢 Thinking, Fast and Slow" */
  readonly title: string;
  /** Title with emojis stripped, e.g. "Thinking, Fast and Slow" */
  readonly plainTitle: string;
}

/** A candidate link found in a file */
export interface LinkCandidate {
  /** The content entry this match refers to */
  readonly entry: ContentEntry;
  /** The exact text that was matched in the source file */
  readonly matchedText: string;
  /** Character offset in the original content where the match starts */
  readonly position: number;
  /** Surrounding context for AI validation (~100 chars each side) */
  readonly context: string;
}

/** Result of processing a single file */
export interface FileResult {
  /** Relative path of the processed file */
  readonly relativePath: string;
  /** Number of links added */
  readonly linksAdded: number;
  /** Whether the file content was modified */
  readonly modified: boolean;
}

/** Result of the full internal linking run */
export interface RunResult {
  /** Files that were visited during BFS */
  readonly filesVisited: number;
  /** Files that were modified */
  readonly filesModified: number;
  /** Total links added across all files */
  readonly totalLinksAdded: number;
  /** Per-file results */
  readonly fileResults: readonly FileResult[];
}

/** Configuration for the internal linking run */
export interface LinkingConfig {
  /** Root content directory (absolute path) */
  readonly contentDir: string;
  /** Maximum number of files to edit */
  readonly maxFiles: number;
  /** Gemini API key (if omitted, skips AI validation and uses deterministic-only mode) */
  readonly apiKey?: string;
  /** Gemini model for validation */
  readonly model: string;
  /** If true, don't write changes to disk */
  readonly dryRun: boolean;
}

// --- Pure Utility Functions ---

/**
 * Strip emoji characters from text, returning only non-emoji content.
 * Handles multi-codepoint emoji (ZWJ sequences, skin tones, flags).
 */
export const stripEmojis = (text: string): string =>
  text
    .replace(
      /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2702}-\u{27B0}\u{FE00}-\u{FE0F}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}\u{200D}\u{20E3}\u{E0020}-\u{E007F}\u{FE0E}\u{FE0F}]/gu,
      "",
    )
    .replace(/\s+/g, " ")
    .trim();

/**
 * Count the number of words in a string.
 * Splits on whitespace and hyphens to count compound words.
 */
export const countWords = (text: string): number =>
  text.split(/[\s-]+/).filter((w) => w.length > 0).length;

/**
 * Escape special regex characters in a string for use in RegExp constructor.
 */
export const escapeRegex = (text: string): string =>
  text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Format a wikilink from a content entry.
 * Uses the path relative to content dir (without .md) as the target
 * and the full emoji title as the alias.
 *
 * Example: [[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]]
 */
export const formatWikilink = (entry: ContentEntry): string => {
  const target = entry.relativePath.replace(/\.md$/, "");
  return `[[${target}|${entry.title}]]`;
};

/**
 * Extract context around a position in content for AI validation.
 * Returns ~100 characters before and after the match.
 */
export const extractContext = (
  content: string,
  position: number,
  matchLength: number,
  radius: number = 100,
): string => {
  const start = Math.max(0, position - radius);
  const end = Math.min(content.length, position + matchLength + radius);
  const prefix = start > 0 ? "..." : "";
  const suffix = end < content.length ? "..." : "";
  return `${prefix}${content.substring(start, end)}${suffix}`;
};

// --- Content Index ---

/**
 * Parse frontmatter from markdown content (simple key-value extraction).
 * Returns key-value pairs. Only handles single-line string values.
 */
export const parseFrontmatter = (
  content: string,
): Record<string, string> => {
  const lines = content.split("\n");
  if (lines[0]?.trim() !== "---") return {};

  const endIndex = lines.findIndex((line, i) => i > 0 && line.trim() === "---");
  if (endIndex < 0) return {};

  return Object.fromEntries(
    lines
      .slice(1, endIndex)
      .map((line) => line.match(/^(\w+):\s*(.*)$/))
      .filter((match): match is RegExpMatchArray => match !== null)
      .map(([, key, value]) => [
        key as string,
        (value as string).replace(/^["']|["']$/g, ""),
      ]),
  );
};

/**
 * Build a content index from all markdown files in the content directory.
 * Reads frontmatter from each file to get the title.
 * Skips index.md files and files without a title.
 */
export const buildContentIndex = (contentDir: string): readonly ContentEntry[] =>
  LINKABLE_DIRS.flatMap((dir) => {
    const dirPath = path.join(contentDir, dir);
    if (!fs.existsSync(dirPath)) return [];

    return fs
      .readdirSync(dirPath)
      .filter((f) => f.endsWith(".md") && f !== "index.md")
      .flatMap((file): readonly ContentEntry[] => {
        const relativePath = `${dir}/${file}`;
        const filePath = path.join(contentDir, relativePath);
        const content = fs.readFileSync(filePath, "utf-8");
        const frontmatter = parseFrontmatter(content);
        const title = frontmatter["title"];
        if (!title) return [];

        const plainTitle = stripEmojis(title);
        if (plainTitle.length < MIN_TITLE_LENGTH) return [];

        return [{ relativePath, title, plainTitle }];
      });
  });

// --- BFS Traversal ---

/**
 * Extract all linked paths from content (both markdown links and wikilinks).
 * Returns paths relative to the content directory.
 */
export const extractLinkedPaths = (
  body: string,
  noteRelativePath: string,
  contentDir: string,
): readonly string[] => {
  const noteDir = path.dirname(path.join(contentDir, noteRelativePath));
  const seen = new Set<string>();
  const links: string[] = [];

  const addLink = (relativePath: string): void => {
    if (!relativePath.startsWith("..") && !seen.has(relativePath)) {
      seen.add(relativePath);
      links.push(relativePath);
    }
  };

  // Markdown links: [text](path.md)
  const markdownLinkRegex = /\]\(([^)]+\.md)\)/g;
  const mdMatches = body.matchAll(markdownLinkRegex);
  Array.from(mdMatches).forEach((match) => {
    const target = match[1] as string;
    if (target.startsWith("http://") || target.startsWith("https://")) return;
    const absoluteTarget = path.resolve(noteDir, target);
    const relativePath = path.relative(contentDir, absoluteTarget);
    addLink(relativePath);
  });

  // Wiki links: [[path]] or [[path|display]] or [[path#heading]]
  const wikiLinkRegex = /\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]+)?\]\]/g;
  const wikiMatches = body.matchAll(wikiLinkRegex);
  Array.from(wikiMatches).forEach((match) => {
    const target = (match[1] as string).trim();
    const withMd = target.endsWith(".md") ? target : `${target}.md`;
    if (withMd.includes("/")) {
      addLink(withMd);
    } else {
      const absoluteTarget = path.resolve(noteDir, withMd);
      const relativePath = path.relative(contentDir, absoluteTarget);
      addLink(relativePath);
    }
  });

  return links;
};

/**
 * Find the most recent reflection file by date filename.
 */
export const findMostRecentReflection = (contentDir: string): string | null => {
  const reflectionsDir = path.join(contentDir, "reflections");
  if (!fs.existsSync(reflectionsDir)) return null;

  const datePattern = /^\d{4}-\d{2}-\d{2}\.md$/;
  const files = fs
    .readdirSync(reflectionsDir)
    .filter((f) => datePattern.test(f))
    .sort()
    .reverse();

  return files.length > 0 ? `reflections/${files[0]}` : null;
};

/**
 * BFS traversal of the content graph starting from the most recent reflection.
 * Returns an array of relative paths in BFS visit order.
 * Skips index.md files.
 */
export const bfsTraversal = (
  contentDir: string,
  maxVisit: number,
): readonly string[] => {
  const start = findMostRecentReflection(contentDir);
  if (!start) return [];

  const visited = new Set<string>();
  const queue: string[] = [start];
  const result: string[] = [];
  visited.add(start);

  while (queue.length > 0 && result.length < maxVisit) {
    const current = queue.shift()!;
    const filePath = path.join(contentDir, current);

    if (!fs.existsSync(filePath)) continue;
    if (path.basename(current) === "index.md") continue;

    result.push(current);

    const content = fs.readFileSync(filePath, "utf-8");
    const fmLines = content.split("\n");
    const fmEnd = fmLines[0]?.trim() === "---"
      ? fmLines.findIndex((l, i) => i > 0 && l.trim() === "---")
      : -1;
    const body = fmEnd >= 0 ? fmLines.slice(fmEnd + 1).join("\n") : content;

    const linkedPaths = extractLinkedPaths(body, current, contentDir);
    linkedPaths.forEach((linked) => {
      if (!visited.has(linked)) {
        visited.add(linked);
        queue.push(linked);
      }
    });
  }

  return result;
};

// --- Protected Region Masking ---

/**
 * Create a masked version of content where protected regions are replaced
 * with space characters. Protected regions include:
 * - Frontmatter (between --- delimiters)
 * - Fenced code blocks (``` ... ```)
 * - Inline code (` ... `)
 * - Existing markdown links [text](url)
 * - Existing wikilinks [[...]]
 * - Headings (lines starting with #)
 * - Bare URLs
 * - Bold/italic markers around link-like text
 *
 * Positions are preserved (masked content has same length as original).
 */
export const maskProtectedRegions = (content: string): string => {
  const mask = (text: string, regex: RegExp): string =>
    text.replace(regex, (m) => " ".repeat(m.length));

  // Order matters: mask larger structures first
  const steps: readonly RegExp[] = [
    // Frontmatter block
    /^---\n[\s\S]*?\n---\n/,
    // Fenced code blocks (``` or ~~~)
    /(`{3,}|~{3,})[\s\S]*?\1/g,
    // Inline code
    /`[^`\n]+`/g,
    // Markdown links [text](url) - mask entire link including text
    /\[[^\]]*\]\([^)]*\)/g,
    // Wikilinks [[...]]
    /\[\[[^\]]*\]\]/g,
    // Headings
    /^#{1,6}\s.*$/gm,
    // Bare URLs
    /https?:\/\/[^\s)\]]+/g,
    // Bold markers **text** (the markers only, to avoid matching bold book titles as plain text)
    /\*\*/g,
  ];

  return steps.reduce(mask, content);
};

/**
 * Collect the set of already-linked paths from the content.
 * Extracts both markdown link targets and wikilink targets.
 * Returns a set of relative paths (without .md extension) for matching against content entries.
 */
export const extractExistingLinkedPaths = (
  content: string,
  noteRelativePath: string,
  contentDir: string,
): ReadonlySet<string> => {
  const noteDir = path.dirname(path.join(contentDir, noteRelativePath));
  const paths = new Set<string>();

  // Markdown links
  const mdRegex = /\]\(([^)]+\.md)\)/g;
  Array.from(content.matchAll(mdRegex)).forEach((match) => {
    const target = match[1] as string;
    if (!target.startsWith("http")) {
      const abs = path.resolve(noteDir, target);
      paths.add(path.relative(contentDir, abs));
    }
  });

  // Wikilinks
  const wikiRegex = /\[\[([^\]|#]+)/g;
  Array.from(content.matchAll(wikiRegex)).forEach((match) => {
    const target = (match[1] as string).trim();
    const withMd = target.endsWith(".md") ? target : `${target}.md`;
    if (withMd.includes("/")) {
      paths.add(withMd);
    } else {
      const abs = path.resolve(noteDir, withMd);
      paths.add(path.relative(contentDir, abs));
    }
  });

  return paths;
};

// --- Candidate Discovery ---

/**
 * Check whether a file's raw content already contains any link (wikilink or markdown)
 * pointing to the given entry's path. Checks for the path followed by common link
 * delimiters to avoid false positives on longer paths that share a prefix.
 */
export const contentAlreadyLinksTo = (
  content: string,
  entry: ContentEntry,
): boolean => {
  const pathWithoutMd = entry.relativePath.replace(/\.md$/, "");
  return (
    content.includes(`${pathWithoutMd}]`) ||
    content.includes(`${pathWithoutMd}|`) ||
    content.includes(`${pathWithoutMd}#`) ||
    content.includes(`${pathWithoutMd}.`)
  );
};

/**
 * Find link candidates in a file by searching masked content for plain-title matches.
 * Returns candidates sorted by position (ascending) for safe replacement.
 *
 * Only considers entries from the books directory (LINKABLE_DIRS).
 * Skips entries whose path already appears anywhere in the file (even outside links).
 *
 * When hasAiValidation is false (no Gemini API key), applies stricter filtering:
 * only multi-word titles are considered to avoid common single-word false positives.
 */
export const findLinkCandidates = (
  content: string,
  masked: string,
  index: readonly ContentEntry[],
  existingLinks: ReadonlySet<string>,
  selfPath: string,
  hasAiValidation: boolean = true,
): readonly LinkCandidate[] => {
  const candidates: LinkCandidate[] = [];

  // Sort by plainTitle length descending to prefer longer matches
  const sortedIndex = [...index].sort(
    (a, b) => b.plainTitle.length - a.plainTitle.length,
  );

  // Track which positions have already been matched (to avoid overlapping matches)
  const matchedRanges: Array<{ start: number; end: number }> = [];

  const isOverlapping = (start: number, end: number): boolean =>
    matchedRanges.some(
      (r) => start < r.end && end > r.start,
    );

  sortedIndex.forEach((entry) => {
    // Skip self-references
    if (entry.relativePath === selfPath) return;

    // Skip already-linked content
    if (existingLinks.has(entry.relativePath)) return;

    // Skip if the entry's path already appears anywhere in the raw content
    if (contentAlreadyLinksTo(content, entry)) return;

    // Without AI validation, skip single-word titles to avoid common word false positives
    if (!hasAiValidation && countWords(entry.plainTitle) < MIN_WORD_COUNT_WITHOUT_AI) return;

    // Build word-boundary regex for the plain title
    const pattern = new RegExp(
      `\\b${escapeRegex(entry.plainTitle)}\\b`,
      "gi",
    );

    const matches = masked.matchAll(pattern);
    Array.from(matches).forEach((match) => {
      const position = match.index ?? 0;
      const end = position + match[0].length;

      // Skip if this position overlaps with an existing match
      if (isOverlapping(position, end)) return;

      // Only take the first match per entry per file (conservative)
      if (candidates.some((c) => c.entry.relativePath === entry.relativePath)) return;

      matchedRanges.push({ start: position, end });

      candidates.push({
        entry,
        matchedText: content.substring(position, end),
        position,
        context: extractContext(content, position, match[0].length),
      });
    });
  });

  // Sort by position ascending for safe end-to-start replacement
  return [...candidates].sort((a, b) => a.position - b.position);
};

// --- Gemini Book Identification ---

/**
 * Build the identification prompt for Gemini.
 * Sends the file body and available book titles so Gemini can identify
 * genuine book references — not just validate deterministic matches.
 */
export const buildIdentificationPrompt = (
  fileBody: string,
  bookEntries: readonly ContentEntry[],
  fileRelativePath: string,
): { readonly system: string; readonly user: string } => {
  const bookList = bookEntries
    .map((e) => `- "${e.plainTitle}" (${e.relativePath})`)
    .join("\n");

  return {
    system: `You are a precise editorial assistant for a knowledge base of book reports. Your job is to identify genuine book references in a document.

You will receive:
1. The path and body text of a document.
2. A list of book titles and their file paths.

Your task: Determine which books from the list are genuinely referenced in the document AS BOOKS (literary works). This means the text is discussing, recommending, citing, or listing the book itself — not merely using a word that happens to match a book title.

Rules:
- Return the relativePath of each book that is genuinely referenced as a book.
- A book reference may use the main title without the subtitle. For example, "Thinking, Fast and Slow" references the book even if the full title includes a subtitle.
- DO NOT include a book if the matching word or phrase is used in a generic context. For example:
  - "diplomacy" meaning the practice of international relations → NOT a book reference
  - "foundation" meaning a base or organization → NOT a book reference
  - "common sense" meaning practical judgment → NOT a book reference
  - "abundance" meaning plentifulness → NOT a book reference
  - "on democracy" as a phrase in a sentence about democracy → NOT a book reference
- DO include a book when the text explicitly discusses, recommends, or cites it as a literary work, e.g.:
  - "I recommend reading Thinking, Fast and Slow" → YES
  - "The Alignment Problem by Brian Christian" → YES
  - Book recommendation sections, reading lists, "related books" sections → YES
- Be conservative: when in doubt, do NOT include the book.

Return ONLY a valid JSON array of relativePath strings for books genuinely referenced. Example: ["books/thinking-fast-and-slow.md", "books/deep-learning.md"]
If no books are genuinely referenced, return an empty array: []
No other text, no explanation, no markdown formatting.`,
    user: `File: ${fileRelativePath}

Available books:
${bookList}

Document body:
${fileBody}`,
  };
};

/**
 * Identify genuine book references using Gemini AI.
 * Returns an array of relativePaths for books genuinely referenced in the content.
 *
 * Implements retry with exponential backoff for per-minute rate limits.
 * Throws QuotaExhaustedError on daily quota exhaustion to halt the pipeline.
 */
export const identifyBooksWithGemini = async (
  fileBody: string,
  bookEntries: readonly ContentEntry[],
  fileRelativePath: string,
  apiKey: string,
  model: string,
): Promise<readonly string[]> => {
  if (bookEntries.length === 0) return [];

  const { GoogleGenAI } = await import("@google/genai");
  const ai = new GoogleGenAI({ apiKey });

  const prompt = buildIdentificationPrompt(fileBody, bookEntries, fileRelativePath);
  const contents = [
    {
      role: "user" as const,
      parts: [{ text: `${prompt.system}\n\n${prompt.user}` }],
    },
  ];

  let backoffMs = INITIAL_BACKOFF_MS;

  for (let attempt = 0; attempt <= MAX_GEMINI_RETRIES; attempt++) {
    try {
      const result = await ai.models.generateContent({
        model,
        contents,
        config: {
          temperature: 0,
          responseMimeType: "application/json",
        },
      });

      const text = (result.text ?? "").trim();
      const parsed = JSON.parse(text);

      if (
        !Array.isArray(parsed) ||
        !parsed.every((v: unknown) => typeof v === "string")
      ) {
        console.error(
          JSON.stringify({
            event: "gemini_identification_invalid_response",
            file: fileRelativePath,
            got: parsed,
          }),
        );
        return [];
      }

      return parsed as readonly string[];
    } catch (error) {
      if (isDailyQuotaError(error)) {
        console.error(
          JSON.stringify({
            event: "gemini_daily_quota_exhausted",
            file: fileRelativePath,
            error: error instanceof Error ? error.message : String(error),
          }),
        );
        throw new QuotaExhaustedError();
      }

      if (isRateLimitError(error) && attempt < MAX_GEMINI_RETRIES) {
        const serverDelay = parseRetryDelay(error);
        const waitMs = serverDelay ?? backoffMs;
        console.warn(
          JSON.stringify({
            event: "gemini_rate_limit_retry",
            file: fileRelativePath,
            attempt: attempt + 1,
            maxRetries: MAX_GEMINI_RETRIES,
            waitMs,
          }),
        );
        await sleep(waitMs);
        backoffMs = Math.min(backoffMs * 2, MAX_BACKOFF_MS);
        continue;
      }

      console.error(
        JSON.stringify({
          event: "gemini_identification_error",
          file: fileRelativePath,
          error: error instanceof Error ? error.message : String(error),
        }),
      );
      return [];
    }
  }

  console.error(
    JSON.stringify({
      event: "gemini_retries_exhausted",
      file: fileRelativePath,
      maxRetries: MAX_GEMINI_RETRIES,
    }),
  );
  return [];
};

// --- Replacement Application ---

/**
 * Generate a minimal diff showing only changed lines between original and modified content.
 * Returns an array of diff hunks, each showing the line number, old line, and new line.
 */
export const generateDiff = (
  original: string,
  modified: string,
): readonly string[] => {
  const originalLines = original.split("\n");
  const modifiedLines = modified.split("\n");
  const maxLen = Math.max(originalLines.length, modifiedLines.length);

  return Array.from({ length: maxLen })
    .flatMap((_, i) => {
      const origLine = originalLines[i];
      const modLine = modifiedLines[i];
      return origLine !== modLine
        ? [
            `@@ line ${i + 1} @@`,
            ...(origLine !== undefined ? [`- ${origLine}`] : []),
            ...(modLine !== undefined ? [`+ ${modLine}`] : []),
          ]
        : [];
    });
};

/**
 * Apply wikilink replacements to content.
 * Processes replacements from end to start to preserve positions.
 * Only replaces candidates where the validation is true.
 */
export const applyReplacements = (
  content: string,
  candidates: readonly LinkCandidate[],
  validations: readonly boolean[],
): string => {
  // Process from end to start to preserve earlier positions
  const validReplacements = candidates
    .map((candidate, i) => ({ candidate, valid: validations[i] ?? false }))
    .filter(({ valid }) => valid)
    .sort((a, b) => b.candidate.position - a.candidate.position);

  return validReplacements.reduce((acc, { candidate }) => {
    const before = acc.substring(0, candidate.position);
    const after = acc.substring(candidate.position + candidate.matchedText.length);
    const wikilink = formatWikilink(candidate.entry);
    return `${before}${wikilink}${after}`;
  }, content);
};

// --- Frontmatter Timestamp ---

/**
 * Update the "updated" frontmatter field for a file to the given ISO 8601 timestamp.
 * Creates the field if missing, creates a frontmatter block if absent.
 * Used to leave a BFS trail so Enveloppe can discover modified files.
 */
export const updateFrontmatterTimestamp = (
  filePath: string,
  timestamp: string,
): void => {
  if (!fs.existsSync(filePath)) return;

  const raw = fs.readFileSync(filePath, "utf-8");
  const lines = raw.split("\n");

  if (lines[0]?.trim() === "---") {
    const endIndex = lines.findIndex((l, i) => i > 0 && l.trim() === "---");
    if (endIndex < 0) return;

    const updatedLineIndex = lines.findIndex(
      (l, i) => i > 0 && i < endIndex && /^updated:\s/.test(l),
    );

    if (updatedLineIndex >= 0) {
      lines[updatedLineIndex] = `updated: ${timestamp}`;
    } else {
      lines.splice(endIndex, 0, `updated: ${timestamp}`);
    }

    fs.writeFileSync(filePath, lines.join("\n"), "utf-8");
  } else {
    fs.writeFileSync(filePath, `---\nupdated: ${timestamp}\n---\n${raw}`, "utf-8");
  }
};

// --- File Processing ---

/**
 * Extract the body text from a markdown file (everything after frontmatter).
 */
export const extractBody = (content: string): string => {
  const lines = content.split("\n");
  if (lines[0]?.trim() !== "---") return content;
  const endIndex = lines.findIndex((l, i) => i > 0 && l.trim() === "---");
  return endIndex >= 0 ? lines.slice(endIndex + 1).join("\n") : content;
};

/**
 * Process a single file: use Gemini to identify book references, find positions, apply links.
 *
 * New architecture: Gemini IDENTIFIES which books are referenced (not just validates).
 * Deterministic position finding is only used AFTER Gemini confirms a book is referenced.
 * Throws QuotaExhaustedError on daily quota exhaustion to halt the pipeline.
 */
export const processFile = async (
  relativePath: string,
  contentDir: string,
  index: readonly ContentEntry[],
  config: LinkingConfig,
): Promise<FileResult> => {
  const filePath = path.join(contentDir, relativePath);
  const content = fs.readFileSync(filePath, "utf-8");
  const body = extractBody(content);

  // Filter index to books not already linked in this file
  const eligibleBooks = index.filter(
    (entry) =>
      entry.relativePath !== relativePath &&
      !contentAlreadyLinksTo(content, entry),
  );

  if (eligibleBooks.length === 0) {
    return { relativePath, linksAdded: 0, modified: false };
  }

  // Use Gemini to IDENTIFY which books are genuinely referenced
  // (not just deterministic string matching)
  const identifiedPaths = config.apiKey
    ? await identifyBooksWithGemini(body, eligibleBooks, relativePath, config.apiKey, config.model)
    : [];

  if (identifiedPaths.length === 0) {
    return { relativePath, linksAdded: 0, modified: false };
  }

  // Build a set of Gemini-identified books
  const identifiedSet = new Set(identifiedPaths);

  console.log(
    JSON.stringify({
      event: "books_identified",
      file: relativePath,
      count: identifiedPaths.length,
      books: identifiedPaths,
    }),
  );

  // Now find positions for only the identified books using deterministic matching
  const masked = maskProtectedRegions(content);
  const identifiedIndex = index.filter((e) => identifiedSet.has(e.relativePath));
  const existingLinks = extractExistingLinkedPaths(content, relativePath, contentDir);
  const candidates = findLinkCandidates(content, masked, identifiedIndex, existingLinks, relativePath, true);

  if (candidates.length === 0) {
    return { relativePath, linksAdded: 0, modified: false };
  }

  // All candidates are Gemini-approved — apply all
  const validations = candidates.map(() => true);
  const newContent = applyReplacements(content, candidates, validations);

  if (config.dryRun) {
    const diffLines = generateDiff(content, newContent);
    if (diffLines.length > 0) {
      console.log(
        JSON.stringify({
          event: "dry_run_diff",
          file: relativePath,
          diff: diffLines,
        }),
      );
    }
  } else {
    fs.writeFileSync(filePath, newContent, "utf-8");
  }

  console.log(
    JSON.stringify({
      event: "links_applied",
      file: relativePath,
      linksAdded: candidates.length,
      dryRun: config.dryRun,
      links: candidates.map((c) => ({
        matched: c.matchedText,
        target: c.entry.relativePath,
        title: c.entry.title,
      })),
    }),
  );

  return { relativePath, linksAdded: candidates.length, modified: true };
};

// --- Orchestration ---

/**
 * Run the full internal linking pipeline.
 * 1. Build content index (books only)
 * 2. BFS from most recent reflection
 * 3. Update "updated" timestamps along BFS path (for Enveloppe discovery)
 * 4. For each file, find and validate book link candidates
 * 5. Apply wikilink replacements
 */
export const run = async (config: LinkingConfig): Promise<RunResult> => {
  console.log(
    JSON.stringify({
      event: "internal_linking_start",
      contentDir: config.contentDir,
      maxFiles: config.maxFiles,
      model: config.model,
      dryRun: config.dryRun,
      hasApiKey: !!config.apiKey,
    }),
  );

  // Build content index (books only)
  const index = buildContentIndex(config.contentDir);
  console.log(JSON.stringify({ event: "index_built", entries: index.length }));

  // BFS traversal
  const filesToVisit = bfsTraversal(config.contentDir, config.maxFiles);
  console.log(
    JSON.stringify({
      event: "bfs_complete",
      filesFound: filesToVisit.length,
      maxFiles: config.maxFiles,
    }),
  );

  // Update "updated" timestamps along the BFS path so Enveloppe can discover changes
  const timestamp = new Date().toISOString();
  if (!config.dryRun) {
    filesToVisit.forEach((relativePath) => {
      const filePath = path.join(config.contentDir, relativePath);
      updateFrontmatterTimestamp(filePath, timestamp);
    });
    console.log(
      JSON.stringify({
        event: "timestamps_updated",
        filesUpdated: filesToVisit.length,
        timestamp,
      }),
    );
  }

  // Process each file sequentially (to respect Gemini rate limits)
  // QuotaExhaustedError halts the pipeline immediately
  const fileResults: FileResult[] = [];
  for (const relativePath of filesToVisit) {
    try {
      const result = await processFile(relativePath, config.contentDir, index, config);
      fileResults.push(result);
    } catch (error) {
      if (error instanceof QuotaExhaustedError) {
        console.error(
          JSON.stringify({
            event: "pipeline_halted_quota_exhausted",
            filesProcessed: fileResults.length,
            filesRemaining: filesToVisit.length - fileResults.length,
          }),
        );
        break;
      }
      throw error;
    }
  }

  const filesModified = fileResults.filter((r) => r.modified).length;
  const totalLinksAdded = fileResults.reduce((sum, r) => sum + r.linksAdded, 0);

  const runResult: RunResult = {
    filesVisited: filesToVisit.length,
    filesModified,
    totalLinksAdded,
    fileResults,
  };

  console.log(
    JSON.stringify({
      event: "internal_linking_complete",
      ...runResult,
      fileResults: undefined,
    }),
  );

  return runResult;
};
