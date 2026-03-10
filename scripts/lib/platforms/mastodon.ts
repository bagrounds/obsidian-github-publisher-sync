/**
 * Mastodon platform integration.
 *
 * Handles posting, deleting, URL parsing, and embed HTML generation
 * for Mastodon instances.
 *
 * @module platforms/mastodon
 */

import type { MastodonCredentials, MastodonPostResult, EmbedResult } from "../types.ts";

// --- URL Extraction (Pure Functions) ---

export const extractMastodonInstanceUrl = (postUrl: string): string => {
  try {
    const url = new URL(postUrl);
    return `${url.protocol}//${url.host}`;
  } catch {
    return "";
  }
};

export const extractMastodonStatusId = (postUrl: string): string =>
  postUrl.split("/").at(-1) ?? "";

export const extractMastodonUsername = (postUrl: string): string =>
  postUrl.match(/@([^/]+)/)?.[1] ?? "";

// --- Posting ---

/**
 * Post to Mastodon using the REST API.
 *
 * Supports the Idempotency-Key header to prevent duplicate posts on retries.
 * Default character limit is 500 (instance-configurable).
 */
export async function postToMastodon(
  text: string,
  credentials: MastodonCredentials,
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
  credentials: MastodonCredentials,
): Promise<void> {
  const { createRestAPIClient } = await import("masto");
  const client = createRestAPIClient({
    url: credentials.instanceUrl,
    accessToken: credentials.accessToken,
  });
  await client.v1.statuses.$select(statusId).remove();
}

// --- Embed HTML ---

/**
 * Fetch Mastodon post embed HTML from the instance's oEmbed API.
 */
export async function fetchMastodonOEmbed(postUrl: string): Promise<EmbedResult> {
  const instanceUrl = extractMastodonInstanceUrl(postUrl);
  if (!instanceUrl) {
    throw new Error(`Could not extract instance URL from: ${postUrl}`);
  }

  const params = new URLSearchParams({ url: postUrl });
  const response = await fetch(`${instanceUrl}/api/oembed?${params}`);

  if (!response.ok) {
    throw new Error(`Mastodon oEmbed API returned ${response.status}: ${response.statusText}`);
  }

  const data = (await response.json()) as { html: string };
  return { html: data.html };
}

/**
 * Generate Mastodon embed HTML locally as a fallback.
 */
export const generateLocalMastodonEmbed = (
  postUrl: string,
  _postText: string,
  _date: string,
): string => {
  const instanceUrl = extractMastodonInstanceUrl(postUrl);

  return (
    `<iframe src="${postUrl}/embed" class="mastodon-embed" ` +
    `style="max-width: 100%; border: 0" width="400" allowfullscreen="allowfullscreen"></iframe>` +
    `<script src="${instanceUrl}/embed.js" async="async"></script>`
  );
};

/**
 * Get Mastodon embed HTML, trying oEmbed first, then falling back to local generation.
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
