/**
 * AI Blog Post Navigation Links
 *
 * Ensures all ai-blog posts have ⏮️/⏭️ navigation links connecting them
 * in chronological order. Posts are linked by their filename sort order
 * (which is date-based: YYYY-MM-DD-slug.md).
 *
 * Also links new ai-blog posts from the daily reflection that matches
 * their date, using the daily-updates mechanism.
 *
 * Pure functions operate on strings; I/O functions handle the filesystem.
 *
 * @module ai-blog-links
 */

import fs from "node:fs";
import path from "node:path";

import { parseFrontmatter } from "./frontmatter.ts";

// --- Constants ---

export const AI_BLOG_NAV_PREFIX = "[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]";

// --- Pure Functions (no I/O) ---

export const buildAiBlogBackLink = (prevFilename: string): string =>
  `[[ai-blog/${prevFilename.replace(/\.md$/, "")}|⏮️]]`;

export const buildAiBlogForwardLink = (nextFilename: string): string =>
  `[[ai-blog/${nextFilename.replace(/\.md$/, "")}|⏭️]]`;

/**
 * Build the full nav line for an ai-blog post with optional prev/next links.
 */
export const buildNavLine = (prevFilename?: string, nextFilename?: string): string => {
  const links = [
    prevFilename ? buildAiBlogBackLink(prevFilename) : undefined,
    nextFilename ? buildAiBlogForwardLink(nextFilename) : undefined,
  ].filter(Boolean);

  return links.length > 0
    ? `${AI_BLOG_NAV_PREFIX} | ${links.join(" ")}`
    : AI_BLOG_NAV_PREFIX;
};

/**
 * Update a post's content to include the correct nav links.
 *
 * Finds the line starting with the AI_BLOG_NAV_PREFIX and replaces it
 * with the full nav line including any applicable ⏮️/⏭️ links.
 *
 * Returns the content unchanged if no nav prefix line is found.
 * Idempotent: safe to call repeatedly with the same arguments.
 */
export const updateNavLinks = (
  content: string,
  prevFilename: string | undefined,
  nextFilename: string | undefined,
): string => {
  const navLine = buildNavLine(prevFilename, nextFilename);
  const lines = content.split("\n");
  const navIndex = lines.findIndex((line) => line.startsWith(AI_BLOG_NAV_PREFIX));

  if (navIndex < 0) return content;

  const currentLine = lines[navIndex];
  if (!currentLine || currentLine === navLine) return content;

  return [...lines.slice(0, navIndex), navLine, ...lines.slice(navIndex + 1)].join("\n");
};

/**
 * Check whether a post's nav line already has the expected links.
 */
export const navLinksMatch = (
  content: string,
  prevFilename: string | undefined,
  nextFilename: string | undefined,
): boolean => {
  const expected = buildNavLine(prevFilename, nextFilename);
  return content.split("\n").some((line) => line === expected);
};

/**
 * Extract the date from an ai-blog post filename.
 * Returns the YYYY-MM-DD prefix or undefined if no date found.
 */
export const extractPostDate = (filename: string): string | undefined =>
  filename.match(/^(\d{4}-\d{2}-\d{2})/)?.[1];

// --- I/O Functions ---

/**
 * Read ai-blog post filenames sorted in chronological order (oldest first).
 */
export const readAiBlogPostFiles = (aiBlogDir: string): readonly string[] =>
  !fs.existsSync(aiBlogDir)
    ? []
    : fs.readdirSync(aiBlogDir)
        .filter((f) => f.endsWith(".md") && f !== "index.md" && f !== "AGENTS.md")
        .sort();

export interface NavLinkResult {
  readonly filename: string;
  readonly modified: boolean;
}

/**
 * Ensure all ai-blog posts have correct ⏮️/⏭️ navigation links.
 *
 * Scans all posts in chronological order, computes each post's expected
 * prev/next neighbors, and updates their nav lines if needed.
 *
 * Returns the list of filenames that were modified.
 */
export const ensureAllNavLinks = (aiBlogDir: string): readonly NavLinkResult[] => {
  const files = readAiBlogPostFiles(aiBlogDir);

  return files.map((filename, index) => {
    const prevFilename = index > 0 ? files[index - 1] : undefined;
    const nextFilename = index < files.length - 1 ? files[index + 1] : undefined;

    const filePath = path.join(aiBlogDir, filename);
    const content = fs.readFileSync(filePath, "utf-8");

    if (navLinksMatch(content, prevFilename, nextFilename)) {
      return { filename, modified: false };
    }

    const updated = updateNavLinks(content, prevFilename, nextFilename);
    if (updated !== content) {
      fs.writeFileSync(filePath, updated, "utf-8");
      return { filename, modified: true };
    }

    return { filename, modified: false };
  });
};

/**
 * Extract the title from a post file's frontmatter.
 * Falls back to the filename without extension.
 */
export const extractAiBlogTitle = (aiBlogDir: string, filename: string): string => {
  const filePath = path.join(aiBlogDir, filename);
  if (!fs.existsSync(filePath)) return filename.replace(/\.md$/, "");

  const content = fs.readFileSync(filePath, "utf-8");
  const { frontmatter } = parseFrontmatter(content);
  return (frontmatter["title"] as string) ?? filename.replace(/\.md$/, "");
};

/**
 * Build update links for ai-blog posts that were modified.
 * Returns an array suitable for addUpdateLinksToReflection.
 */
export const buildReflectionLinks = (
  aiBlogDir: string,
  modifiedResults: readonly NavLinkResult[],
): ReadonlyArray<{ readonly relativePath: string; readonly title: string; readonly date: string }> =>
  modifiedResults
    .filter((r) => r.modified)
    .map((r) => ({
      relativePath: `ai-blog/${r.filename}`,
      title: extractAiBlogTitle(aiBlogDir, r.filename),
      date: extractPostDate(r.filename) ?? "",
    }))
    .filter((link) => link.date !== "");
