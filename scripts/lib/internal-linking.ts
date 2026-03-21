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

/** Default Gemini model for link validation */
export const DEFAULT_LINKING_MODEL = "gemini-3.1-flash-lite-preview";

/** Content subdirectories to index (skip bot-chats, they're not linkable content) */
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
  "reflections",
  "chickie-loo",
  "auto-blog-zero",
] as const;

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
  INDEXABLE_DIRS.flatMap((dir) => {
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
 * Find link candidates in a file by searching masked content for plain-title matches.
 * Returns candidates sorted by position (ascending) for safe replacement.
 */
export const findLinkCandidates = (
  content: string,
  masked: string,
  index: readonly ContentEntry[],
  existingLinks: ReadonlySet<string>,
  selfPath: string,
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

// --- Gemini Validation ---

/**
 * Build the validation prompt for Gemini.
 * Asks the model to validate each candidate link.
 */
export const buildValidationPrompt = (
  candidates: readonly LinkCandidate[],
  fileRelativePath: string,
): { readonly system: string; readonly user: string } => {
  const candidateDescriptions = candidates
    .map(
      (c, i) =>
        `${i + 1}. Matched text: "${c.matchedText}"
   Proposed link target: ${c.entry.relativePath} (${c.entry.title})
   Context: "${c.context}"`,
    )
    .join("\n\n");

  return {
    system: `You are a precise editorial assistant for a knowledge base. Your job is to validate proposed internal links.

For each candidate below, determine if the matched plain text genuinely refers to the proposed content page.

Rules:
- Return true ONLY if you are confident the text refers to exactly the same work/concept as the proposed link target.
- Return false if the match is coincidental, partial, ambiguous, or could refer to something else.
- A book title in body text that exactly matches a book report title should be true.
- A software name that matches a software page should be true if used in that context.
- A person's name that matches a person page should be true if referring to that person.
- Be conservative: when in doubt, return false.

Return ONLY a valid JSON array of booleans, one per candidate. Example: [true, false, true]
No other text, no explanation, no markdown formatting.`,
    user: `File: ${fileRelativePath}

Candidates to validate:

${candidateDescriptions}`,
  };
};

/**
 * Validate link candidates using Gemini AI.
 * Returns an array of booleans, one per candidate (true = valid link).
 * On any error, returns all false (conservative: skip file on failure).
 */
export const validateWithGemini = async (
  candidates: readonly LinkCandidate[],
  fileRelativePath: string,
  apiKey: string,
  model: string,
): Promise<readonly boolean[]> => {
  if (candidates.length === 0) return [];

  try {
    const { GoogleGenAI } = await import("@google/genai");
    const ai = new GoogleGenAI({ apiKey });

    const prompt = buildValidationPrompt(candidates, fileRelativePath);
    const contents = [
      {
        role: "user" as const,
        parts: [{ text: `${prompt.system}\n\n${prompt.user}` }],
      },
    ];

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
      parsed.length !== candidates.length ||
      !parsed.every((v: unknown) => typeof v === "boolean")
    ) {
      console.error(
        JSON.stringify({
          event: "gemini_validation_invalid_response",
          expected: candidates.length,
          got: parsed,
        }),
      );
      return candidates.map(() => false);
    }

    return parsed as readonly boolean[];
  } catch (error) {
    console.error(
      JSON.stringify({
        event: "gemini_validation_error",
        file: fileRelativePath,
        error: error instanceof Error ? error.message : String(error),
      }),
    );
    return candidates.map(() => false);
  }
};

// --- Replacement Application ---

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

// --- File Processing ---

/**
 * Process a single file: find candidates, validate with AI, apply replacements.
 */
export const processFile = async (
  relativePath: string,
  contentDir: string,
  index: readonly ContentEntry[],
  config: LinkingConfig,
): Promise<FileResult> => {
  const filePath = path.join(contentDir, relativePath);
  const content = fs.readFileSync(filePath, "utf-8");

  // Find existing links to avoid double-linking
  const existingLinks = extractExistingLinkedPaths(content, relativePath, contentDir);

  // Mask protected regions and find candidates
  const masked = maskProtectedRegions(content);
  const candidates = findLinkCandidates(content, masked, index, existingLinks, relativePath);

  if (candidates.length === 0) {
    return { relativePath, linksAdded: 0, modified: false };
  }

  console.log(
    JSON.stringify({
      event: "candidates_found",
      file: relativePath,
      count: candidates.length,
      candidates: candidates.map((c) => ({
        text: c.matchedText,
        target: c.entry.relativePath,
      })),
    }),
  );

  // Validate with Gemini if API key is available
  const validations = config.apiKey
    ? await validateWithGemini(candidates, relativePath, config.apiKey, config.model)
    : candidates.map(() => true); // Without AI, accept all deterministic matches

  const validCount = validations.filter(Boolean).length;

  if (validCount === 0) {
    return { relativePath, linksAdded: 0, modified: false };
  }

  // Apply replacements
  const newContent = applyReplacements(content, candidates, validations);

  if (!config.dryRun) {
    fs.writeFileSync(filePath, newContent, "utf-8");
  }

  console.log(
    JSON.stringify({
      event: "links_applied",
      file: relativePath,
      linksAdded: validCount,
      dryRun: config.dryRun,
      links: candidates
        .filter((_, i) => validations[i])
        .map((c) => ({
          matched: c.matchedText,
          target: c.entry.relativePath,
          title: c.entry.title,
        })),
    }),
  );

  return { relativePath, linksAdded: validCount, modified: true };
};

// --- Orchestration ---

/**
 * Run the full internal linking pipeline.
 * 1. Build content index
 * 2. BFS from most recent reflection
 * 3. For each file, find and validate link candidates
 * 4. Apply wikilink replacements
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

  // Build content index
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

  // Process each file sequentially (to respect Gemini rate limits)
  const fileResults: FileResult[] = [];
  for (const relativePath of filesToVisit) {
    const result = await processFile(relativePath, config.contentDir, index, config);
    fileResults.push(result);
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
