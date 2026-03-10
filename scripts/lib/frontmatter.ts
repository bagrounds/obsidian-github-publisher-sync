/**
 * Frontmatter parsing and note I/O.
 *
 * Pure parsing functions for YAML frontmatter in markdown files,
 * plus note reading functions that bridge the filesystem boundary.
 *
 * @module frontmatter
 */

import fs from "node:fs";
import path from "node:path";

import type { ReflectionData } from "./types.ts";
import {
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  MASTODON_SECTION_HEADER,
} from "./types.ts";

// --- Pure Parsing ---

/**
 * Parse frontmatter from a markdown string.
 * Returns the frontmatter key-value pairs and the body after frontmatter.
 *
 * Pure function: operates only on the input string, no I/O.
 */
export function parseFrontmatter(content: string): {
  frontmatter: Record<string, string>;
  body: string;
} {
  const lines = content.split("\n");

  if (lines[0]?.trim() !== "---") {
    return { frontmatter: {}, body: content };
  }

  const endIndex = lines.findIndex((line, i) => i > 0 && line.trim() === "---");

  if (endIndex < 0) {
    return { frontmatter: {}, body: content };
  }

  const frontmatter = Object.fromEntries(
    lines
      .slice(1, endIndex)
      .map((line) => line.match(/^(\w+):\s*(.*)$/))
      .filter((match): match is RegExpMatchArray => match !== null)
      .map(([, key, value]) => [
        key as string,
        (value as string).replace(/^["']|["']$/g, ""),
      ]),
  );

  const body = lines.slice(endIndex + 1).join("\n");
  return { frontmatter, body };
}

// --- Section Detection ---

const hasSectionHeader = (content: string, header: string): boolean =>
  content.includes(header);

const detectSections = (content: string) => ({
  hasTweetSection: hasSectionHeader(content, TWEET_SECTION_HEADER),
  hasBlueskySection: hasSectionHeader(content, BLUESKY_SECTION_HEADER),
  hasMastodonSection: hasSectionHeader(content, MASTODON_SECTION_HEADER),
});

// --- File Path Utilities ---

export const getReflectionPath = (date: string, contentDir: string): string =>
  path.join(contentDir, `${date}.md`);

const extractDateFromFilename = (filename: string): string => {
  const match = path.basename(filename).match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? (match[1] as string) : (new Date().toISOString().split("T")[0] as string);
};

const deriveUrl = (frontmatter: Record<string, string>, relativePath: string): string => {
  const slug = relativePath.replace(/\.md$/, "");
  return frontmatter["URL"] || `https://bagrounds.org/${slug}`;
};

// --- Note Reading ---

/**
 * Read and parse a reflection file by date.
 */
export function readReflection(date: string, contentDir: string): ReflectionData | null {
  const filePath = getReflectionPath(date, contentDir);

  if (!fs.existsSync(filePath)) return null;

  const content = fs.readFileSync(filePath, "utf-8");
  const { frontmatter, body } = parseFrontmatter(content);

  return {
    date,
    title: frontmatter["title"] || date,
    url: frontmatter["URL"] || `https://bagrounds.org/reflections/${date}`,
    body,
    filePath,
    ...detectSections(content),
  };
}

/**
 * Read and parse an arbitrary content note by relative path.
 */
export function readNote(relativePath: string, contentDir: string): ReflectionData | null {
  const filePath = path.join(contentDir, relativePath);

  if (!fs.existsSync(filePath)) return null;

  const content = fs.readFileSync(filePath, "utf-8");
  const { frontmatter, body } = parseFrontmatter(content);

  return {
    date: extractDateFromFilename(relativePath),
    title: frontmatter["title"] || path.basename(relativePath, ".md"),
    url: deriveUrl(frontmatter, relativePath),
    body,
    filePath,
    ...detectSections(content),
  };
}
