/**
 * Social Post Reflection Automation Script
 *
 * Reads yesterday's reflection from the repo, generates a post via Gemini,
 * posts it to Twitter and Bluesky, fetches the embed code, and writes the
 * updated note back to the Obsidian vault via Obsidian Headless Sync.
 *
 * Twitter and Bluesky are both optional — the script posts to whichever
 * platforms have credentials configured. Platform failures are logged but
 * don't crash the pipeline.
 *
 * The user reviews the change in Obsidian and publishes it to this repo
 * via the Enveloppe plugin (one-way sync: Obsidian → GitHub).
 *
 * Usage:
 *   npx tsx scripts/tweet-reflection.ts [--date YYYY-MM-DD] [--dry-run]
 *
 * Environment variables:
 *   TWITTER_API_KEY       - (Optional) OAuth 1.0a Consumer Key (from X Developer Portal → Keys and Tokens)
 *   TWITTER_API_SECRET    - (Optional) OAuth 1.0a Consumer Secret
 *   TWITTER_ACCESS_TOKEN  - (Optional) OAuth 1.0a Access Token (generated with Read+Write permissions)
 *   TWITTER_ACCESS_SECRET - (Optional) OAuth 1.0a Access Token Secret
 *   BLUESKY_IDENTIFIER    - (Optional) Bluesky handle (e.g. "bagrounds.bsky.social") or DID
 *   BLUESKY_APP_PASSWORD  - (Optional) Bluesky App Password (from Settings → App Passwords)
 *   GEMINI_API_KEY        - Google Gemini API key (from Google AI Studio)
 *   GEMINI_MODEL          - (Optional) Gemini model name, defaults to gemma-3-27b-it
 *   OBSIDIAN_AUTH_TOKEN   - Obsidian account auth token (from `ob login`)
 *   OBSIDIAN_VAULT_NAME   - Remote vault name or ID in Obsidian Sync
 *   OBSIDIAN_VAULT_PASSWORD - (Optional) E2EE vault password, if vault uses end-to-end encryption
 *
 * @see https://github.com/PLhery/node-twitter-api-v2 — twitter-api-v2 docs
 * @see https://docs.bsky.app/ — Bluesky/AT Protocol API docs
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

export interface EmbedResult {
  /** HTML embed code */
  html: string;
}

// --- Constants ---

const CONTENT_DIR = path.join(process.cwd(), "content", "reflections");
const TWITTER_HANDLE = "bagrounds";
const TWITTER_DISPLAY_NAME = "Bryan Grounds";
const BLUESKY_DISPLAY_NAME = "Bryan Grounds";
const TWEET_SECTION_HEADER = "## 🐦 Tweet";
const BLUESKY_SECTION_HEADER = "## 🦋 Bluesky";
/** Twitter counts all URLs as 23 characters */
const TWITTER_URL_LENGTH = 23;
const TWITTER_MAX_LENGTH = 280;
/** Bluesky has a 300-character limit for post text */
const BLUESKY_MAX_LENGTH = 300;
/** Delay before first Bluesky oEmbed attempt to allow post propagation */
const BLUESKY_OEMBED_INITIAL_DELAY_MS = 3_000;
/** Delay before retrying Bluesky oEmbed on 404 */
const BLUESKY_OEMBED_RETRY_DELAY_MS = 5_000;

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
  contentDir: string = CONTENT_DIR,
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
  contentDir: string = CONTENT_DIR,
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
- Keep the total tweet under 280 characters (URLs count as 23 characters)
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
  const monthNames = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  const displayDate = `${monthNames[dateObj.getUTCMonth()]} ${dateObj.getUTCDate()}, ${dateObj.getUTCFullYear()}`;

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
    postRecord.embed = {
      $type: "app.bsky.embed.external",
      external: {
        uri: linkCard.uri,
        title: linkCard.title,
        description: linkCard.description,
      },
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
  const monthNames = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  const displayDate = `${monthNames[dateObj.getUTCMonth()]} ${dateObj.getUTCDate()}, ${dateObj.getUTCFullYear()}`;

  const cidAttr = cid ? ` data-bluesky-cid="${cid}"` : "";

  return (
    `<blockquote class="bluesky-embed" data-bluesky-uri="${uri}"${cidAttr} data-bluesky-embed-color-mode="system">` +
    `<p lang="en">${htmlText}</p>` +
    `&mdash; ${BLUESKY_DISPLAY_NAME} ` +
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
      // Wait before oEmbed attempt to allow post propagation
      const delayMs = attempt === 0
        ? BLUESKY_OEMBED_INITIAL_DELAY_MS
        : BLUESKY_OEMBED_RETRY_DELAY_MS;
      console.log(`  ⏳ Waiting ${delayMs / 1000}s for Bluesky post propagation...`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));

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
 * @returns The local vault path where files were synced
 */
export async function syncObsidianVault(credentials: {
  authToken: string;
  vaultName: string;
  vaultPassword?: string;
}): Promise<string> {
  const vaultDir = path.join(
    process.env.RUNNER_TEMP || "/tmp",
    `obsidian-vault-${process.pid}-${Date.now()}`,
  );
  fs.mkdirSync(vaultDir, { recursive: true });

  const env: Record<string, string> = {
    OBSIDIAN_AUTH_TOKEN: credentials.authToken,
  };

  // Set up the vault for syncing
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

  // Kill lingering processes and remove stale lock left by sync-setup.
  // sync-setup may leave orphan child processes that hold the lock.
  // @see https://github.com/obsidianmd/obsidian-headless/issues/4
  await ensureSyncClean(vaultDir);

  // Pull latest content (retry once if lock contention occurs)
  console.log(`📥 Pulling latest vault content...`);
  try {
    await runObCommand(["sync", "--path", vaultDir], { env });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    if (msg.includes("Another sync instance")) {
      console.warn(`  ⚠️ Sync lock contention on pull, cleaning up and retrying...`);
      await ensureSyncClean(vaultDir);
      await runObCommand(["sync", "--path", vaultDir], { env });
    } else {
      throw error;
    }
  }

  return vaultDir;
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
function removeSyncLock(vaultDir: string): void {
  const lockPath = path.join(vaultDir, ".obsidian", ".sync.lock");
  if (fs.existsSync(lockPath)) {
    console.log(`🔓 Removing stale .sync.lock from vault`);
    fs.rmSync(lockPath, { recursive: true, force: true });
  }
}

/**
 * Kill any lingering `ob` processes that may be holding the sync lock.
 *
 * The `ob sync-setup` and `ob sync` commands can leave orphan child processes
 * that hold the `.sync.lock` even after the parent process exits. Removing the
 * lock file alone doesn't help because the running process recreates it or
 * detects the running instance via other means (e.g. PID file, socket).
 *
 * This function finds all `ob` processes (except the current one) and sends
 * SIGTERM to each, then waits briefly for them to exit.
 *
 * ## 5 Whys — Obsidian sync lock failure
 *
 * 1. **Why does "Another sync instance is already running" persist after
 *    removing `.sync.lock`?**
 *    Because the `ob` CLI checks for a running process, not just a lock file.
 *    A lingering `ob` process from `sync-setup` or a previous `sync` still
 *    holds the lock at the OS level.
 *
 * 2. **Why is there a lingering `ob` process?**
 *    `ob sync-setup` may spawn background workers or keep a file watcher
 *    alive. When called via Node's `execFile`, the parent resolves after
 *    stdout/stderr close, but child processes may linger.
 *
 * 3. **Why doesn't `execFile` kill child processes on completion?**
 *    `execFile` only waits for the main process; it doesn't track or kill
 *    grandchild/orphan processes. The `ob` tool's internal architecture
 *    may fork workers that outlive the main CLI process.
 *
 * 4. **Why does the retry-after-5s approach also fail?**
 *    The 5s delay doesn't kill the lingering process — it just waits.
 *    The process is still alive and still holding the lock when the retry
 *    fires.
 *
 * 5. **What is the root fix?**
 *    Kill all `ob` processes between operations. This ensures no orphan
 *    process holds the lock when the next `ob sync` starts. Combined
 *    with lock file removal, this handles both file-based and process-based
 *    lock mechanisms.
 *
 * @see https://github.com/obsidianmd/obsidian-headless/issues/4
 * @see https://help.obsidian.md/sync/headless
 */
async function killObProcesses(): Promise<void> {
  try {
    // Find 'ob' processes owned by the current user.
    // Uses `ps -u $(id -u)` to scope to current user (avoids killing other users'
    // processes in multi-user CI environments) and matches the 'ob' command name.
    const { stdout } = await execAsync(
      "ps -u $(id -u) -o pid,comm | grep '[o]b$' | awk '{print $1}'",
    );
    const pids = stdout.trim().split("\n").filter(Boolean);
    if (pids.length > 0) {
      console.log(`🔪 Killing ${pids.length} lingering ob process(es): ${pids.join(", ")}`);
      for (const pid of pids) {
        try {
          process.kill(parseInt(pid, 10), "SIGTERM");
        } catch (err) {
          // ESRCH = process already exited — expected and safe to ignore
          if ((err as NodeJS.ErrnoException).code !== "ESRCH") {
            console.warn(`  ⚠️ Could not kill PID ${pid}: ${(err as Error).message}`);
          }
        }
      }
      // Wait for processes to terminate. The `ob` CLI handles SIGTERM gracefully
      // and cleans up within ~1s based on observed behavior in CI.
      await new Promise((resolve) => setTimeout(resolve, 2_000));
    }
  } catch {
    // ps/grep may fail if no processes found — that's fine
  }
}

/**
 * Ensure no sync lock or lingering process blocks the next `ob sync`.
 * Combines lock file removal with process cleanup for maximum reliability.
 */
async function ensureSyncClean(vaultDir: string): Promise<void> {
  await killObProcesses();
  removeSyncLock(vaultDir);
}

/**
 * Push local changes back to the Obsidian vault via Headless Sync.
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
  try {
    await runObCommand(["sync", "--path", vaultDir], { env });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    if (msg.includes("Another sync instance")) {
      console.warn(`  ⚠️ Sync lock contention on push, cleaning up and retrying...`);
      await ensureSyncClean(vaultDir);
      await runObCommand(["sync", "--path", vaultDir], { env });
    } else {
      throw error;
    }
  }
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
function parseArgs(): { date: string; dryRun: boolean } {
  const args = process.argv.slice(2);
  let date = getYesterdayDate();
  let dryRun = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--date" && args[i + 1]) {
      date = args[i + 1] as string;
      i++;
    } else if (args[i] === "--dry-run") {
      dryRun = true;
    }
  }

  return { date, dryRun };
}

/**
 * Validate that all required environment variables are set.
 * Twitter and Bluesky credentials are optional — the script will attempt
 * each platform only if its credentials are present.
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
  const twitterKeys = [
    "TWITTER_API_KEY",
    "TWITTER_API_SECRET",
    "TWITTER_ACCESS_TOKEN",
    "TWITTER_ACCESS_SECRET",
  ];
  const hasTwitter = twitterKeys.every((key) => process.env[key]);
  const twitter = hasTwitter
    ? {
        apiKey: process.env.TWITTER_API_KEY as string,
        apiSecret: process.env.TWITTER_API_SECRET as string,
        accessToken: process.env.TWITTER_ACCESS_TOKEN as string,
        accessSecret: process.env.TWITTER_ACCESS_SECRET as string,
      }
    : null;

  // Bluesky credentials are optional — both must be present to enable
  const hasBluesky =
    !!process.env.BLUESKY_IDENTIFIER && !!process.env.BLUESKY_APP_PASSWORD;
  const bluesky = hasBluesky
    ? {
        identifier: process.env.BLUESKY_IDENTIFIER as string,
        password: process.env.BLUESKY_APP_PASSWORD as string,
      }
    : null;

  return {
    twitter,
    bluesky,
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
 * Posts to both Twitter and Bluesky (if credentials are configured).
 * Twitter failures are logged but don't crash the pipeline.
 * Bluesky failures are also logged but don't crash.
 * The pipeline continues as long as at least one platform succeeds,
 * or if only dry-run/generation is requested.
 */
export async function main(options?: {
  date?: string;
  dryRun?: boolean;
  contentDir?: string;
}): Promise<void> {
  const date = options?.date || getYesterdayDate();
  const dryRun = options?.dryRun || false;
  const contentDir = options?.contentDir || CONTENT_DIR;

  console.log(
    `📅 Processing reflection for ${date}${dryRun ? " (DRY RUN)" : ""}`,
  );

  // Step 1: Read the reflection from the repo (checked out by GitHub Actions)
  const reflection = readReflection(date, contentDir);
  if (!reflection) {
    console.log(`ℹ️  No reflection found for ${date}, exiting`);
    return;
  }

  console.log(`📄 Found reflection: ${reflection.title}`);

  // Check idempotency — skip if both sections already exist
  if (reflection.hasTweetSection && reflection.hasBlueskySection) {
    console.log(`ℹ️  Reflection already has both tweet and Bluesky sections, skipping`);
    return;
  }

  // Step 2: Validate credentials
  const env = validateEnvironment();

  if (!env.twitter && !env.bluesky) {
    console.warn(`⚠️  No social platform credentials configured. Set TWITTER_* or BLUESKY_* env vars.`);
  }

  // Step 3: Generate post text with Gemini
  console.log(`🤖 Generating post with ${env.gemini.model}...`);
  const postText = await generateTweetWithGemini(
    reflection,
    env.gemini.apiKey,
    env.gemini.model,
  );
  console.log(
    `📝 Generated post (${calculateTweetLength(postText)} chars):\n${postText}`,
  );

  if (dryRun) {
    console.log(`🏁 Dry run complete, would have posted the above`);
    return;
  }

  // Collect embed sections to write to Obsidian
  const embedSections: EmbedSection[] = [];

  // Step 4: Post to social platforms in parallel (both non-fatal)
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

          // Build link card for the reflection URL so Bluesky renders a website preview.
          // Bluesky does NOT auto-fetch OpenGraph metadata; we must supply it explicitly.
          // @see https://docs.bsky.app/docs/advanced-guides/posts#website-card-embeds
          const linkCard = {
            uri: reflection.url,
            title: reflection.title,
            description: `Daily reflection from bagrounds.org — ${reflection.date}`,
          };

          const bskyPost = await postToBluesky(postText, env.bluesky!, linkCard);
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

  // Step 5: Write embed sections to Obsidian vault via Headless Sync
  if (embedSections.length > 0) {
    const obsidianNotePath = `reflections/${date}.md`;
    console.log(`📝 Writing ${embedSections.length} embed section(s) to Obsidian note: ${obsidianNotePath}`);
    await appendEmbedsToObsidianNote(obsidianNotePath, embedSections, env.obsidian);
    console.log(`✅ Obsidian vault updated via Headless Sync (review in Obsidian and publish)`);
  } else {
    console.log(`ℹ️  No successful posts to embed`);
  }

  console.log(`🎉 Done processing reflection for ${date}`);
}

// Run if executed directly
const isMainModule = process.argv[1]?.endsWith("tweet-reflection.ts");
if (isMainModule) {
  const { date, dryRun } = parseArgs();
  main({ date, dryRun }).catch((error) => {
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
