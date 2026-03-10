/**
 * OpenGraph metadata fetching.
 *
 * Fetches og:title, og:description, and og:image from web pages.
 * Used by Bluesky to build rich link card embeds.
 *
 * @module og-metadata
 */

import type { OgMetadata } from "../types.ts";

/**
 * Extract an OpenGraph property value from HTML.
 * Handles both attribute orders:
 *   <meta property="og:X" content="value">
 *   <meta content="value" property="og:X">
 */
const extractOgProperty = (html: string, property: string): string | undefined => {
  const propFirst = html.match(
    new RegExp(`<meta\\s+property=["']${property}["']\\s+content=["']([^"']+)["']`, "i"),
  );
  if (propFirst) return propFirst[1];

  const contentFirst = html.match(
    new RegExp(`<meta\\s+content=["']([^"']+)["']\\s+property=["']${property}["']`, "i"),
  );
  return contentFirst?.[1];
};

/**
 * Fetch OpenGraph metadata from a URL by parsing <meta property="og:*"> tags.
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
    return {
      title: extractOgProperty(html, "og:title"),
      description: extractOgProperty(html, "og:description"),
      imageUrl: extractOgProperty(html, "og:image"),
    };
  } catch (error) {
    console.warn(`  ⚠️ OG fetch failed for ${url}: ${error instanceof Error ? error.message : error}`);
    return {};
  }
}

/**
 * Fetch an image from a URL and return it as a Uint8Array with its MIME type.
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
