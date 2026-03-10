/**
 * Twitter platform integration.
 *
 * Handles posting, deleting, and embed HTML generation for Twitter/X.
 * Uses twitter-api-v2 with idempotency keys for safe retries.
 *
 * @module platforms/twitter
 */

import { randomUUID } from "node:crypto";

import type { TwitterCredentials, TweetResult, EmbedResult } from "../types.ts";
import { TWITTER_HANDLE, TWITTER_DISPLAY_NAME } from "../types.ts";
import { textToHtml, formatDisplayDate } from "../html.ts";
import { withRetry } from "../retry.ts";

// --- Error Logging ---

const logTwitterError = (label: string, err: unknown, verbose = false): void => {
  const e = err as {
    code?: number; data?: unknown; headers?: Record<string, string>;
    rateLimit?: unknown; message?: string; stack?: string; type?: string;
  };
  console.error(`  ⚠️ [${label}] ${e.code ?? "?"} ${e.message ?? "unknown error"}`);
  if (!verbose) return;
  console.error(`🔍 Twitter API error details:`);
  console.error(`  HTTP status: ${e.code ?? "unknown"}, type: ${e.type ?? "unknown"}`);
  if (e.data) console.error(`  Response data: ${JSON.stringify(e.data, null, 2)}`);
  if (e.rateLimit) console.error(`  Rate limit: ${JSON.stringify(e.rateLimit, null, 2)}`);
  if (e.stack) console.error(`  Stack trace:\n${e.stack.split("\n").slice(0, 4).join("\n")}`);
};

// --- Posting ---

/**
 * Post a tweet using the Twitter API v2.
 *
 * Uses an X-Idempotency-Key header to prevent duplicate posts on retries
 * after 503 "ghost tweet" scenarios.
 */
export async function postTweet(
  text: string,
  credentials: TwitterCredentials,
): Promise<TweetResult> {
  const { TwitterApi } = await import("twitter-api-v2");
  const client = new TwitterApi({
    appKey: credentials.apiKey,
    appSecret: credentials.apiSecret,
    accessToken: credentials.accessToken,
    accessSecret: credentials.accessSecret,
  });

  const idempotencyKey = randomUUID();
  console.log(`  📡 POST /2/tweets (idempotency key: ${idempotencyKey})`);

  const { data } = await withRetry(
    () => client.v2.post("tweets", { text }, {
      headers: { "X-Idempotency-Key": idempotencyKey },
    }),
    {
      maxRetries: 3,
      baseDelayMs: 1_000,
      onRetry: (err, attempt, delayMs) => {
        const code = (err as { code?: number }).code;
        console.warn(`  ⚠️ Twitter API returned ${code}, retry ${attempt}/3 after ${delayMs / 1000}s...`);
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
  credentials: TwitterCredentials,
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

// --- Embed HTML ---

/**
 * Fetch tweet embed HTML from Twitter's oEmbed API.
 */
export async function fetchOEmbed(
  tweetUrl: string,
  options: { theme?: string } = {},
): Promise<EmbedResult> {
  const params = new URLSearchParams({
    url: tweetUrl,
    theme: options.theme || "dark",
    omit_script: "false",
  });

  const response = await fetch(`https://publish.twitter.com/oembed?${params}`);
  if (!response.ok) {
    throw new Error(`oEmbed API returned ${response.status}: ${response.statusText}`);
  }

  const data = (await response.json()) as { html: string };
  return { html: data.html };
}

/**
 * Generate embed HTML locally as a fallback when oEmbed is unavailable.
 */
export const generateLocalEmbed = (tweetId: string, tweetText: string, date: string): string => {
  const htmlText = textToHtml(tweetText);
  const displayDate = formatDisplayDate(date);

  return (
    `<blockquote class="twitter-tweet" data-theme="dark">` +
    `<p lang="en" dir="ltr">${htmlText}</p>` +
    `&mdash; ${TWITTER_DISPLAY_NAME} (@${TWITTER_HANDLE}) ` +
    `<a href="https://twitter.com/${TWITTER_HANDLE}/status/${tweetId}?ref_src=twsrc%5Etfw">${displayDate}</a>` +
    `</blockquote> ` +
    `<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>`
  );
};

/**
 * Get embed HTML, trying oEmbed first, then falling back to local generation.
 */
export async function getEmbedHtml(tweetId: string, tweetText: string, date: string): Promise<string> {
  const tweetUrl = `https://twitter.com/${TWITTER_HANDLE}/status/${tweetId}`;
  try {
    const { html } = await fetchOEmbed(tweetUrl, { theme: "dark" });
    return html;
  } catch (error) {
    console.warn(`oEmbed API failed, using local embed generation: ${error}`);
    return generateLocalEmbed(tweetId, tweetText, date);
  }
}

export { logTwitterError };
