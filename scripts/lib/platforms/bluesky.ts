/**
 * Bluesky platform integration via AT Protocol.
 *
 * Handles posting (with rich link cards), deleting, URL extraction,
 * and embed HTML generation for Bluesky.
 *
 * @module platforms/bluesky
 */

import type { BlueskyCredentials, BlueskyPostResult, EmbedResult, LinkCard } from "../types.ts";
import {
  BLUESKY_DISPLAY_NAME,
  BLUESKY_OEMBED_INITIAL_DELAY_MS,
  BLUESKY_OEMBED_RETRY_DELAY_MS,
} from "../types.ts";
import { textToHtml, formatDisplayDate } from "../html.ts";
import { fetchImageAsBuffer } from "./og-metadata.ts";

// --- URL Extraction (Pure Functions) ---

export const extractBlueskyPostId = (uri: string): string =>
  uri.split("/").at(-1) ?? "";

export const extractBlueskyDid = (uri: string): string =>
  uri.match(/at:\/\/(did:[^/]+)/)?.[1] ?? "";

export const buildBlueskyPostUrl = (did: string, postId: string): string =>
  `https://bsky.app/profile/${did}/post/${postId}`;

// --- Posting ---

/**
 * Post to Bluesky using the AT Protocol API.
 *
 * Supports rich link card embeds with thumbnail images.
 * Uses RichText for facet detection (clickable links, mentions).
 */
export async function postToBluesky(
  text: string,
  credentials: BlueskyCredentials,
  linkCard?: LinkCard,
): Promise<BlueskyPostResult> {
  const { AtpAgent, RichText } = await import("@atproto/api");
  const agent = new AtpAgent({ service: "https://bsky.social" });

  await agent.login({
    identifier: credentials.identifier,
    password: credentials.password,
  });

  console.log(`  📡 Bluesky: creating post...`);

  const rt = new RichText({ text });
  await rt.detectFacets(agent);

  const postRecord: Record<string, unknown> = {
    text: rt.text,
    facets: rt.facets,
  };

  if (linkCard) {
    const external: Record<string, unknown> = {
      uri: linkCard.uri,
      title: linkCard.title,
      description: linkCard.description,
    };

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

    postRecord.embed = { $type: "app.bsky.embed.external", external };
    console.log(`  🔗 Bluesky: attaching link card for ${linkCard.uri}`);
  }

  const response = await agent.post(postRecord);

  return { uri: response.uri, cid: response.cid, text };
}

/**
 * Delete a Bluesky post (used for test cleanup).
 */
export async function deleteBlueskyPost(
  uri: string,
  credentials: BlueskyCredentials,
): Promise<void> {
  const { AtpAgent } = await import("@atproto/api");
  const agent = new AtpAgent({ service: "https://bsky.social" });
  await agent.login({ identifier: credentials.identifier, password: credentials.password });
  await agent.deletePost(uri);
}

// --- Embed HTML ---

/**
 * Fetch Bluesky post embed HTML from the oEmbed API.
 */
export async function fetchBlueskyOEmbed(postUrl: string): Promise<EmbedResult> {
  const params = new URLSearchParams({ url: postUrl, format: "json" });
  const response = await fetch(`https://embed.bsky.app/oembed?${params}`);

  if (!response.ok) {
    throw new Error(`Bluesky oEmbed API returned ${response.status}: ${response.statusText}`);
  }

  const data = (await response.json()) as { html: string };
  return { html: data.html };
}

/**
 * Generate Bluesky embed HTML locally as a fallback.
 */
export const generateLocalBlueskyEmbed = (
  uri: string,
  postText: string,
  date: string,
  handle: string,
  cid?: string,
): string => {
  const did = extractBlueskyDid(uri);
  const postId = extractBlueskyPostId(uri);
  const postUrl = buildBlueskyPostUrl(did, postId);
  const htmlText = textToHtml(postText);
  const displayDate = formatDisplayDate(date);
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
};

const delay = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Get Bluesky embed HTML, trying oEmbed first (with retry for propagation delay),
 * then falling back to local generation.
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
      const delayMs = attempt === 0 ? BLUESKY_OEMBED_INITIAL_DELAY_MS : BLUESKY_OEMBED_RETRY_DELAY_MS;
      if (delayMs > 0) {
        console.log(`  ⏳ Waiting ${delayMs / 1000}s for Bluesky post propagation...`);
        await delay(delayMs);
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
