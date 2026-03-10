/**
 * Generic embed section building for social media platforms.
 *
 * Uses a factory function (higher-order function) to eliminate the
 * duplication of buildTweetSection, buildBlueskySection, buildMastodonSection.
 *
 * This is an application of the Strategy pattern expressed functionally:
 * the section header is a parameter, and the build logic is shared.
 *
 * @module embed-section
 */

import fs from "node:fs";

import {
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  MASTODON_SECTION_HEADER,
} from "./types.ts";

// --- Generic Section Builder (Factory / Higher-Order Function) ---

/**
 * Create a section builder for a given header.
 *
 * Returns a pure function: (existingContent, embedHtml) → sectionString.
 *
 * This is a higher-order function (returns a function), eliminating the
 * duplication of three nearly-identical build functions.
 */
export const createSectionBuilder = (header: string) =>
  (existingContent: string, embedHtml: string): string => {
    const separator = existingContent.endsWith("\n") ? "\n" : "\n\n";
    return `${separator}${header}  \n${embedHtml}`;
  };

/**
 * Create a section appender for a given header.
 *
 * Returns an effectful function that appends the section to a file,
 * with idempotency: skips if the section already exists.
 */
export const createSectionAppender = (header: string) => {
  const buildSection = createSectionBuilder(header);

  return (filePath: string, embedHtml: string): void => {
    const content = fs.readFileSync(filePath, "utf-8");

    if (content.includes(header)) {
      console.log(`${header} already exists, skipping update`);
      return;
    }

    fs.writeFileSync(filePath, content + buildSection(content, embedHtml), "utf-8");
  };
};

// --- Platform-Specific Instances ---

export const buildTweetSection = createSectionBuilder(TWEET_SECTION_HEADER);
export const buildBlueskySection = createSectionBuilder(BLUESKY_SECTION_HEADER);
export const buildMastodonSection = createSectionBuilder(MASTODON_SECTION_HEADER);

export const appendTweetSection = createSectionAppender(TWEET_SECTION_HEADER);
export const appendBlueskySection = createSectionAppender(BLUESKY_SECTION_HEADER);
export const appendMastodonSection = createSectionAppender(MASTODON_SECTION_HEADER);
