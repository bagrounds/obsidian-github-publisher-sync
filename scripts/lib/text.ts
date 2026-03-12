/**
 * Pure text processing functions for social media post formatting.
 *
 * All functions are pure (no side effects, no I/O) and operate on
 * string values. They implement the domain rules for platform-specific
 * text length constraints.
 *
 * Key abstractions:
 * - Grapheme counting: Unicode-aware character counting (emoji = 1)
 * - Tweet length: Twitter's URL shortening rule (URLs = 23 chars)
 * - Post fitting: Progressive content removal to meet length limits
 *
 * @module text
 */

import { TWITTER_URL_LENGTH, TWITTER_MAX_LENGTH } from "./types.ts";

// --- Grapheme Operations ---

const createSegmenter = () => new Intl.Segmenter("en", { granularity: "grapheme" });

/**
 * Count Unicode grapheme clusters in text.
 *
 * Graphemes represent user-perceived characters — e.g. 👨‍💻 is one grapheme
 * despite being multiple code points. Bluesky enforces a 300-grapheme limit.
 *
 * Uses Intl.Segmenter — the standard Unicode grapheme segmentation API.
 */
export const countGraphemes = (text: string): number => {
  let count = 0;
  for (const _ of createSegmenter().segment(text)) count++;
  return count;
};

/**
 * Truncate text to a grapheme limit, appending "…" if truncated.
 * Returns the original text unchanged if already within the limit.
 */
export const truncateToGraphemeLimit = (text: string, maxGraphemes: number): string => {
  const segments = [...createSegmenter().segment(text)];
  if (segments.length <= maxGraphemes) return text;
  return segments.slice(0, maxGraphemes - 1).map((s) => s.segment).join("") + "…";
};

// --- Tweet Length ---

const URL_REGEX = /https?:\/\/[^\s]+/g;

/**
 * Calculate effective tweet length accounting for Twitter's t.co URL shortening.
 * URLs are always counted as 23 characters by Twitter.
 */
export const calculateTweetLength = (text: string): number => {
  const urls = text.match(URL_REGEX) ?? [];
  const urlLengthDelta = urls.reduce(
    (delta, url) => delta + (TWITTER_URL_LENGTH - url.length),
    0,
  );
  return text.length + urlLengthDelta;
};

/**
 * Validate that tweet text is within Twitter's character limit.
 */
export const validateTweetLength = (text: string): { valid: boolean; length: number } => {
  const length = calculateTweetLength(text);
  return { valid: length <= TWITTER_MAX_LENGTH, length };
};

// --- Post Fitting ---

/**
 * Find the last index in an array matching a predicate.
 * Functional alternative to a reverse for-loop.
 */
const findLastIndex = <T>(
  arr: readonly T[],
  predicate: (value: T, index: number) => boolean,
): number => {
  for (let i = arr.length - 1; i >= 0; i--) {
    if (predicate(arr[i] as T, i)) return i;
  }
  return -1;
};

/** Rebuild post text with a modified topic line. */
const rebuildPost = (
  contentLines: readonly string[],
  topicIndex: number,
  newTopicLine: string,
  urlLine: string,
  trailingLines: readonly string[],
): string => {
  const updated = [...contentLines];
  updated[topicIndex] = newTopicLine;
  return [...updated, urlLine, ...trailingLines].join("\n");
};

/**
 * Fit post text to a platform's grapheme limit by progressively removing
 * content in order of decreasing expendability:
 *
 * 1. Remove pipe-separated topic tags from right to left
 * 2. Remove the entire topic line (and preceding blank line)
 * 3. Strip subtitle from title (remove everything after the first colon)
 * 4. Remove the title entirely (and following blank line)
 * 5. Truncate remaining content with "…"
 *
 * The URL line is always preserved — it's essential for link previews
 * and facet detection.
 *
 * Post format (variant B):
 *   Line 0: Title
 *   Line 1: (blank)
 *   Line 2: #AI Q: Question?
 *   Line 3: (blank)
 *   Line 4: {emoji} Tag | {emoji} Tag | ...
 *   Line 5: https://bagrounds.org/...
 */
export const fitPostToLimit = (text: string, maxGraphemes: number): string => {
  if (countGraphemes(text) <= maxGraphemes) return text;

  const lines = text.split("\n");
  const urlLineIndex = findLastIndex(lines, (l) => /^https?:\/\//.test(l));

  if (urlLineIndex < 0) return truncateToGraphemeLimit(text, maxGraphemes);

  const urlLine = lines[urlLineIndex] as string;
  const contentLines = lines.slice(0, urlLineIndex);
  const trailingLines = lines.slice(urlLineIndex + 1);

  const topicIndex = findLastIndex(
    contentLines,
    (l, i) => i > 0 && l.includes(" | "),
  );

  // Strategy 1: Remove topic tags from right to left
  if (topicIndex >= 0) {
    const tags = (contentLines[topicIndex] as string).split(" | ");

    while (tags.length > 1) {
      tags.pop();
      const candidate = rebuildPost(contentLines, topicIndex, tags.join(" | "), urlLine, trailingLines);
      if (countGraphemes(candidate) <= maxGraphemes) return candidate;
    }

    // Strategy 2: Remove topic line entirely (and preceding blank line)
    const trimmedContent = [...contentLines];
    trimmedContent.splice(topicIndex, 1);
    if (topicIndex > 0 && trimmedContent[topicIndex - 1] === "") {
      trimmedContent.splice(topicIndex - 1, 1);
    }

    const candidate = [...trimmedContent, urlLine, ...trailingLines].join("\n");
    if (countGraphemes(candidate) <= maxGraphemes) return candidate;
  }

  // Strategy 3: Strip subtitle from title (remove after first colon)
  {
    const workingLines = topicIndex >= 0
      ? (() => {
          const cl = [...contentLines];
          cl.splice(topicIndex, 1);
          if (topicIndex > 0 && cl[topicIndex - 1] === "") cl.splice(topicIndex - 1, 1);
          return cl;
        })()
      : [...contentLines];

    const titleLine = workingLines[0] ?? "";
    const colonIndex = titleLine.indexOf(":");
    if (colonIndex > 0) {
      const shortTitle = titleLine.slice(0, colonIndex).trim();
      if (shortTitle.length > 0) {
        workingLines[0] = shortTitle;
        const candidate = [...workingLines, urlLine, ...trailingLines].join("\n");
        if (countGraphemes(candidate) <= maxGraphemes) return candidate;
      }
    }

    // Strategy 4: Remove title entirely (and following blank line)
    if (workingLines.length > 0) {
      const noTitle = [...workingLines];
      noTitle.splice(0, 1);
      // Remove the blank line that was after the title
      if (noTitle.length > 0 && noTitle[0] === "") {
        noTitle.splice(0, 1);
      }
      const candidate = [...noTitle, urlLine, ...trailingLines].join("\n");
      if (countGraphemes(candidate) <= maxGraphemes) return candidate;
    }
  }

  // Strategy 5: Truncate content before URL
  const separatorAndUrl = "\n" + urlLine;
  const reservedGraphemes = countGraphemes(separatorAndUrl);
  const available = maxGraphemes - reservedGraphemes;

  if (available > 1) {
    const contentText = contentLines.join("\n");
    return truncateToGraphemeLimit(contentText, available) + separatorAndUrl;
  }

  return truncateToGraphemeLimit(text, maxGraphemes);
};
