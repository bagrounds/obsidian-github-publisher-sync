/**
 * Daily reflection creation and update for Obsidian vault.
 *
 * Deterministic, template-based operations — no AI required.
 * Creates/updates daily reflection notes and inserts blog post links.
 *
 * All pure functions operate on strings; I/O functions handle the filesystem.
 *
 * @module daily-reflection
 */

import fs from "node:fs";
import path from "node:path";

import type { BlogSeriesConfig } from "./blog-series-config.ts";
import {
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  MASTODON_SECTION_HEADER,
} from "./types.ts";

// --- Constants ---

const EMBED_SECTION_HEADERS = [
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  MASTODON_SECTION_HEADER,
] as const;

// --- Result Types ---

export interface EnsureReflectionResult {
  readonly created: boolean;
  readonly previousDate: string | undefined;
  readonly forwardLinkAdded: boolean;
}

export interface UpdateReflectionResult {
  readonly reflectionCreated: boolean;
  readonly sectionCreated: boolean;
  readonly linkInserted: boolean;
  readonly forwardLinkAdded: boolean;
  readonly previousDate: string | undefined;
}

// --- Pure Functions (no I/O) ---

export const buildReflectionContent = (date: string, previousDate?: string): string => {
  const backLink = previousDate ? ` | [[reflections/${previousDate}|⏮️]]` : "";
  return `---
share: true
aliases:
  - ${date}
title: ${date}
URL: https://bagrounds.org/reflections/${date}
Author: "[[bryan-grounds]]"
tags:
---
[[index|Home]] > [[reflections/index|Reflections]]${backLink}
# ${date}
`;
};

export const buildSeriesSectionHeading = (series: BlogSeriesConfig): string =>
  `## [[${series.id}/index|${series.icon} ${series.name}]]`;

export const buildPostLink = (seriesId: string, filenameNoExt: string, displayTitle: string): string =>
  `- [[${seriesId}/${filenameNoExt}|${displayTitle}]]`;

export const addForwardLink = (content: string, targetDate: string): string => {
  const forwardLink = `[[reflections/${targetDate}|⏭️]]`;
  return content.includes("⏭️") ? content : content.replace("⏮️]]", `⏮️]] ${forwardLink}`);
};

const findFirstEmbedSectionIndex = (content: string): number => {
  const indices = EMBED_SECTION_HEADERS
    .map((header) => content.indexOf(header))
    .filter((index) => index >= 0);
  return indices.length > 0 ? Math.min(...indices) : -1;
};

const appendLinkToExistingSection = (content: string, sectionHeading: string, postLink: string): string => {
  const lines = content.split("\n");
  const sectionIndex = lines.findIndex((line) => line.startsWith(sectionHeading));
  let insertAt = sectionIndex + 1;
  while (insertAt < lines.length && lines[insertAt]!.startsWith("- ")) {
    insertAt++;
  }
  return [...lines.slice(0, insertAt), postLink, ...lines.slice(insertAt)].join("\n");
};

const insertNewSection = (content: string, sectionHeading: string, postLink: string): string => {
  const firstEmbedIndex = findFirstEmbedSectionIndex(content);
  const sectionBlock = `${sectionHeading}\n${postLink}`;

  return firstEmbedIndex >= 0
    ? `${content.slice(0, firstEmbedIndex).trimEnd()}\n\n${sectionBlock}\n\n${content.slice(firstEmbedIndex)}`
    : `${content.trimEnd()}\n\n${sectionBlock}\n`;
};

export const insertPostLink = (
  content: string,
  series: BlogSeriesConfig,
  filenameNoExt: string,
  displayTitle: string,
): string => {
  const linkTarget = `[[${series.id}/${filenameNoExt}|`;
  if (content.includes(linkTarget)) return content;

  const sectionHeading = buildSeriesSectionHeading(series);
  const postLink = buildPostLink(series.id, filenameNoExt, displayTitle);

  return content.includes(sectionHeading)
    ? appendLinkToExistingSection(content, sectionHeading, postLink)
    : insertNewSection(content, sectionHeading, postLink);
};

// --- I/O Functions ---

export const findPreviousReflectionDate = (reflectionsDir: string, today: string): string | undefined => {
  if (!fs.existsSync(reflectionsDir)) return undefined;

  const candidates = fs.readdirSync(reflectionsDir)
    .filter((f) => /^\d{4}-\d{2}-\d{2}\.md$/.test(f) && f < `${today}.md`)
    .sort();

  const latest = candidates.at(-1);
  return latest?.replace(/\.md$/, "");
};

export const ensureDailyReflection = (reflectionsDir: string, today: string): EnsureReflectionResult => {
  const reflectionPath = path.join(reflectionsDir, `${today}.md`);

  if (fs.existsSync(reflectionPath)) {
    return { created: false, previousDate: undefined, forwardLinkAdded: false };
  }

  const previousDate = findPreviousReflectionDate(reflectionsDir, today);
  const content = buildReflectionContent(today, previousDate);
  fs.mkdirSync(reflectionsDir, { recursive: true });
  fs.writeFileSync(reflectionPath, content, "utf-8");

  let forwardLinkAdded = false;
  if (previousDate) {
    const prevPath = path.join(reflectionsDir, `${previousDate}.md`);
    if (fs.existsSync(prevPath)) {
      const prevContent = fs.readFileSync(prevPath, "utf-8");
      const updated = addForwardLink(prevContent, today);
      if (updated !== prevContent) {
        fs.writeFileSync(prevPath, updated, "utf-8");
        forwardLinkAdded = true;
      }
    }
  }

  return { created: true, previousDate, forwardLinkAdded };
};

export const updateDailyReflection = (
  vaultDir: string,
  today: string,
  series: BlogSeriesConfig,
  postFilename: string,
  postTitle: string,
): UpdateReflectionResult => {
  const reflectionsDir = path.join(vaultDir, "reflections");
  const { created, previousDate, forwardLinkAdded } = ensureDailyReflection(reflectionsDir, today);

  const reflectionPath = path.join(reflectionsDir, `${today}.md`);
  const content = fs.readFileSync(reflectionPath, "utf-8");
  const filenameNoExt = postFilename.replace(/\.md$/, "");
  const hadSection = content.includes(buildSeriesSectionHeading(series));
  const updated = insertPostLink(content, series, filenameNoExt, postTitle);

  const linkInserted = updated !== content;
  if (linkInserted) {
    fs.writeFileSync(reflectionPath, updated, "utf-8");
  }

  return {
    reflectionCreated: created,
    sectionCreated: !hadSection && linkInserted,
    linkInserted,
    forwardLinkAdded,
    previousDate,
  };
};
