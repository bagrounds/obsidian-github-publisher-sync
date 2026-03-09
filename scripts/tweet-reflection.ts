/**
 * Social Post Reflection Automation Script
 *
 * Reads yesterday's reflection from the repo, generates a post via Gemini,
 * posts it to Twitter, Bluesky, and Mastodon, fetches the embed code, and
 * writes the updated note back to the Obsidian vault via Obsidian Headless Sync.
 *
 * Twitter, Bluesky, and Mastodon are all optional — the script posts to whichever
 * platforms have credentials configured. Platform failures are logged but
 * don't crash the pipeline.
 *
 * The user reviews the change in Obsidian and publishes it to this repo
 * via the Enveloppe plugin (one-way sync: Obsidian → GitHub).
 *
 * Usage:
 *   npx tsx scripts/tweet-reflection.ts [--date YYYY-MM-DD]
 *
 * Environment variables:
 *   TWITTER_API_KEY       - (Optional) OAuth 1.0a Consumer Key (from X Developer Portal → Keys and Tokens)
 *   TWITTER_API_SECRET    - (Optional) OAuth 1.0a Consumer Secret
 *   TWITTER_ACCESS_TOKEN  - (Optional) OAuth 1.0a Access Token (generated with Read+Write permissions)
 *   TWITTER_ACCESS_SECRET - (Optional) OAuth 1.0a Access Token Secret
 *   BLUESKY_IDENTIFIER    - (Optional) Bluesky handle (e.g. "bagrounds.bsky.social") or DID
 *   BLUESKY_APP_PASSWORD  - (Optional) Bluesky App Password (from Settings → App Passwords)
 *   MASTODON_INSTANCE_URL - (Optional) Mastodon instance URL (e.g. "https://mastodon.social")
 *   MASTODON_ACCESS_TOKEN - (Optional) Mastodon access token (from Settings → Development → Your Application)
 *   GEMINI_API_KEY        - Google Gemini API key (from Google AI Studio)
 *   GEMINI_MODEL          - (Optional) Gemini model name, defaults to gemma-3-27b-it
 *   OBSIDIAN_AUTH_TOKEN   - Obsidian account auth token (from `ob login`)
 *   OBSIDIAN_VAULT_NAME   - Remote vault name or ID in Obsidian Sync
 *   OBSIDIAN_VAULT_PASSWORD - (Optional) E2EE vault password, if vault uses end-to-end encryption
 *
 * @see https://github.com/PLhery/node-twitter-api-v2 — twitter-api-v2 docs
 * @see https://docs.bsky.app/ — Bluesky/AT Protocol API docs
 * @see https://docs.joinmastodon.org/methods/statuses/ — Mastodon API docs
 * @see https://ai.google.dev/gemini-api/docs — Google Gemini API docs
 * @see https://help.obsidian.md/sync/headless — Obsidian Headless Sync docs
 * @see https://github.com/obsidianmd/obsidian-headless — obsidian-headless CLI
 * @see https://developer.x.com/en/docs/twitter-api — X/Twitter API v2 docs
 */

import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFile as execFileCb, exec as execCb } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFileCb);
const execAsync = promisify(execCb);

// --- Timing Instrumentation ---

/**
 * Lightweight timer for profiling pipeline phases.
 * Records start/end of named phases and prints a summary table.
 */
export class PipelineTimer {
  private entries: Array<{ name: string; startMs: number; endMs?: number }> = [];
  private pipelineStartMs = Date.now();

  /** Start timing a named phase. */
  start(name: string): void {
    this.entries.push({ name, startMs: Date.now() });
  }

  /** End timing a named phase. */
  end(name: string): void {
    const entry = this.entries.find((e) => e.name === name && !e.endMs);
    if (entry) entry.endMs = Date.now();
  }

  /** Time an async operation, returning its result. */
  async time<T>(name: string, fn: () => Promise<T>): Promise<T> {
    this.start(name);
    try {
      return await fn();
    } finally {
      this.end(name);
    }
  }

  /** Print a summary of all recorded phases. */
  printSummary(): void {
    const totalMs = Date.now() - this.pipelineStartMs;
    console.log(`\n⏱️  Pipeline Timing Summary:`);
    console.log(`${"─".repeat(52)}`);
    for (const entry of this.entries) {
      const durationMs = (entry.endMs ?? Date.now()) - entry.startMs;
      const pct = totalMs > 0 ? ((durationMs / totalMs) * 100).toFixed(1) : "0.0";
      const status = entry.endMs ? "✅" : "⏳";
      console.log(
        `  ${status} ${entry.name.padEnd(30)} ${(durationMs / 1000).toFixed(1).padStart(7)}s  (${pct.padStart(5)}%)`,
      );
    }
    console.log(`${"─".repeat(52)}`);
    console.log(`  🏁 Total pipeline time${" ".repeat(13)} ${(totalMs / 1000).toFixed(1)}s`);
  }
}

// --- Types ---

export interface ReflectionData {
  /** The date string YYYY-MM-DD */
  date: string;
  /** Full title from frontmatter */
  title: string;
  /** URL from frontmatter */
  url: string;
  /** Raw markdown body (after frontmatter) */
  body: string;
  /** Full file path */
  filePath: string;
  /** Whether a tweet section already exists */
  hasTweetSection: boolean;
  /** Whether a Bluesky section already exists */
  hasBlueskySection: boolean;
  /** Whether a Mastodon section already exists */
  hasMastodonSection: boolean;
}

export interface TweetResult {
  /** Tweet ID returned by Twitter */
  id: string;
  /** Full tweet text that was posted */
  text: string;
}

export interface BlueskyPostResult {
  /** Post URI (at:// protocol) */
  uri: string;
  /** Post CID (content identifier) */
  cid: string;
  /** Full post text that was posted */
  text: string;
}

export interface MastodonPostResult {
  /** Status ID from Mastodon */
  id: string;
  /** Full URL of the posted status */
  url: string;
  /** Full post text that was posted */
  text: string;
}

export interface EmbedResult {
  /** HTML embed code */
  html: string;
}

// --- Constants ---

const TWITTER_HANDLE = "bagrounds";
const TWITTER_DISPLAY_NAME = "Bryan Grounds";
const BLUESKY_DISPLAY_NAME = "Bryan Grounds";
const TWEET_SECTION_HEADER = "## 🐦 Tweet";
const BLUESKY_SECTION_HEADER = "## 🦋 Bluesky";
const MASTODON_SECTION_HEADER = "## 🐘 Mastodon";
/** Twitter counts all URLs as 23 characters */
const TWITTER_URL_LENGTH = 23;
const TWITTER_MAX_LENGTH = 280;
/** Bluesky has a 300-character limit for post text */
const BLUESKY_MAX_LENGTH = 300;
/** Mastodon default character limit is 500 (instance-configurable) */
const MASTODON_MAX_LENGTH = 500;
const MASTODON_DISPLAY_NAME = "Bryan Grounds";
/** Shared month names for date formatting in embed HTML */
const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];
/** Delay before first Bluesky oEmbed attempt to allow post propagation.
 * Reduced from 3s → 0s: local embed generation is reliable and instant.
 * oEmbed is attempted immediately as a best-effort upgrade. */
const BLUESKY_OEMBED_INITIAL_DELAY_MS = 0;
/** Delay before retrying Bluesky oEmbed on 404. Reduced from 5s → 2s. */
const BLUESKY_OEMBED_RETRY_DELAY_MS = 2_000;

/** Section data for writing embeds to Obsidian notes */
export interface EmbedSection {
  header: string;
  embedHtml: string;
  buildSection: (content: string, html: string) => string;
}
/** Default Gemini model — Gemma 3 27B has a generous free tier (14,400 RPD) */
const DEFAULT_GEMINI_MODEL = "gemma-3-27b-it";

// --- Reflection File Operations ---

/**
 * Get the file path for a reflection by date.
 */
export function getReflectionPath(
  date: string,
  contentDir: string,
): string {
  return path.join(contentDir, `${date}.md`);
}

/**
 * Parse frontmatter from a markdown string.
 * Returns the frontmatter key-value pairs and the body after frontmatter.
 */
export function parseFrontmatter(content: string): {
  frontmatter: Record<string, string>;
  body: string;
} {
  const frontmatter: Record<string, string> = {};
  const lines = content.split("\n");

  if (lines[0]?.trim() !== "---") {
    return { frontmatter, body: content };
  }

  let endIndex = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i]?.trim() === "---") {
      endIndex = i;
      break;
    }
    const match = lines[i]?.match(/^(\w+):\s*(.*)$/);
    if (match) {
      const key = match[1] as string;
      const value = match[2] as string;
      frontmatter[key] = value.replace(/^["']|["']$/g, "");
    }
  }

  const body = endIndex >= 0 ? lines.slice(endIndex + 1).join("\n") : content;
  return { frontmatter, body };
}

/**
 * Read and parse a reflection file.
 */
export function readReflection(
  date: string,
  contentDir: string,
): ReflectionData | null {
  const filePath = getReflectionPath(date, contentDir);

  if (!fs.existsSync(filePath)) {
    return null;
  }

  const content = fs.readFileSync(filePath, "utf-8");
  const { frontmatter, body } = parseFrontmatter(content);

  return {
    date,
    title: frontmatter["title"] || date,
    url: frontmatter["URL"] || `https://bagrounds.org/reflections/${date}`,
    body,
    filePath,
    hasTweetSection: content.includes(TWEET_SECTION_HEADER),
    hasBlueskySection: content.includes(BLUESKY_SECTION_HEADER),
    hasMastodonSection: content.includes(MASTODON_SECTION_HEADER),
  };
}

/**
 * Read and parse an arbitrary content note (not just reflections by date).
 * Works for any .md file under the content directory.
 */
export function readNote(
  relativePath: string,
  contentDir: string,
): ReflectionData | null {
  const filePath = path.join(contentDir, relativePath);

  if (!fs.existsSync(filePath)) {
    return null;
  }

  const content = fs.readFileSync(filePath, "utf-8");
  const { frontmatter, body } = parseFrontmatter(content);

  // Extract date from filename if it's a reflection, otherwise use today
  const dateMatch = path.basename(relativePath).match(/^(\d{4}-\d{2}-\d{2})/);
  const date = dateMatch ? dateMatch[1] as string : new Date().toISOString().split("T")[0] as string;

  // Derive URL from frontmatter or from relative path
  const slug = relativePath.replace(/\.md$/, "");
  const url = frontmatter["URL"] || `https://bagrounds.org/${slug}`;

  return {
    date,
    title: frontmatter["title"] || path.basename(relativePath, ".md"),
    url,
    body,
    filePath,
    hasTweetSection: content.includes(TWEET_SECTION_HEADER),
    hasBlueskySection: content.includes(BLUESKY_SECTION_HEADER),
    hasMastodonSection: content.includes(MASTODON_SECTION_HEADER),
  };
}

/**
 * Calculate effective tweet length accounting for Twitter's t.co URL shortening.
 * URLs are always counted as 23 characters by Twitter.
 */
export function calculateTweetLength(text: string): number {
  // Match URLs in the text
  const urlRegex = /https?:\/\/[^\s]+/g;
  let length = text.length;
  const urls = text.match(urlRegex);
  if (urls) {
    for (const url of urls) {
      // Replace actual URL length with Twitter's fixed URL length
      length = length - url.length + TWITTER_URL_LENGTH;
    }
  }
  return length;
}

/**
 * Validate that tweet text is within Twitter's character limit.
 */
export function validateTweetLength(text: string): {
  valid: boolean;
  length: number;
} {
  const length = calculateTweetLength(text);
  return { valid: length <= TWITTER_MAX_LENGTH, length };
}

// --- Platform-Aware Length Enforcement ---

/**
 * Count Unicode grapheme clusters in text.
 * Bluesky enforces a 300-grapheme limit (not characters or bytes).
 * Graphemes represent user-perceived characters — e.g. 👨‍💻 is one grapheme
 * despite being multiple code points.
 *
 * @see https://docs.bsky.app/docs/api/app.bsky.feed.post
 * @see https://unicode.org/reports/tr29/#Grapheme_Cluster_Boundaries
 */
export function countGraphemes(text: string): number {
  const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
  let count = 0;
  for (const _ of segmenter.segment(text)) {
    count++;
  }
  return count;
}

/**
 * Truncate text to a grapheme limit, appending "…" if truncated.
 * Returns the original text unchanged if already within the limit.
 */
export function truncateToGraphemeLimit(
  text: string,
  maxGraphemes: number,
): string {
  const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
  const segments = [...segmenter.segment(text)];
  if (segments.length <= maxGraphemes) return text;

  // Reserve 1 grapheme for the ellipsis
  const truncated = segments
    .slice(0, maxGraphemes - 1)
    .map((s) => s.segment)
    .join("");
  return truncated + "…";
}

/**
 * Fit post text to a platform's grapheme limit by progressively removing
 * content in order of decreasing expendability:
 *
 * 1. Remove pipe-separated topic tags from right to left
 * 2. Remove the entire topic line (and preceding blank line)
 * 3. Truncate remaining content with "…"
 *
 * The URL line is always preserved — it's essential for link previews
 * and facet detection.
 *
 * Post format (from Gemini prompt):
 *   Line 1: {date} | {emoji} Title Words {emoji}
 *   Line 2: (blank)
 *   Line 3: {emoji} Tag | {emoji} Tag | ...
 *   Line 4: https://bagrounds.org/...
 */
export function fitPostToLimit(text: string, maxGraphemes: number): string {
  if (countGraphemes(text) <= maxGraphemes) return text;

  const lines = text.split("\n");

  // Find the URL line — always preserved
  const urlLineIndex = findLastIndex(lines, (l) => /^https?:\/\//.test(l));

  if (urlLineIndex < 0) {
    // No URL found — fall back to simple truncation
    return truncateToGraphemeLimit(text, maxGraphemes);
  }

  const urlLine = lines[urlLineIndex] as string;
  const contentLines = lines.slice(0, urlLineIndex);
  const trailingLines = lines.slice(urlLineIndex + 1);

  // Find the topic line: last content line containing " | " that isn't line 0
  const topicIndex = findLastIndex(
    contentLines,
    (l, i) => i > 0 && l.includes(" | "),
  );

  // Strategy 1: Remove topic tags from right to left
  if (topicIndex >= 0) {
    const topicLine = contentLines[topicIndex] as string;
    const tags = topicLine.split(" | ");

    while (tags.length > 1) {
      tags.pop();
      const candidate = rebuildPost(
        contentLines,
        topicIndex,
        tags.join(" | "),
        urlLine,
        trailingLines,
      );
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

  // Strategy 3: Truncate content before URL
  // Reserve space for the newline separator and URL line
  const separatorAndUrl = "\n" + urlLine;
  const reservedGraphemes = countGraphemes(separatorAndUrl);
  const available = maxGraphemes - reservedGraphemes;

  if (available > 1) {
    const contentText = contentLines.join("\n");
    const truncatedContent = truncateToGraphemeLimit(contentText, available);
    return truncatedContent + separatorAndUrl;
  }

  // Absolute last resort: truncate entire text
  return truncateToGraphemeLimit(text, maxGraphemes);
}

/** Rebuild post text with a modified topic line. */
function rebuildPost(
  contentLines: readonly string[],
  topicIndex: number,
  newTopicLine: string,
  urlLine: string,
  trailingLines: readonly string[],
): string {
  const updated = [...contentLines];
  updated[topicIndex] = newTopicLine;
  return [...updated, urlLine, ...trailingLines].join("\n");
}

/** Array.findLastIndex polyfill for readability. */
function findLastIndex<T>(
  arr: readonly T[],
  predicate: (value: T, index: number) => boolean,
): number {
  for (let i = arr.length - 1; i >= 0; i--) {
    if (predicate(arr[i] as T, i)) return i;
  }
  return -1;
}

// --- Gemini Integration ---

/**
 * Build the prompt for Gemini to generate a tweet.
 */
export function buildGeminiPrompt(reflection: ReflectionData): {
  system: string;
  user: string;
} {
  const system = `You are a tweet writer for a personal digital garden blog at bagrounds.org.
Your job is to write a single tweet promoting today's daily reflection blog post.

Rules:
- The first line MUST be the exact reflection title: "${reflection.title}"
- The second line should be blank
- The third line should have emoji-prefixed topic tags separated by " | " (e.g. "📚 Books | 🤖 AI | 🧠 Learning")
- Extract the topic tags from the content of the reflection (books being read, videos watched, topics explored)
- The last line should be the URL: ${reflection.url}
- Keep the total tweet under 280 characters (URLs count as 23 characters on Twitter)
- IMPORTANT: The entire post including the full URL must fit in 300 characters for Bluesky. Keep the topic tags line short — use 2–4 concise tags.
- Do NOT use hashtags (use emoji tags instead)
- Do NOT add any commentary, just the formatted tweet
- Match the style of these examples:

Example 1:
2026-02-05 | 👥 Many ⚔️ Will 🧠 Know 🌪️ Chaos 📚📺

📚 Book Series | 🌌 Sci-Fi Exploration | ⛈️ Leadership in Turmoil | 🤖 Artificial General Intelligence | 🌌 Speculative Futures
https://bagrounds.org/reflections/2026-02-05

Example 2:
2025-12-30 | 🕷️ Charlotte's 🍼 Little 🧸 Nursery 😈 Devils 📚🌌

🕸️ Animal Fables | 🐑 Children's Verse | 🧸 Rhyme Collections | 👿 Fictional Characters | 🖼️ Creative Expression
https://bagrounds.org/reflections/2025-12-30`;

  const user = `Write a tweet for this reflection:

Title: ${reflection.title}
URL: ${reflection.url}
Date: ${reflection.date}

Content:
${reflection.body.slice(0, 1500)}`;

  return { system, user };
}

/**
 * Generate tweet text using Google Gemini API.
 */
export async function generateTweetWithGemini(
  reflection: ReflectionData,
  apiKey: string,
  modelName: string = DEFAULT_GEMINI_MODEL,
): Promise<string> {
  const { GoogleGenerativeAI } = await import("@google/generative-ai");
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: modelName,
  });

  const prompt = buildGeminiPrompt(reflection);

  const result = await model.generateContent({
    contents: [
      {
        role: "user",
        parts: [{ text: `${prompt.system}\n\n${prompt.user}` }],
      },
    ],
  });

  const text = result.response.text().trim();

  // Validate length
  const { valid, length } = validateTweetLength(text);
  if (!valid) {
    throw new Error(
      `Generated tweet exceeds 280 characters (${length} effective chars). Tweet: ${text}`,
    );
  }

  return text;
}

// --- Retry Utility ---

/** HTTP status codes that indicate a transient server error worth retrying. */
const TRANSIENT_HTTP_CODES = new Set([429, 502, 503, 504]);

/**
 * Retry an async operation with exponential backoff for transient errors.
 * Only retries when the error has an HTTP `code` in TRANSIENT_HTTP_CODES.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  {
    maxRetries = 3,
    baseDelayMs = 1000,
    onRetry,
  }: {
    maxRetries?: number;
    baseDelayMs?: number;
    onRetry?: (error: unknown, attempt: number, delayMs: number) => void;
  } = {},
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err: unknown) {
      lastError = err;
      const code =
        typeof err === "object" && err !== null && "code" in err
          ? (err as { code: number }).code
          : undefined;

      if (attempt < maxRetries && code !== undefined && TRANSIENT_HTTP_CODES.has(code)) {
        const delayMs = baseDelayMs * 2 ** attempt;
        onRetry?.(err, attempt + 1, delayMs);
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      } else {
        throw err;
      }
    }
  }
  /* istanbul ignore next — unreachable, but satisfies TypeScript */
  throw lastError;
}

// --- Twitter Integration ---

/**
 * Log verbose details from a twitter-api-v2 error for diagnostics.
 */
function logTwitterError(label: string, err: unknown, verbose = false): void {
  const e = err as {
    code?: number;
    data?: unknown;
    headers?: Record<string, string>;
    rateLimit?: unknown;
    message?: string;
    stack?: string;
    type?: string;
  };
  // One-line summary (always shown)
  console.error(`  ⚠️ [${label}] ${e.code ?? "?"} ${e.message ?? "unknown error"}`);
  // Verbose details only on final failure
  if (!verbose) return;
  console.error(`🔍 Twitter API error details:`);
  console.error(`  HTTP status: ${e.code ?? "unknown"}, type: ${e.type ?? "unknown"}`);
  if (e.data) console.error(`  Response data: ${JSON.stringify(e.data, null, 2)}`);
  if (e.rateLimit) console.error(`  Rate limit: ${JSON.stringify(e.rateLimit, null, 2)}`);
  if (e.stack) {
    console.error(`  Stack trace:\n${e.stack.split("\n").slice(0, 4).join("\n")}`);
  }
}

/**
 * Post a tweet using the Twitter API v2.
 *
 * The X platform free tier frequently returns persistent 503 errors on
 * the v2 POST /2/tweets endpoint. To handle this safely:
 *
 * - An `X-Idempotency-Key` header is sent with every request, ensuring
 *   that retries after a 503 "ghost tweet" (tweet posted but 503 returned)
 *   won't create duplicates.
 * - Retries up to 5 times with exponential backoff (10s base, up to ~5 min
 *   total wait) to ride out transient outages.
 * - Non-server errors (auth, bad request) fail immediately.
 *
 * Note: The v1.1 `POST /1.1/statuses/update.json` endpoint is NOT available
 * on the free tier (returns 403 code 453).
 *
 * @see https://developer.x.com/en/docs/twitter-api/tweets/manage-tweets/api-reference/post-tweets
 * @see https://github.com/PLhery/node-twitter-api-v2/issues/499
 */
export async function postTweet(
  text: string,
  credentials: {
    apiKey: string;
    apiSecret: string;
    accessToken: string;
    accessSecret: string;
  },
): Promise<TweetResult> {
  const { TwitterApi } = await import("twitter-api-v2");
  const client = new TwitterApi({
    appKey: credentials.apiKey,
    appSecret: credentials.apiSecret,
    accessToken: credentials.accessToken,
    accessSecret: credentials.accessSecret,
  });

  // Generate a unique idempotency key for this tweet attempt.
  // If Twitter receives the same key twice (e.g. after a 503 "ghost tweet"),
  // it returns the original response instead of creating a duplicate.
  const idempotencyKey = randomUUID();
  console.log(`  📡 POST /2/tweets (idempotency key: ${idempotencyKey})`);

  const { data } = await withRetry(
    () =>
      client.v2.post("tweets", { text }, {
        headers: { "X-Idempotency-Key": idempotencyKey },
      }),
    {
      maxRetries: 3,
      baseDelayMs: 1_000,
      onRetry: (err, attempt, delayMs) => {
        const code = (err as { code?: number }).code;
        console.warn(
          `  ⚠️ Twitter API returned ${code}, retry ${attempt}/3 after ${delayMs / 1000}s...`,
        );
        logTwitterError(`retry ${attempt}`, err);
      },
    },
  );

  return {
    id: (data as { id: string }).id,
    text: (data as { text?: string }).text ?? text,
  };
}

/**
 * Delete a tweet (used for test cleanup).
 */
export async function deleteTweet(
  tweetId: string,
  credentials: {
    apiKey: string;
    apiSecret: string;
    accessToken: string;
    accessSecret: string;
  },
): Promise<void> {
  const { TwitterApi } = await import("twitter-api-v2");
  const client = new TwitterApi({
    appKey: credentials.apiKey,
    appSecret: credentials.apiSecret,
    accessToken: credentials.accessToken,
    accessSecret: credentials.accessSecret,
  });

  await client.v2.deleteTweet(tweetId);
}

// --- oEmbed Integration ---

/**
 * Fetch tweet embed HTML from Twitter's oEmbed API.
 */
export async function fetchOEmbed(
  tweetUrl: string,
  options: { theme?: string } = {},
): Promise<EmbedResult> {
  const theme = options.theme || "dark";
  const params = new URLSearchParams({
    url: tweetUrl,
    theme,
    omit_script: "false",
  });

  const response = await fetch(`https://publish.twitter.com/oembed?${params}`);

  if (!response.ok) {
    throw new Error(
      `oEmbed API returned ${response.status}: ${response.statusText}`,
    );
  }

  const data = (await response.json()) as { html: string };
  return { html: data.html };
}

/**
 * Generate embed HTML locally as a fallback when oEmbed is unavailable.
 */
export function generateLocalEmbed(
  tweetId: string,
  tweetText: string,
  date: string,
): string {
  // HTML-encode the tweet text
  const htmlText = tweetText
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/\n/g, "<br>");

  // Format the date for display
  const dateObj = new Date(date + "T00:00:00Z");
  const displayDate = `${MONTH_NAMES[dateObj.getUTCMonth()]} ${dateObj.getUTCDate()}, ${dateObj.getUTCFullYear()}`;

  return (
    `<blockquote class="twitter-tweet" data-theme="dark">` +
    `<p lang="en" dir="ltr">${htmlText}</p>` +
    `&mdash; ${TWITTER_DISPLAY_NAME} (@${TWITTER_HANDLE}) ` +
    `<a href="https://twitter.com/${TWITTER_HANDLE}/status/${tweetId}?ref_src=twsrc%5Etfw">${displayDate}</a>` +
    `</blockquote> ` +
    `<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>`
  );
}

/**
 * Get embed HTML, trying oEmbed first, then falling back to local generation.
 */
export async function getEmbedHtml(
  tweetId: string,
  tweetText: string,
  date: string,
): Promise<string> {
  const tweetUrl = `https://twitter.com/${TWITTER_HANDLE}/status/${tweetId}`;

  try {
    const { html } = await fetchOEmbed(tweetUrl, { theme: "dark" });
    return html;
  } catch (error) {
    console.warn(`oEmbed API failed, using local embed generation: ${error}`);
    return generateLocalEmbed(tweetId, tweetText, date);
  }
}

// --- OpenGraph Metadata ---

/**
 * Parsed OpenGraph metadata from a web page.
 */
export interface OgMetadata {
  title?: string;
  description?: string;
  imageUrl?: string;
}

/**
 * Fetch OpenGraph metadata from a URL by parsing <meta property="og:*"> tags.
 *
 * Used to get the real og:description and og:image for Bluesky link card embeds,
 * since Bluesky does NOT auto-fetch OpenGraph metadata.
 *
 * Returns whatever OG tags are found; fields may be undefined if not present.
 */
export async function fetchOgMetadata(url: string): Promise<OgMetadata> {
  try {
    const response = await fetch(url, {
      headers: { "User-Agent": "BlueskyBot/1.0 (OG metadata fetcher)" },
      signal: AbortSignal.timeout(10_000),
    });

    if (!response.ok) {
      console.warn(`  ⚠️ OG fetch: HTTP ${response.status} for ${url}`);
      return {};
    }

    const html = await response.text();
    const metadata: OgMetadata = {};

    // Helper to extract OG property values. Handles both attribute orders:
    //   <meta property="og:X" content="value">
    //   <meta content="value" property="og:X">
    const extractOg = (property: string): string | undefined => {
      const propFirst = html.match(
        new RegExp(`<meta\\s+property=["']${property}["']\\s+content=["']([^"']+)["']`, "i"),
      );
      if (propFirst) return propFirst[1];

      const contentFirst = html.match(
        new RegExp(`<meta\\s+content=["']([^"']+)["']\\s+property=["']${property}["']`, "i"),
      );
      if (contentFirst) return contentFirst[1];

      return undefined;
    };

    metadata.title = extractOg("og:title");
    metadata.description = extractOg("og:description");
    metadata.imageUrl = extractOg("og:image");

    return metadata;
  } catch (error) {
    console.warn(`  ⚠️ OG fetch failed for ${url}: ${error instanceof Error ? error.message : error}`);
    return {};
  }
}

/**
 * Fetch an image from a URL and return it as a Uint8Array with its MIME type.
 * Used to download OG images for uploading as Bluesky blobs.
 */
export async function fetchImageAsBuffer(
  imageUrl: string,
): Promise<{ data: Uint8Array; mimeType: string } | null> {
  try {
    const response = await fetch(imageUrl, {
      signal: AbortSignal.timeout(10_000),
    });

    if (!response.ok) {
      console.warn(`  ⚠️ Image fetch: HTTP ${response.status} for ${imageUrl}`);
      return null;
    }

    const contentType = response.headers.get("content-type") || "image/jpeg";
    const mimeType = (contentType.split(";")[0] || "image/jpeg").trim();
    const arrayBuffer = await response.arrayBuffer();
    return { data: new Uint8Array(arrayBuffer), mimeType };
  } catch (error) {
    console.warn(`  ⚠️ Image fetch failed: ${error instanceof Error ? error.message : error}`);
    return null;
  }
}

// --- Bluesky Integration ---

/**
 * Post to Bluesky using the AT Protocol API.
 *
 * Uses app password authentication (simpler than OAuth for single-user bots).
 * The `@atproto/api` package handles AT Protocol session management.
 *
 * When a link card (external embed) is provided, Bluesky renders a website
 * preview card below the post text — similar to what happens when you paste
 * a URL in the Bluesky app. Bluesky does NOT auto-fetch OpenGraph metadata;
 * the caller must supply the title, description, and URI explicitly.
 * If a thumbnail image URL is provided, the image is fetched, uploaded as a
 * blob to Bluesky, and attached to the link card for a richer preview.
 *
 * @see https://docs.bsky.app/docs/api/app/bsky/feed/post
 * @see https://docs.bsky.app/docs/advanced-guides/posts#website-card-embeds
 * @see https://atproto.com/guides/bot-tutorial
 */
export async function postToBluesky(
  text: string,
  credentials: {
    identifier: string;
    password: string;
  },
  linkCard?: {
    uri: string;
    title: string;
    description: string;
    thumbUrl?: string;
  },
): Promise<BlueskyPostResult> {
  const { AtpAgent } = await import("@atproto/api");
  const agent = new AtpAgent({ service: "https://bsky.social" });

  await agent.login({
    identifier: credentials.identifier,
    password: credentials.password,
  });

  console.log(`  📡 Bluesky: creating post...`);

  // Use RichText to detect facets (links, mentions) so URLs are clickable
  const { RichText } = await import("@atproto/api");
  const rt = new RichText({ text });
  await rt.detectFacets(agent);

  // Build the post record
  const postRecord: Record<string, unknown> = {
    text: rt.text,
    facets: rt.facets,
  };

  // Add external embed (website card) if provided
  if (linkCard) {
    const external: Record<string, unknown> = {
      uri: linkCard.uri,
      title: linkCard.title,
      description: linkCard.description,
    };

    // Upload thumbnail image if provided
    if (linkCard.thumbUrl) {
      console.log(`  🖼️ Bluesky: fetching thumbnail from ${linkCard.thumbUrl}`);
      const imageData = await fetchImageAsBuffer(linkCard.thumbUrl);
      if (imageData) {
        console.log(`  📤 Bluesky: uploading thumbnail (${imageData.data.length} bytes, ${imageData.mimeType})...`);
        const uploadResponse = await agent.uploadBlob(imageData.data, {
          encoding: imageData.mimeType,
        });
        external.thumb = uploadResponse.data.blob;
        console.log(`  ✅ Bluesky: thumbnail uploaded`);
      }
    }

    postRecord.embed = {
      $type: "app.bsky.embed.external",
      external,
    };
    console.log(`  🔗 Bluesky: attaching link card for ${linkCard.uri}`);
  }

  const response = await agent.post(postRecord);

  return {
    uri: response.uri,
    cid: response.cid,
    text,
  };
}

/**
 * Delete a Bluesky post (used for test cleanup).
 */
export async function deleteBlueskyPost(
  uri: string,
  credentials: {
    identifier: string;
    password: string;
  },
): Promise<void> {
  const { AtpAgent } = await import("@atproto/api");
  const agent = new AtpAgent({ service: "https://bsky.social" });

  await agent.login({
    identifier: credentials.identifier,
    password: credentials.password,
  });

  await agent.deletePost(uri);
}

/**
 * Extract the post ID (rkey) from a Bluesky AT URI.
 * e.g. "at://did:plc:abc123/app.bsky.feed.post/3ltxsqnjf6s2b" → "3ltxsqnjf6s2b"
 */
export function extractBlueskyPostId(uri: string): string {
  const parts = uri.split("/");
  return parts[parts.length - 1] as string;
}

/**
 * Extract the DID from a Bluesky AT URI.
 * e.g. "at://did:plc:abc123/app.bsky.feed.post/3ltxsqnjf6s2b" → "did:plc:abc123"
 */
export function extractBlueskyDid(uri: string): string {
  const match = uri.match(/at:\/\/(did:[^/]+)/);
  return match ? match[1] : "";
}

/**
 * Build a Bluesky post URL from a DID and post ID.
 */
export function buildBlueskyPostUrl(did: string, postId: string): string {
  return `https://bsky.app/profile/${did}/post/${postId}`;
}

/**
 * Fetch Bluesky post embed HTML from the oEmbed API.
 *
 * @see https://docs.bsky.app/docs/advanced-guides/oembed
 */
export async function fetchBlueskyOEmbed(postUrl: string): Promise<EmbedResult> {
  const params = new URLSearchParams({ url: postUrl, format: "json" });
  const response = await fetch(`https://embed.bsky.app/oembed?${params}`);

  if (!response.ok) {
    throw new Error(
      `Bluesky oEmbed API returned ${response.status}: ${response.statusText}`,
    );
  }

  const data = (await response.json()) as { html: string };
  return { html: data.html };
}

/**
 * Generate Bluesky embed HTML locally as a fallback when oEmbed is unavailable.
 * Matches the format used in existing Bluesky embeds in the content.
 */
export function generateLocalBlueskyEmbed(
  uri: string,
  postText: string,
  date: string,
  handle: string,
  cid?: string,
): string {
  const did = extractBlueskyDid(uri);
  const postId = extractBlueskyPostId(uri);
  const postUrl = buildBlueskyPostUrl(did, postId);

  // HTML-encode the post text
  const htmlText = postText
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/\n/g, "<br>");

  // Format the date for display
  const dateObj = new Date(date + "T00:00:00Z");
  const displayDate = `${MONTH_NAMES[dateObj.getUTCMonth()]} ${dateObj.getUTCDate()}, ${dateObj.getUTCFullYear()}`;

  const cidAttr = cid ? ` data-bluesky-cid="${cid}"` : "";

  return (
    `<blockquote class="bluesky-embed" data-bluesky-uri="${uri}"${cidAttr} data-bluesky-embed-color-mode="system">` +
    `<p lang="en">${htmlText}</p>` +
    `\n&mdash; ${BLUESKY_DISPLAY_NAME} ` +
    `(<a href="https://bsky.app/profile/${did}?ref_src=embed">@${handle}</a>) ` +
    `<a href="${postUrl}?ref_src=embed">${displayDate}</a>` +
    `</blockquote>` +
    `<script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>`
  );
}

/**
 * Get Bluesky embed HTML, trying oEmbed first (with retry for propagation delay),
 * then falling back to local generation.
 *
 * Freshly created posts may not be immediately available via oEmbed due to
 * read-after-write propagation delay in Bluesky's decentralized architecture.
 */
export async function getBlueskyEmbedHtml(
  uri: string,
  postText: string,
  date: string,
  handle: string,
  cid?: string,
): Promise<string> {
  const did = extractBlueskyDid(uri);
  const postId = extractBlueskyPostId(uri);
  const postUrl = buildBlueskyPostUrl(did, postId);

  const maxAttempts = 2;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      // Wait before oEmbed attempt to allow post propagation (skip if 0)
      const delayMs = attempt === 0
        ? BLUESKY_OEMBED_INITIAL_DELAY_MS
        : BLUESKY_OEMBED_RETRY_DELAY_MS;
      if (delayMs > 0) {
        console.log(`  ⏳ Waiting ${delayMs / 1000}s for Bluesky post propagation...`);
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }

      const { html } = await fetchBlueskyOEmbed(postUrl);
      return html;
    } catch (error) {
      const is404 = error instanceof Error && error.message.includes("404");
      if (is404 && attempt < maxAttempts - 1) {
        console.warn(`  ⚠️ Bluesky oEmbed returned 404 (propagation delay), retrying...`);
        continue;
      }
      console.warn(`Bluesky oEmbed API failed, using local embed generation: ${error}`);
      break;
    }
  }

  return generateLocalBlueskyEmbed(uri, postText, date, handle, cid);
}

// --- Mastodon Integration ---

/**
 * Post to Mastodon using the REST API.
 *
 * Uses a personal access token for authentication (simplest for single-user bots).
 * The `masto` package handles Mastodon API interactions.
 *
 * Mastodon supports the `Idempotency-Key` header to prevent duplicate posts
 * on retries. The default character limit is 500 (instance-configurable).
 *
 * @see https://docs.joinmastodon.org/methods/statuses/
 * @see https://github.com/neet/masto.js
 */
export async function postToMastodon(
  text: string,
  credentials: {
    instanceUrl: string;
    accessToken: string;
  },
): Promise<MastodonPostResult> {
  const { createRestAPIClient } = await import("masto");
  const client = createRestAPIClient({
    url: credentials.instanceUrl,
    accessToken: credentials.accessToken,
  });

  console.log(`  📡 Mastodon: creating post on ${credentials.instanceUrl}...`);

  const status = await client.v1.statuses.create({
    status: text,
    visibility: "public",
    language: "en",
  });

  return {
    id: status.id,
    url: status.url ?? `${credentials.instanceUrl}/@${status.account?.acct ?? "unknown"}/${status.id}`,
    text,
  };
}

/**
 * Delete a Mastodon post (used for test cleanup).
 */
export async function deleteMastodonPost(
  statusId: string,
  credentials: {
    instanceUrl: string;
    accessToken: string;
  },
): Promise<void> {
  const { createRestAPIClient } = await import("masto");
  const client = createRestAPIClient({
    url: credentials.instanceUrl,
    accessToken: credentials.accessToken,
  });

  await client.v1.statuses.$select(statusId).remove();
}

/**
 * Extract the Mastodon instance URL from a post URL.
 * e.g. "https://mastodon.social/@user/123456789" → "https://mastodon.social"
 */
export function extractMastodonInstanceUrl(postUrl: string): string {
  try {
    const url = new URL(postUrl);
    return `${url.protocol}//${url.host}`;
  } catch {
    return "";
  }
}

/**
 * Extract the status ID from a Mastodon post URL.
 * e.g. "https://mastodon.social/@user/123456789" → "123456789"
 */
export function extractMastodonStatusId(postUrl: string): string {
  const parts = postUrl.split("/");
  return parts[parts.length - 1] || "";
}

/**
 * Extract the username from a Mastodon post URL.
 * e.g. "https://mastodon.social/@user/123456789" → "user"
 */
export function extractMastodonUsername(postUrl: string): string {
  const match = postUrl.match(/@([^/]+)/);
  return match ? match[1] : "";
}

/**
 * Fetch Mastodon post embed HTML from the instance's oEmbed API.
 *
 * Each Mastodon instance hosts its own oEmbed endpoint at /api/oembed.
 *
 * @see https://docs.joinmastodon.org/methods/oembed/
 */
export async function fetchMastodonOEmbed(postUrl: string): Promise<EmbedResult> {
  const instanceUrl = extractMastodonInstanceUrl(postUrl);
  if (!instanceUrl) {
    throw new Error(`Could not extract instance URL from: ${postUrl}`);
  }

  const params = new URLSearchParams({ url: postUrl });
  const response = await fetch(`${instanceUrl}/api/oembed?${params}`);

  if (!response.ok) {
    throw new Error(
      `Mastodon oEmbed API returned ${response.status}: ${response.statusText}`,
    );
  }

  const data = (await response.json()) as { html: string };
  return { html: data.html };
}

/**
 * Generate Mastodon embed HTML locally as a fallback when oEmbed is unavailable.
 * Uses an iframe embed format consistent with Mastodon's standard embed output.
 */
export function generateLocalMastodonEmbed(
  postUrl: string,
  postText: string,
  date: string,
): string {
  const instanceUrl = extractMastodonInstanceUrl(postUrl);
  const statusId = extractMastodonStatusId(postUrl);
  const username = extractMastodonUsername(postUrl);

  // HTML-encode the post text
  const htmlText = postText
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/\n/g, "<br>");

  // Format the date for display
  const dateObj = new Date(date + "T00:00:00Z");
  const displayDate = `${MONTH_NAMES[dateObj.getUTCMonth()]} ${dateObj.getUTCDate()}, ${dateObj.getUTCFullYear()}`;

  return (
    `<iframe src="${postUrl}/embed" class="mastodon-embed" ` +
    `style="max-width: 100%; border: 0" width="400" allowfullscreen="allowfullscreen"></iframe>` +
    `<script src="${instanceUrl}/embed.js" async="async"></script>`
  );
}

/**
 * Get Mastodon embed HTML, trying oEmbed first, then falling back to local generation.
 *
 * Unlike Bluesky, Mastodon posts are generally available via oEmbed immediately
 * since the instance handles the request directly (no federation propagation delay
 * for same-instance requests).
 */
export async function getMastodonEmbedHtml(
  postUrl: string,
  postText: string,
  date: string,
): Promise<string> {
  try {
    const { html } = await fetchMastodonOEmbed(postUrl);
    return html;
  } catch (error) {
    console.warn(`Mastodon oEmbed API failed, using local embed generation: ${error}`);
    return generateLocalMastodonEmbed(postUrl, postText, date);
  }
}

// --- File Update Operations ---

/**
 * Build the tweet section content to append to a note.
 * Handles separator logic: ensures a blank line before the section.
 */
export function buildTweetSection(
  existingContent: string,
  embedHtml: string,
): string {
  const separator = existingContent.endsWith("\n") ? "\n" : "\n\n";
  return `${separator}${TWEET_SECTION_HEADER}  \n${embedHtml}`;
}

/**
 * Append the tweet section to a local reflection file (used in tests).
 */
export function appendTweetSection(filePath: string, embedHtml: string): void {
  const content = fs.readFileSync(filePath, "utf-8");

  if (content.includes(TWEET_SECTION_HEADER)) {
    console.log("Tweet section already exists, skipping update");
    return;
  }

  fs.writeFileSync(filePath, content + buildTweetSection(content, embedHtml), "utf-8");
}

/**
 * Build the Bluesky section content to append to a note.
 * Handles separator logic: ensures a blank line before the section.
 */
export function buildBlueskySection(
  existingContent: string,
  embedHtml: string,
): string {
  const separator = existingContent.endsWith("\n") ? "\n" : "\n\n";
  return `${separator}${BLUESKY_SECTION_HEADER}  \n${embedHtml}`;
}

/**
 * Append the Bluesky section to a local reflection file (used in tests).
 */
export function appendBlueskySection(filePath: string, embedHtml: string): void {
  const content = fs.readFileSync(filePath, "utf-8");

  if (content.includes(BLUESKY_SECTION_HEADER)) {
    console.log("Bluesky section already exists, skipping update");
    return;
  }

  fs.writeFileSync(filePath, content + buildBlueskySection(content, embedHtml), "utf-8");
}

/**
 * Build the Mastodon section content to append to a note.
 * Handles separator logic: ensures a blank line before the section.
 */
export function buildMastodonSection(
  existingContent: string,
  embedHtml: string,
): string {
  const separator = existingContent.endsWith("\n") ? "\n" : "\n\n";
  return `${separator}${MASTODON_SECTION_HEADER}  \n${embedHtml}`;
}

/**
 * Append the Mastodon section to a local reflection file (used in tests).
 */
export function appendMastodonSection(filePath: string, embedHtml: string): void {
  const content = fs.readFileSync(filePath, "utf-8");

  if (content.includes(MASTODON_SECTION_HEADER)) {
    console.log("Mastodon section already exists, skipping update");
    return;
  }

  fs.writeFileSync(filePath, content + buildMastodonSection(content, embedHtml), "utf-8");
}

// --- Obsidian Headless Sync Integration ---

/**
 * Run the `ob` CLI command with arguments.
 * Uses OBSIDIAN_AUTH_TOKEN for non-interactive authentication.
 *
 * @see https://help.obsidian.md/sync/headless
 * @see https://github.com/obsidianmd/obsidian-headless
 */
export async function runObCommand(
  args: string[],
  options: { cwd?: string; env?: Record<string, string> } = {},
): Promise<{ stdout: string; stderr: string }> {
  const env = { ...process.env, ...options.env };
  try {
    const { stdout, stderr } = await execFileAsync("ob", args, {
      cwd: options.cwd,
      env,
    });
    return { stdout, stderr };
  } catch (error) {
    const err = error as Error & { stdout?: string; stderr?: string };
    throw new Error(
      [
        `Command: ob ${args.join(" ")}`,
        `Error: ${err.message}`,
        err.stdout ? `Stdout: ${err.stdout}` : null,
        err.stderr ? `Stderr: ${err.stderr}` : null,
      ]
        .filter(Boolean)
        .join("\n"),
    );
  }
}

/**
 * Set up and sync an Obsidian vault to a local directory using Headless Sync.
 * Pulls the latest vault content from Obsidian Sync.
 *
 * When `OBSIDIAN_VAULT_CACHE_DIR` is set, re-uses an existing vault directory
 * for incremental sync (only downloads changes since last cache). This can
 * reduce pull time from ~7 minutes (cold) to seconds (warm cache).
 *
 * @returns The local vault path where files were synced
 */
export async function syncObsidianVault(credentials: {
  authToken: string;
  vaultName: string;
  vaultPassword?: string;
}): Promise<string> {
  const cacheDir = process.env.OBSIDIAN_VAULT_CACHE_DIR;
  const vaultDir = cacheDir || path.join(
    process.env.RUNNER_TEMP || "/tmp",
    `obsidian-vault-${process.pid}-${Date.now()}`,
  );

  const isWarmCache = cacheDir && fs.existsSync(path.join(vaultDir, ".obsidian"));
  fs.mkdirSync(vaultDir, { recursive: true });

  if (isWarmCache) {
    console.log(`♻️  Re-using cached vault at ${vaultDir} (incremental sync)`);
  }

  const env: Record<string, string> = {
    OBSIDIAN_AUTH_TOKEN: credentials.authToken,
  };

  // ── Pre-sync cleanup ──────────────────────────────────────────────
  // Kill any lingering processes and remove stale lock.
  // @see https://github.com/obsidianmd/obsidian-headless/issues/4
  await ensureSyncClean(vaultDir);

  // ── Warm cache fast path ──────────────────────────────────────────
  // For warm caches (vault already configured from a previous run), try
  // `ob sync` directly WITHOUT running `sync-setup` first. This avoids
  // the lock contention that occurs when `sync-setup` is called on an
  // already-configured vault: `sync-setup` may leave filesystem state
  // (config writes, directory mtime updates) that causes the subsequent
  // `ob sync` lock acquisition to fail its verify() step.
  //
  // ## 5 Whys — Obsidian sync lock failure (4th investigation, 2026-03-09)
  //
  // 1. Why does "Another sync instance" occur immediately after sync-setup?
  //    `ob sync` creates `.sync.lock` dir, then verify() fails, throwing
  //    the lock error. The lock dir is NOT released on acquire() failure.
  //
  // 2. Why does verify() fail?
  //    The lock class sets mtime via utimesSync, reads it back via statSync.
  //    On warm cache vaults, the mtime round-trip may lose precision due to
  //    filesystem state from the cache restoration (tar extraction).
  //
  // 3. Why do retries keep failing after removing the lock?
  //    Each `ob sync` attempt creates a fresh lock dir, fails verify(),
  //    and exits without releasing the lock. The retry removes it, but the
  //    next attempt recreates it and fails the same way.
  //
  // 4. Why didn't process-killing help?
  //    There IS no lingering process — `sync-setup` doesn't spawn daemons.
  //    The issue is entirely in `ob sync`'s own lock acquisition failing.
  //
  // 5. What is the root fix?
  //    Skip `sync-setup` for warm caches. The vault config persists in the
  //    cache, so `ob sync` can run directly. Only fall back to `sync-setup`
  //    if `ob sync` reports missing configuration.

  if (isWarmCache) {
    console.log(`📥 Pulling latest vault content (warm cache fast path)...`);
    try {
      await runObSyncWithRetry(["sync", "--path", vaultDir], { env }, vaultDir);
      return vaultDir;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      // Exit code 3 = "No sync configuration found" → needs sync-setup
      // Exit code 2 = "Encryption key not found" → needs sync-setup
      if (msg.includes("No sync configuration") || msg.includes("Encryption key not found") || msg.includes("Run") && msg.includes("sync-setup")) {
        console.log(`⚠️  Warm cache missing config, falling back to sync-setup...`);
        await ensureSyncClean(vaultDir);
      } else {
        throw error;
      }
    }
  }

  // ── Cold cache / fallback: full sync-setup + sync ─────────────────
  const setupArgs = [
    "sync-setup",
    "--vault",
    credentials.vaultName,
    "--path",
    vaultDir,
  ];
  if (credentials.vaultPassword) {
    setupArgs.push("--password", credentials.vaultPassword);
  }

  console.log(`🔧 Setting up Obsidian Sync for vault: ${credentials.vaultName}`);
  await runObCommand(setupArgs, { env });

  // Remove any lock that sync-setup's config writes may have indirectly
  // triggered (e.g., by updating .obsidian directory mtime). We only
  // remove the lock file — we do NOT kill processes, since sync-setup
  // does not spawn daemons.
  removeSyncLock(vaultDir);

  console.log(`📥 Pulling latest vault content...`);
  await runObSyncWithRetry(["sync", "--path", vaultDir], { env }, vaultDir);

  return vaultDir;
}

/**
 * Run an `ob sync` command with retry logic for lock contention.
 * Retries up to 5 times with exponential backoff (2s, 4s, 8s, 16s, 32s) when
 * "Another sync instance is already running" is detected.
 * Each retry cleans up lingering processes and removes the lock file.
 *
 * The generous retry budget accounts for the intermittent nature of the
 * lock contention: `ob` child processes may take variable time to fully
 * release the lock after termination, especially under CI load.
 */
export async function runObSyncWithRetry(
  args: string[],
  options: { env?: Record<string, string> },
  vaultDir: string,
  maxRetries = 5,
): Promise<void> {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      await runObCommand(args, options);
      return;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      if (msg.includes("Another sync instance") && attempt < maxRetries) {
        const delayMs = 2000 * 2 ** attempt; // 2s, 4s, 8s, 16s, 32s
        console.warn(
          `  ⚠️ Sync lock contention (retry ${attempt + 1}/${maxRetries}), ` +
          `cleaning up and retrying in ${delayMs / 1000}s...`,
        );
        // Diagnostic: log lock state and running processes for debugging
        await logSyncDiagnostics(vaultDir);
        await ensureSyncClean(vaultDir);
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      } else {
        throw error;
      }
    }
  }
}

/**
 * Log diagnostic information about the sync lock state and running processes.
 * This helps debug intermittent lock contention issues in CI.
 */
export async function logSyncDiagnostics(vaultDir: string): Promise<void> {
  const lockPath = path.join(vaultDir, ".obsidian", ".sync.lock");
  try {
    if (fs.existsSync(lockPath)) {
      const stat = fs.statSync(lockPath);
      const lockAgeMs = Date.now() - stat.mtimeMs;
      console.log(
        `  🔍 Lock exists: mtime=${stat.mtimeMs.toFixed(3)}, age=${lockAgeMs}ms, ` +
        `isDir=${stat.isDirectory()}`,
      );
    } else {
      console.log(`  🔍 Lock does not exist at ${lockPath}`);
    }
  } catch (err) {
    console.log(`  🔍 Lock stat error: ${(err as Error).message}`);
  }

  // Log any processes related to obsidian or the vault
  try {
    const { stdout } = await execAsync(
      `ps -u $(id -u) -o pid,args 2>/dev/null | grep -iE 'obsidian|ob |${vaultDir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}' | grep -v grep || true`,
    );
    if (stdout.trim()) {
      console.log(`  🔍 Related processes:\n${stdout.trim().split("\n").map(line => `    ${line.trim()}`).join("\n")}`);
    } else {
      console.log(`  🔍 No related processes found`);
    }
  } catch {
    // ps/grep may fail — not critical
  }
}

/**
 * Remove the .sync.lock directory from an Obsidian vault.
 * The `ob sync` command creates this lock to prevent concurrent syncs.
 * If a previous sync completed or was interrupted, the stale lock blocks
 * subsequent syncs. Removing it between operations prevents the
 * "Another sync instance is already running" error.
 *
 * @see https://github.com/obsidianmd/obsidian-headless/issues/4
 */
export function removeSyncLock(vaultDir: string): void {
  const lockPath = path.join(vaultDir, ".obsidian", ".sync.lock");
  if (fs.existsSync(lockPath)) {
    console.log(`🔓 Removing stale .sync.lock from vault`);
    fs.rmSync(lockPath, { recursive: true, force: true });
  }
}

/**
 * Kill any lingering `ob` (obsidian-headless) processes that may be holding
 * the sync lock.
 *
 * The `ob sync-setup` and `ob sync` commands can leave orphan child processes
 * that hold the `.sync.lock` even after the parent process exits. Removing the
 * lock file alone doesn't help because the running process recreates it or
 * detects the running instance via other means (e.g. PID file, socket).
 *
 * This function finds all obsidian-headless processes and sends SIGTERM to
 * each, waits for them to exit, then escalates to SIGKILL if needed.
 *
 * ## 5 Whys — Obsidian sync lock failure (2nd investigation, 2026-03-08)
 *
 * 1. **Why does "Another sync instance is already running" persist even
 *    after `ensureSyncClean` (kill + remove lock)?**
 *    Because `killObProcesses` silently found zero processes to kill.
 *    The lingering `ob` process was invisible to the grep pattern.
 *
 * 2. **Why did `killObProcesses` find zero processes?**
 *    It used `ps -o pid,comm | grep '[o]b$'` which matches the COMMAND
 *    column (short process name). But `ob` is a Node.js script
 *    (`#!/usr/bin/env node`), so the process name in `comm` is `node`
 *    (or `MainThread` on some Linux kernels), NOT `ob`.
 *
 * 3. **Why does the process appear as `node` instead of `ob`?**
 *    obsidian-headless is installed via npm as a global package. The `ob`
 *    binary is a symlink to `cli.js` with a `#!/usr/bin/env node` shebang.
 *    The OS kernel runs `node /path/to/cli.js`, so `ps -o comm` reports
 *    `node` (the interpreter), not `ob` (the script name).
 *
 * 4. **Why doesn't `node` match the grep pattern `[o]b$`?**
 *    `[o]b$` matches strings ending with "ob". "node" doesn't end with
 *    "ob". The pattern was designed assuming `ob` would appear as the
 *    command name, which is only true for compiled binaries.
 *
 * 5. **What is the root fix?**
 *    Use `ps -o pid,args` (full command line) instead of `ps -o pid,comm`
 *    (short name). The `args` column contains the full invocation path,
 *    e.g. `node /path/to/obsidian-headless/cli.js sync ...`, which we
 *    can match on `obsidian-headless`. Also escalate to SIGKILL if
 *    SIGTERM doesn't terminate the process within 1 second.
 *
 * ## 5 Whys — Obsidian sync lock failure (3rd investigation, 2026-03-09)
 *
 * 1. **Why does the error still occur intermittently despite the 2nd fix?**
 *    When auto-post processes multiple posts, each `main()` call runs
 *    `sync-setup` → `sync` (pull) → post → `sync` (push). The push
 *    from post N may leave a daemon/lock, and post N+1 starts immediately.
 *
 * 2. **Why doesn't `ensureSyncClean` between sync-setup and sync help?**
 *    Because it was placed AFTER `sync-setup`, which spawns a daemon that
 *    `sync` needs. Killing that daemon (or disturbing its lock state)
 *    between setup and sync creates the very error we're trying to prevent.
 *
 * 3. **Why is it intermittent (works sometimes, fails other times)?**
 *    Race condition: timing determines whether the daemon has fully
 *    started when cleanup runs. Under CI load, timing varies per run.
 *
 * 4. **Why didn't broader process detection solve it?**
 *    The daemon may use a process name that doesn't match `obsidian-headless`
 *    (e.g., `MainThread`, bare `node`, or a detached worker).
 *
 * 5. **What is the root fix?**
 *    (a) Move cleanup to BEFORE sync-setup (not after) so the daemon
 *        sync-setup creates is preserved for sync to use.
 *    (b) Add post-push cleanup with settling delay so the next post
 *        starts with clean vault state.
 *    (c) Broaden process detection to also match vault paths.
 *    (d) Increase retry budget (5 retries, 2–32s backoff) for resilience.
 *
 * ## 5 Whys — Obsidian sync lock failure (4th investigation, 2026-03-09)
 *
 * 1. **Why does "Another sync instance" occur immediately after sync-setup
 *    even though sync-setup doesn't create the lock?**
 *    Analysis of the obsidian-headless source revealed: sync-setup does NOT
 *    create locks or spawn daemons. It only writes config files. The lock
 *    error comes from `ob sync`'s OWN `acquire()` method failing internally.
 *
 * 2. **Why does `ob sync`'s acquire() fail on a freshly created lock?**
 *    The lock class creates a `.sync.lock` directory, sets its mtime via
 *    `utimesSync`, reads it back with `statSync`, and compares. If the
 *    round-trip mtime doesn't match (`verify()` fails), it throws the
 *    lock error. The lock directory is NOT cleaned up when acquire fails.
 *
 * 3. **Why does the mtime round-trip fail?**
 *    On warm cache vaults restored from GitHub Actions cache (tar extraction),
 *    filesystem metadata state may affect `utimesSync` → `statSync` precision.
 *    The 5-second staleness window in the lock class also means any lock
 *    created in the last 5 seconds blocks a new sync, even from the same process.
 *
 * 4. **Why do retries keep failing after removing the lock?**
 *    Each `ob sync` attempt creates a fresh lock dir, fails verify(), and
 *    exits without releasing it (release is only in the inner try-finally,
 *    but acquire failure is caught by the outer catch). The retry removes
 *    it, but the next attempt recreates it and fails the same way.
 *
 * 5. **What is the root fix?**
 *    (a) Skip `sync-setup` for warm caches — the config persists in cache,
 *        so `ob sync` can run directly without setup.
 *    (b) Remove lock after sync-setup when full setup is needed.
 *    (c) Add diagnostic logging (lock state, processes) for debugging.
 *    (d) Verify lock removal in ensureSyncClean.
 *
 * @see https://github.com/obsidianmd/obsidian-headless/issues/4
 * @see https://help.obsidian.md/sync/headless
 */
export async function killObProcesses(vaultDir?: string): Promise<void> {
  try {
    // Find obsidian-headless processes owned by the current user.
    // Uses `ps -o pid,args` to get the FULL command line (not just the short
    // command name). This correctly identifies `ob` processes even though they
    // run as `node /path/to/obsidian-headless/cli.js ...`.
    //
    // We match multiple patterns to catch different process incarnations:
    //   - `obsidian-headless`: the npm package name in the script path
    //   - vault path: any process operating on our specific vault directory
    // This handles cases where daemon children use unexpected process names.
    const patterns = ["obsidian-headless"];
    if (vaultDir) {
      // Escape all regex-special characters for grep -E
      patterns.push(vaultDir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
    }
    const grepPattern = patterns.join("|");
    const { stdout } = await execAsync(
      `ps -u $(id -u) -o pid,args | grep -E '${grepPattern}' | grep -v grep | grep -v $$ | awk '{print $1}'`,
    );
    const pids = stdout.trim().split("\n").filter(Boolean).filter(
      // Exclude our own process
      (pid) => parseInt(pid, 10) !== process.pid,
    );
    if (pids.length === 0) return;

    console.log(`🔪 Killing ${pids.length} lingering ob process(es): ${pids.join(", ")}`);

    // Phase 1: SIGTERM — graceful shutdown
    for (const pid of pids) {
      try {
        process.kill(parseInt(pid, 10), "SIGTERM");
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code !== "ESRCH") {
          console.warn(`  ⚠️ Could not SIGTERM PID ${pid}: ${(err as Error).message}`);
        }
      }
    }

    // Wait up to 2s for graceful termination, checking every 200ms
    for (let i = 0; i < 10; i++) {
      await new Promise((resolve) => setTimeout(resolve, 200));
      const allDead = pids.every((pid) => {
        try {
          process.kill(parseInt(pid, 10), 0); // signal 0 = test if alive
          return false; // still alive
        } catch {
          return true; // dead
        }
      });
      if (allDead) return;
    }

    // Phase 2: SIGKILL — force kill any survivors
    for (const pid of pids) {
      try {
        process.kill(parseInt(pid, 10), 0); // test if still alive
        console.warn(`  ⚠️ PID ${pid} survived SIGTERM, sending SIGKILL`);
        process.kill(parseInt(pid, 10), "SIGKILL");
      } catch {
        // already dead — good
      }
    }
    // Brief wait for SIGKILL to take effect
    await new Promise((resolve) => setTimeout(resolve, 500));
  } catch {
    // ps/grep may fail if no processes found — that's fine
  }
}

/**
 * Ensure no sync lock or lingering process blocks the next `ob sync`.
 * Combines lock file removal with process cleanup for maximum reliability.
 * Verifies the lock is actually gone after removal.
 */
export async function ensureSyncClean(vaultDir: string): Promise<void> {
  await killObProcesses(vaultDir);
  removeSyncLock(vaultDir);

  // Verify lock is actually gone — belt and suspenders.
  // A running process could recreate it between removal and verification.
  const lockPath = path.join(vaultDir, ".obsidian", ".sync.lock");
  if (fs.existsSync(lockPath)) {
    console.warn(`  ⚠️ Lock still exists after cleanup, removing again`);
    fs.rmSync(lockPath, { recursive: true, force: true });
  }
}

/**
 * Push local changes back to the Obsidian vault via Headless Sync.
 * Includes post-push cleanup to prevent lock contention for subsequent syncs.
 */
export async function pushObsidianVault(
  vaultDir: string,
  credentials: { authToken: string },
): Promise<void> {
  const env: Record<string, string> = {
    OBSIDIAN_AUTH_TOKEN: credentials.authToken,
  };

  // Kill lingering processes and remove stale lock left by pull
  await ensureSyncClean(vaultDir);

  console.log(`📤 Pushing changes to Obsidian Sync...`);
  await runObSyncWithRetry(["sync", "--path", vaultDir], { env }, vaultDir);

  // Post-push cleanup: the `ob sync` push may leave daemon processes that
  // hold the lock. Clean up immediately so the next pipeline iteration
  // (if auto-post is processing multiple items) starts with a clean slate.
  // The settling delay gives child processes time to fully exit.
  await new Promise((resolve) => setTimeout(resolve, 1000));
  await ensureSyncClean(vaultDir);
}

/**
 * Update a note in the Obsidian vault via Headless Sync.
 * Pulls vault → modifies file → pushes back.
 *
 * Appends one or more embed sections (tweet, Bluesky) if they don't already exist.
 */
export async function appendEmbedsToObsidianNote(
  notePath: string,
  sections: EmbedSection[],
  credentials: {
    authToken: string;
    vaultName: string;
    vaultPassword?: string;
  },
): Promise<void> {
  // Pull vault
  const vaultDir = await syncObsidianVault(credentials);

  // Read note from synced vault
  const filePath = path.join(vaultDir, notePath);
  if (!fs.existsSync(filePath)) {
    throw new Error(
      `Note not found in Obsidian vault: ${notePath} (looked at ${filePath})`,
    );
  }

  let content = fs.readFileSync(filePath, "utf-8");
  let modified = false;

  for (const section of sections) {
    if (!content.includes(section.header)) {
      content = content + section.buildSection(content, section.embedHtml);
      modified = true;
    } else {
      console.log(`${section.header} already exists in Obsidian note, skipping`);
    }
  }

  if (!modified) {
    console.log("No new sections to add to Obsidian note");
    return;
  }

  // Write updated content
  fs.writeFileSync(filePath, content, "utf-8");

  // Push changes back
  await pushObsidianVault(vaultDir, {
    authToken: credentials.authToken,
  });
}

// --- Main Pipeline ---

/**
 * Get yesterday's date in YYYY-MM-DD format (UTC).
 * We post the previous day's reflection to ensure the note is finalized.
 */
export function getYesterdayDate(): string {
  const now = new Date();
  now.setUTCDate(now.getUTCDate() - 1);
  return now.toISOString().split("T")[0] as string;
}

/**
 * Parse command line arguments.
 */
function parseArgs(): { date: string; note?: string } {
  const args = process.argv.slice(2);
  let date = getYesterdayDate();
  let note: string | undefined;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--date" && args[i + 1]) {
      date = args[i + 1] as string;
      i++;
    } else if (args[i] === "--note" && args[i + 1]) {
      note = args[i + 1] as string;
      i++;
    }
  }

  return { date, note };
}

/**
 * Check if a platform is explicitly disabled via an environment variable.
 * Accepted truthy values: "true", "1", "yes" (case-insensitive).
 */
export function isPlatformDisabled(envVar: string): boolean {
  const value = process.env[envVar]?.toLowerCase()?.trim();
  return value === "true" || value === "1" || value === "yes";
}

/**
 * Validate that all required environment variables are set.
 * Twitter, Bluesky, and Mastodon credentials are optional — the script will attempt
 * each platform only if its credentials are present and the platform is not disabled.
 *
 * Platforms can be explicitly disabled via environment variables:
 * - DISABLE_TWITTER=true  — skip Twitter even if credentials are set
 * - DISABLE_BLUESKY=true  — skip Bluesky even if credentials are set
 * - DISABLE_MASTODON=true — skip Mastodon even if credentials are set
 */
export function validateEnvironment(): {
  twitter: {
    apiKey: string;
    apiSecret: string;
    accessToken: string;
    accessSecret: string;
  } | null;
  bluesky: {
    identifier: string;
    password: string;
  } | null;
  mastodon: {
    instanceUrl: string;
    accessToken: string;
  } | null;
  gemini: { apiKey: string; model: string };
  obsidian: {
    authToken: string;
    vaultName: string;
    vaultPassword?: string;
  };
} {
  const required = [
    "GEMINI_API_KEY",
    "OBSIDIAN_AUTH_TOKEN",
    "OBSIDIAN_VAULT_NAME",
  ];

  const missing = required.filter((key) => !process.env[key]);
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(", ")}`,
    );
  }

  // Twitter credentials are optional — all 4 must be present to enable
  // Can be explicitly disabled via DISABLE_TWITTER env var
  const twitterKeys = [
    "TWITTER_API_KEY",
    "TWITTER_API_SECRET",
    "TWITTER_ACCESS_TOKEN",
    "TWITTER_ACCESS_SECRET",
  ];
  const twitterDisabled = isPlatformDisabled("DISABLE_TWITTER");
  const hasTwitter = !twitterDisabled && twitterKeys.every((key) => process.env[key]);
  const twitter = hasTwitter
    ? {
        apiKey: process.env.TWITTER_API_KEY as string,
        apiSecret: process.env.TWITTER_API_SECRET as string,
        accessToken: process.env.TWITTER_ACCESS_TOKEN as string,
        accessSecret: process.env.TWITTER_ACCESS_SECRET as string,
      }
    : null;
  if (twitterDisabled) {
    console.log(`🚫 Twitter disabled via DISABLE_TWITTER env var`);
  }

  // Bluesky credentials are optional — both must be present to enable
  // Can be explicitly disabled via DISABLE_BLUESKY env var
  const blueskyDisabled = isPlatformDisabled("DISABLE_BLUESKY");
  const hasBluesky =
    !blueskyDisabled && !!process.env.BLUESKY_IDENTIFIER && !!process.env.BLUESKY_APP_PASSWORD;
  const bluesky = hasBluesky
    ? {
        identifier: process.env.BLUESKY_IDENTIFIER as string,
        password: process.env.BLUESKY_APP_PASSWORD as string,
      }
    : null;
  if (blueskyDisabled) {
    console.log(`🚫 Bluesky disabled via DISABLE_BLUESKY env var`);
  }

  // Mastodon credentials are optional — both must be present to enable
  // Can be explicitly disabled via DISABLE_MASTODON env var
  const mastodonDisabled = isPlatformDisabled("DISABLE_MASTODON");
  const hasMastodon =
    !mastodonDisabled && !!process.env.MASTODON_INSTANCE_URL && !!process.env.MASTODON_ACCESS_TOKEN;
  const mastodon = hasMastodon
    ? {
        instanceUrl: process.env.MASTODON_INSTANCE_URL as string,
        accessToken: process.env.MASTODON_ACCESS_TOKEN as string,
      }
    : null;
  if (mastodonDisabled) {
    console.log(`🚫 Mastodon disabled via DISABLE_MASTODON env var`);
  }

  return {
    twitter,
    bluesky,
    mastodon,
    gemini: {
      apiKey: process.env.GEMINI_API_KEY as string,
      model: process.env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL,
    },
    obsidian: {
      authToken: process.env.OBSIDIAN_AUTH_TOKEN as string,
      vaultName: process.env.OBSIDIAN_VAULT_NAME as string,
      vaultPassword: process.env.OBSIDIAN_VAULT_PASSWORD || undefined,
    },
  };
}

/**
 * Main entry point for the social posting pipeline.
 *
 * Posts to Twitter, Bluesky, and Mastodon (if credentials are configured).
 * Platform failures are logged but don't crash the pipeline.
 * The pipeline continues as long as at least one platform succeeds.
 *
 * ## Source of Truth: Obsidian Vault
 *
 * All note content is read from the Obsidian vault (the authoritative source),
 * not from the GitHub repo's content/ directory. The repo content is stale —
 * it only updates when the user manually publishes from Obsidian. Reading from
 * the vault ensures we always see the latest social media embed sections,
 * preventing duplicate posts across pipeline runs.
 *
 * If a `vaultDir` is provided (pre-pulled by auto-post.ts), it is reused
 * instead of pulling the vault again.
 *
 * Timeline:
 *   pull(~7min) → read note → generate(3s) → post(10s) → push(1.5s)
 */
export async function main(options?: {
  date?: string;
  note?: string;
  vaultDir?: string;
}): Promise<void> {
  const timer = new PipelineTimer();
  const date = options?.date || getYesterdayDate();
  const notePath = options?.note;
  const obsidianNotePath = notePath || `reflections/${date}.md`;

  console.log(`📄 Processing: ${obsidianNotePath}`);

  // Step 1: Validate credentials
  const env = validateEnvironment();

  if (!env.twitter && !env.bluesky && !env.mastodon) {
    console.warn(`⚠️  No social platform credentials configured. Set TWITTER_*, BLUESKY_*, or MASTODON_* env vars.`);
  }

  // Step 2: Get the Obsidian vault — the single source of truth.
  // If a pre-pulled vault dir is provided (e.g. from auto-post.ts),
  // reuse it to avoid a redundant pull. Otherwise, pull fresh.
  let vaultDir = options?.vaultDir || null;
  if (!vaultDir) {
    console.log(`📥 Pulling Obsidian vault (source of truth)...`);
    vaultDir = await timer.time("obsidian-pull", () =>
      syncObsidianVault(env.obsidian),
    );
  }

  // Step 3: Read the note from the vault
  const reflection = readNote(obsidianNotePath, vaultDir);
  if (!reflection) {
    console.log(`ℹ️  Note not found in Obsidian vault: ${obsidianNotePath}, exiting`);
    return;
  }

  console.log(`📄 Found: ${reflection.title}`);

  // Check idempotency — skip if all sections already exist
  if (reflection.hasTweetSection && reflection.hasBlueskySection && reflection.hasMastodonSection) {
    console.log(`ℹ️  Note already has all social platform sections, skipping`);
    return;
  }
  console.log(`🔍 Section check — tweet: ${reflection.hasTweetSection}, bluesky: ${reflection.hasBlueskySection}, mastodon: ${reflection.hasMastodonSection}`);

  // Step 4: Generate post text with Gemini
  const postText = await timer.time("gemini-generate", async () => {
    console.log(`🤖 Generating post with ${env.gemini.model}...`);
    const text = await generateTweetWithGemini(
      reflection,
      env.gemini.apiKey,
      env.gemini.model,
    );
    console.log(
      `📝 Generated post (${calculateTweetLength(text)} chars):\n${text}`,
    );
    return text;
  });

  // Collect embed sections to write to Obsidian
  const embedSections: EmbedSection[] = [];

  // Step 5: Post to social platforms in parallel (both non-fatal)
  await timer.time("social-posting", async () => {
    const postingTasks: Array<Promise<EmbedSection | null>> = [];

    // Twitter posting task
    if (env.twitter && !reflection.hasTweetSection) {
      postingTasks.push(
        (async (): Promise<EmbedSection | null> => {
          try {
            console.log(`🐦 Posting tweet to Twitter...`);
            const tweet = await postTweet(postText, env.twitter!);
            console.log(
              `✅ Tweet posted: https://twitter.com/${TWITTER_HANDLE}/status/${tweet.id}`,
            );

            console.log(`🔗 Fetching tweet embed code...`);
            const tweetEmbedHtml = await getEmbedHtml(tweet.id, tweet.text, date);
            console.log(`📋 Got tweet embed HTML (${tweetEmbedHtml.length} chars)`);

            return {
              header: TWEET_SECTION_HEADER,
              embedHtml: tweetEmbedHtml,
              buildSection: buildTweetSection,
            };
          } catch (error) {
            console.error(`⚠️  Twitter posting failed (non-fatal)`);
            logTwitterError("final", error, true);
            return null;
          }
        })(),
      );
    } else if (!env.twitter) {
      console.log(`ℹ️  Twitter credentials not configured, skipping`);
    }

    // Bluesky posting task
    if (env.bluesky && !reflection.hasBlueskySection) {
      postingTasks.push(
        (async (): Promise<EmbedSection | null> => {
          try {
            console.log(`🦋 Posting to Bluesky...`);

            // Fetch OG metadata from the reflection URL for a richer link card.
            // Bluesky does NOT auto-fetch OpenGraph metadata; we must supply it explicitly.
            // @see https://docs.bsky.app/docs/advanced-guides/posts#website-card-embeds
            console.log(`  🔍 Fetching OG metadata from ${reflection.url}...`);
            const ogMeta = await fetchOgMetadata(reflection.url);

            const linkCard = {
              uri: reflection.url,
              title: ogMeta.title || reflection.title,
              description: ogMeta.description || `Daily reflection from bagrounds.org — ${reflection.date}`,
              thumbUrl: ogMeta.imageUrl,
            };

            if (ogMeta.description) {
              console.log(`  📋 OG description: ${ogMeta.description.slice(0, 80)}...`);
            }
            if (ogMeta.imageUrl) {
              console.log(`  🖼️ OG image found: ${ogMeta.imageUrl}`);
            }

            // Enforce Bluesky's 300-grapheme limit — the AI targets Twitter's
            // 280-char limit (with URL shortening), so the actual text with full
            // URLs can exceed 300 graphemes for long URLs.
            const blueskyText = fitPostToLimit(postText, BLUESKY_MAX_LENGTH);
            if (blueskyText !== postText) {
              console.log(`  ✂️ Bluesky: trimmed post from ${countGraphemes(postText)} to ${countGraphemes(blueskyText)} graphemes`);
            }

            const bskyPost = await postToBluesky(blueskyText, env.bluesky!, linkCard);
            const did = extractBlueskyDid(bskyPost.uri);
            const postId = extractBlueskyPostId(bskyPost.uri);
            console.log(
              `✅ Bluesky post created: ${buildBlueskyPostUrl(did, postId)}`,
            );

            console.log(`🔗 Fetching Bluesky embed code...`);
            const bskyEmbedHtml = await getBlueskyEmbedHtml(
              bskyPost.uri, bskyPost.text, date, env.bluesky!.identifier, bskyPost.cid,
            );
            console.log(`📋 Got Bluesky embed HTML (${bskyEmbedHtml.length} chars)`);

            return {
              header: BLUESKY_SECTION_HEADER,
              embedHtml: bskyEmbedHtml,
              buildSection: buildBlueskySection,
            };
          } catch (error) {
            console.error(`⚠️  Bluesky posting failed (non-fatal):`);
            console.error(`   ${error instanceof Error ? error.message : error}`);
            if (error instanceof Error && error.stack) {
              console.error(`   Stack: ${error.stack.split("\n").slice(0, 3).join("\n   ")}`);
            }
            return null;
          }
        })(),
      );
    } else if (!env.bluesky) {
      console.log(`ℹ️  Bluesky credentials not configured, skipping`);
    }

    // Mastodon posting task
    if (env.mastodon && !reflection.hasMastodonSection) {
      postingTasks.push(
        (async (): Promise<EmbedSection | null> => {
          try {
            console.log(`🐘 Posting to Mastodon...`);

            const mastodonText = fitPostToLimit(postText, MASTODON_MAX_LENGTH);
            if (mastodonText !== postText) {
              console.log(`  ✂️ Mastodon: trimmed post from ${countGraphemes(postText)} to ${countGraphemes(mastodonText)} graphemes`);
            }

            const mastodonPost = await postToMastodon(mastodonText, env.mastodon!);
            console.log(
              `✅ Mastodon post created: ${mastodonPost.url}`,
            );

            console.log(`🔗 Fetching Mastodon embed code...`);
            const mastodonEmbedHtml = await getMastodonEmbedHtml(
              mastodonPost.url, mastodonPost.text, date,
            );
            console.log(`📋 Got Mastodon embed HTML (${mastodonEmbedHtml.length} chars)`);

            return {
              header: MASTODON_SECTION_HEADER,
              embedHtml: mastodonEmbedHtml,
              buildSection: buildMastodonSection,
            };
          } catch (error) {
            console.error(`⚠️  Mastodon posting failed (non-fatal):`);
            console.error(`   ${error instanceof Error ? error.message : error}`);
            if (error instanceof Error && error.stack) {
              console.error(`   Stack: ${error.stack.split("\n").slice(0, 3).join("\n   ")}`);
            }
            return null;
          }
        })(),
      );
    } else if (!env.mastodon) {
      console.log(`ℹ️  Mastodon credentials not configured, skipping`);
    }

    // Wait for all posting tasks to complete
    if (postingTasks.length > 0) {
      console.log(`📡 Posting to ${postingTasks.length} platform(s) in parallel...`);
      const results = await Promise.allSettled(postingTasks);
      for (const result of results) {
        if (result.status === "fulfilled" && result.value) {
          embedSections.push(result.value);
        }
      }
    }
  });

  // Step 6: Write embed sections to Obsidian vault via Headless Sync
  if (embedSections.length > 0 && vaultDir) {
    console.log(`📝 Writing ${embedSections.length} embed section(s) to Obsidian note: ${obsidianNotePath}`);

    await timer.time("obsidian-write-push", async () => {
      // Read note from synced vault (already pulled in step 2)
      const filePath = path.join(vaultDir!, obsidianNotePath);
      if (!fs.existsSync(filePath)) {
        throw new Error(
          `Note not found in Obsidian vault: ${obsidianNotePath} (looked at ${filePath})`,
        );
      }

      let content = fs.readFileSync(filePath, "utf-8");
      let modified = false;

      for (const section of embedSections) {
        if (!content.includes(section.header)) {
          content = content + section.buildSection(content, section.embedHtml);
          modified = true;
        } else {
          console.log(`${section.header} already exists in Obsidian note, skipping`);
        }
      }

      if (modified) {
        fs.writeFileSync(filePath, content, "utf-8");
        await pushObsidianVault(vaultDir!, { authToken: env.obsidian.authToken });
      } else {
        console.log("No new sections to add to Obsidian note");
      }
    });
    console.log(`✅ Obsidian vault updated via Headless Sync (review in Obsidian and publish)`);
  } else {
    if (embedSections.length === 0) {
      console.log(`ℹ️  No successful posts to embed`);
    }
  }

  console.log(`🎉 Done processing ${notePath || `reflection for ${date}`}`);
  timer.printSummary();
}

// Run if executed directly
const isMainModule = process.argv[1]?.endsWith("tweet-reflection.ts");
if (isMainModule) {
  const { date, note } = parseArgs();
  main({ date, note }).catch((error) => {
    console.error(
      `❌ Error: ${error instanceof Error ? error.message : error}`,
    );
    if (error instanceof Error && error.stack) {
      console.error(`Stack trace:\n${error.stack}`);
    }
    // Log extra fields from API errors
    const e = error as { code?: number; data?: unknown; rateLimit?: unknown };
    if (e.code) console.error(`HTTP status code: ${e.code}`);
    if (e.data) console.error(`Response data: ${JSON.stringify(e.data, null, 2)}`);
    if (e.rateLimit) console.error(`Rate limit: ${JSON.stringify(e.rateLimit, null, 2)}`);
    process.exit(1);
  });
}
