/**
 * Daily Reflection Updates Section
 *
 * Adds an Updates section to the current daily reflection note with
 * wiki links to files modified by automated tasks (image backfill,
 * internal linking, social posting).
 *
 * This replaces the old "breadcrumb trail" strategy of updating the
 * `updated` frontmatter timestamp along every file in the BFS path.
 * Instead, the daily reflection directly links to modified files,
 * so Enveloppe discovers them in a single BFS hop when publishing.
 *
 * All pure functions operate on strings; I/O functions handle the filesystem.
 *
 * @module daily-updates
 */

import fs from "node:fs";
import path from "node:path";

import { parseFrontmatter } from "./frontmatter.ts";

// --- Constants ---

export const UPDATES_SECTION_HEADER = "## 🔄 Updates";

// --- Pure Functions (no I/O) ---

/**
 * Build a wiki link list item for the Updates section.
 * Strips `.md` extension from the relative path.
 */
export const buildUpdateLink = (relativePath: string, title: string): string =>
  `- [[${relativePath.replace(/\.md$/, "")}|${title}]]`;

/**
 * Add update links to a reflection note's content.
 * Creates the Updates section if it doesn't exist, or appends to it.
 *
 * Idempotent: skips links whose target path is already present.
 * Returns the updated content string.
 */
export const addUpdateLinks = (
  content: string,
  links: ReadonlyArray<{ readonly relativePath: string; readonly title: string }>,
): string => {
  const newLinks = links.filter(
    (link) => !content.includes(`[[${link.relativePath.replace(/\.md$/, "")}|`),
  );

  if (newLinks.length === 0) return content;

  const linkLines = newLinks.map((l) => buildUpdateLink(l.relativePath, l.title));

  if (content.includes(UPDATES_SECTION_HEADER)) {
    const lines = content.split("\n");
    const sectionIndex = lines.findIndex((l) => l.startsWith(UPDATES_SECTION_HEADER));
    let insertAt = sectionIndex + 1;
    // Skip blank line after header
    if (insertAt < lines.length && lines[insertAt]?.trim() === "") insertAt++;
    // Skip existing list items
    while (insertAt < lines.length && lines[insertAt]?.startsWith("- ")) {
      insertAt++;
    }
    return [...lines.slice(0, insertAt), ...linkLines, ...lines.slice(insertAt)].join("\n");
  }

  return `${content.trimEnd()}\n\n${UPDATES_SECTION_HEADER}\n\n${linkLines.join("\n")}\n`;
};

// --- I/O Functions ---

/**
 * Extract the title from a markdown file's frontmatter.
 * Falls back to the filename (without extension) if no title is found.
 */
export const extractTitleFromFile = (filePath: string): string => {
  if (!fs.existsSync(filePath)) return path.basename(filePath, ".md");

  const content = fs.readFileSync(filePath, "utf-8");
  const { frontmatter } = parseFrontmatter(content);
  return frontmatter["title"] || path.basename(filePath, ".md");
};

/**
 * Add update links to the current daily reflection file.
 * No-op if the reflection file doesn't exist or no new links are needed.
 *
 * @returns true if the reflection was modified
 */
export const addUpdateLinksToReflection = (
  reflectionsDir: string,
  date: string,
  links: ReadonlyArray<{ readonly relativePath: string; readonly title: string }>,
): boolean => {
  if (links.length === 0) return false;

  const reflectionPath = path.join(reflectionsDir, `${date}.md`);
  if (!fs.existsSync(reflectionPath)) {
    console.log(`  ⚠️  No reflection for ${date}, skipping update links`);
    return false;
  }

  const content = fs.readFileSync(reflectionPath, "utf-8");
  const updated = addUpdateLinks(content, links);

  if (updated === content) return false;

  fs.writeFileSync(reflectionPath, updated, "utf-8");
  const linkPaths = links.map((l) => l.relativePath).join(", ");
  console.log(`  🔄 Added update link(s) to ${date} reflection: ${linkPaths}`);
  return true;
};
