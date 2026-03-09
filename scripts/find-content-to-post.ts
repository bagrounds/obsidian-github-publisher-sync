/**
 * BFS Content Discovery for Social Media Posting
 *
 * Performs breadth-first search across linked notes starting from the most
 * recent reflection, finding content that hasn't been posted to social media.
 *
 * Design principles:
 * - Pure functions where possible (functional/declarative style)
 * - Strong static types (TypeScript interfaces for all data)
 * - Unix philosophy: one module, one job (find content to post)
 * - Domain-driven: models the note graph as a domain concept
 *
 * The BFS starts at the most recent reflection and follows markdown links
 * to discover connected notes. It skips index pages and the home page,
 * only returning pages with actual content that are missing social media
 * embeds for at least one configured platform.
 *
 * @module find-content-to-post
 */

import fs from "node:fs";
import path from "node:path";

// --- Types ---

/** The social media platforms we support */
export type Platform = "twitter" | "bluesky" | "mastodon";

/** All supported platforms */
export const ALL_PLATFORMS: readonly Platform[] = [
  "twitter",
  "bluesky",
  "mastodon",
] as const;

/** Section headers that indicate a platform has already been posted to */
export const PLATFORM_SECTION_HEADERS: Record<Platform, string> = {
  twitter: "## 🐦 Tweet",
  bluesky: "## 🦋 Bluesky",
  mastodon: "## 🐘 Mastodon",
};

/** A note in the content graph */
export interface ContentNote {
  /** Absolute file path */
  readonly filePath: string;
  /** Relative path from content root (e.g. "reflections/2026-03-08.md") */
  readonly relativePath: string;
  /** Note title from frontmatter */
  readonly title: string;
  /** URL from frontmatter */
  readonly url: string;
  /** Raw markdown body (after frontmatter) */
  readonly body: string;
  /** Which platforms this note has already been posted to */
  readonly postedPlatforms: ReadonlySet<Platform>;
  /** Relative paths of linked notes (outgoing edges in the graph) */
  readonly linkedNotePaths: readonly string[];
}

/** Result of BFS content discovery for a single platform */
export interface ContentToPost {
  /** The platform to post to */
  readonly platform: Platform;
  /** The note to post */
  readonly note: ContentNote;
}

/** Configuration for the BFS content finder */
export interface FindContentConfig {
  /** Root content directory (absolute path) */
  readonly contentDir: string;
  /** Platforms to find content for (only those with configured credentials) */
  readonly platforms: readonly Platform[];
}

// --- Pure Functions ---

/**
 * Parse frontmatter from markdown content.
 * Returns key-value pairs and the body after frontmatter.
 */
export function parseFrontmatter(content: string): {
  readonly frontmatter: Readonly<Record<string, string>>;
  readonly body: string;
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
 * Determine whether a relative path is an index page or home page.
 * These are excluded from social posting since they aggregate content
 * rather than containing standalone content.
 */
export function isIndexOrHomePage(relativePath: string): boolean {
  const basename = path.basename(relativePath);
  return basename === "index.md";
}

/**
 * Extract markdown link targets from note content.
 * Matches patterns like [text](../path/to/file.md) and returns
 * the resolved relative paths from the content root.
 *
 * Only follows internal .md links; external URLs are ignored.
 */
export function extractMarkdownLinks(
  body: string,
  noteRelativePath: string,
  contentDir: string,
): readonly string[] {
  const linkRegex = /\]\(([^)]+\.md)\)/g;
  const noteDir = path.dirname(
    path.join(contentDir, noteRelativePath),
  );
  const links: string[] = [];
  const seen = new Set<string>();

  let match: RegExpExecArray | null;
  while ((match = linkRegex.exec(body)) !== null) {
    const target = match[1] as string;

    // Skip external URLs
    if (target.startsWith("http://") || target.startsWith("https://")) {
      continue;
    }

    // Resolve relative path to absolute, then back to content-relative
    const absoluteTarget = path.resolve(noteDir, target);
    const relativePath = path.relative(contentDir, absoluteTarget);

    // Skip paths that resolve outside the content directory
    if (relativePath.startsWith("..")) {
      continue;
    }

    if (!seen.has(relativePath)) {
      seen.add(relativePath);
      links.push(relativePath);
    }
  }

  return links;
}

/**
 * Detect which platforms a note has already been posted to
 * by checking for the presence of section headers.
 */
export function detectPostedPlatforms(content: string): ReadonlySet<Platform> {
  const posted = new Set<Platform>();
  for (const platform of ALL_PLATFORMS) {
    if (content.includes(PLATFORM_SECTION_HEADERS[platform])) {
      posted.add(platform);
    }
  }
  return posted;
}

/**
 * Read and parse a single content note.
 * Returns null if the file doesn't exist or can't be read.
 */
export function readContentNote(
  relativePath: string,
  contentDir: string,
): ContentNote | null {
  const filePath = path.join(contentDir, relativePath);

  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    const content = fs.readFileSync(filePath, "utf-8");
    const { frontmatter, body } = parseFrontmatter(content);

    // Derive URL from frontmatter or from the relative path
    const slug = relativePath.replace(/\.md$/, "");
    const url = frontmatter["URL"] || `https://bagrounds.org/${slug}`;

    return {
      filePath,
      relativePath,
      title: frontmatter["title"] || path.basename(relativePath, ".md"),
      url,
      body,
      postedPlatforms: detectPostedPlatforms(content),
      linkedNotePaths: extractMarkdownLinks(body, relativePath, contentDir),
    };
  } catch {
    return null;
  }
}

/**
 * Check if a note has meaningful content worth posting.
 * Excludes index pages, very short notes, and notes without a title.
 */
export function isPostableContent(note: ContentNote): boolean {
  // Skip index / home pages
  if (isIndexOrHomePage(note.relativePath)) {
    return false;
  }

  // Must have a non-empty body with some substance
  // (at least a heading + some content)
  const strippedBody = note.body
    .replace(/\[Home\].*\n?/g, "")
    .replace(/^#.*\n?/gm, "")
    .trim();

  return strippedBody.length > 50;
}

/**
 * Find the most recent reflection file by scanning the reflections directory
 * for date-named files and returning the latest one.
 */
export function findMostRecentReflection(
  contentDir: string,
): string | null {
  const reflectionsDir = path.join(contentDir, "reflections");

  if (!fs.existsSync(reflectionsDir)) {
    return null;
  }

  const datePattern = /^\d{4}-\d{2}-\d{2}\.md$/;
  const reflectionFiles = fs
    .readdirSync(reflectionsDir)
    .filter((f) => datePattern.test(f))
    .sort()
    .reverse();

  if (reflectionFiles.length === 0) {
    return null;
  }

  return `reflections/${reflectionFiles[0]}`;
}

/**
 * Get yesterday's date in YYYY-MM-DD format (UTC).
 */
export function getYesterdayDate(): string {
  const now = new Date();
  now.setUTCDate(now.getUTCDate() - 1);
  return now.toISOString().split("T")[0] as string;
}

/**
 * Check if the prior day's reflection still needs posting on any of the
 * given platforms.
 *
 * @returns The reflection note if it needs posting, null otherwise.
 */
export function getPriorDayReflectionIfNeeded(
  config: FindContentConfig,
): ContentNote | null {
  const yesterday = getYesterdayDate();
  const relativePath = `reflections/${yesterday}.md`;
  const note = readContentNote(relativePath, config.contentDir);

  if (!note) {
    return null;
  }

  // Check if any platform still needs posting
  const needsPosting = config.platforms.some(
    (p) => !note.postedPlatforms.has(p),
  );

  return needsPosting ? note : null;
}

/**
 * Breadth-first search across the content graph to find notes that
 * haven't been posted to all configured platforms.
 *
 * Starts from the most recent reflection and follows markdown links.
 * Skips index/home pages and returns up to one note per platform
 * that still needs posting.
 *
 * @returns Array of content-to-post items, at most one per platform.
 */
export function bfsContentDiscovery(
  config: FindContentConfig,
): readonly ContentToPost[] {
  const { contentDir, platforms } = config;

  // Find starting point
  const startPath = findMostRecentReflection(contentDir);
  if (!startPath) {
    console.log("📭 No reflections found to start BFS from");
    return [];
  }

  // Track which platforms still need a post
  const platformsNeedingContent = new Set<Platform>(platforms);

  // BFS state
  const visited = new Set<string>();
  const queue: string[] = [startPath];
  const results: ContentToPost[] = [];

  console.log(`🔍 Starting BFS from: ${startPath}`);
  console.log(
    `📋 Looking for content for: ${[...platformsNeedingContent].join(", ")}`,
  );

  while (queue.length > 0 && platformsNeedingContent.size > 0) {
    const currentPath = queue.shift()!;

    if (visited.has(currentPath)) {
      continue;
    }
    visited.add(currentPath);

    const note = readContentNote(currentPath, contentDir);
    if (!note) {
      continue;
    }

    // Check if this note is postable content (not an index page)
    if (isPostableContent(note)) {
      // Check each platform that still needs content
      for (const platform of [...platformsNeedingContent]) {
        if (!note.postedPlatforms.has(platform)) {
          results.push({ platform, note });
          platformsNeedingContent.delete(platform);
          console.log(
            `✅ Found content for ${platform}: ${note.title} (${note.relativePath})`,
          );
        }
      }
    }

    // Enqueue linked notes (BFS expansion)
    for (const linkedPath of note.linkedNotePaths) {
      if (!visited.has(linkedPath)) {
        queue.push(linkedPath);
      }
    }
  }

  if (platformsNeedingContent.size > 0) {
    console.log(
      `📝 No unposted content found for: ${[...platformsNeedingContent].join(", ")}`,
    );
    if (results.length === 0) {
      console.log(
        `🎉 All reachable published notes have been posted to all platforms! Time to create more content! 🖊️`,
      );
    }
  }

  console.log(`🔍 BFS visited ${visited.size} notes, found ${results.length} post(s)`);
  return results;
}

/**
 * Main content discovery function.
 *
 * Strategy:
 * 1. If the prior day's reflection hasn't been posted, return that for all platforms.
 * 2. Otherwise, use BFS from the most recent reflection to find unposted content.
 * 3. Returns at most one note per platform.
 *
 * @param config - Content directory and platforms to discover for
 * @param isPastPostingHour - Whether we're past the daily reflection posting hour (e.g. 9am)
 * @returns Array of content items to post, at most one per platform
 */
export function discoverContentToPost(
  config: FindContentConfig,
  isPastPostingHour: boolean,
): readonly ContentToPost[] {
  const { platforms } = config;

  if (platforms.length === 0) {
    console.log("⚠️ No platforms configured, nothing to discover");
    return [];
  }

  // Priority 1: Prior day's reflection (if past posting hour and not yet posted)
  if (isPastPostingHour) {
    const priorDayReflection = getPriorDayReflectionIfNeeded(config);
    if (priorDayReflection) {
      console.log(
        `📅 Prior day's reflection needs posting: ${priorDayReflection.title}`,
      );
      // Return this note for all platforms that haven't posted it yet
      return platforms
        .filter((p) => !priorDayReflection.postedPlatforms.has(p))
        .map((platform) => ({ platform, note: priorDayReflection }));
    }
    console.log(`✅ Prior day's reflection already posted on all platforms`);
  }

  // Priority 2: BFS discovery of unposted content
  return bfsContentDiscovery(config);
}

/**
 * Check if the current UTC hour is past the configured posting hour.
 * Used to determine whether to prioritize the prior day's reflection.
 */
export function isPastPostingHourUTC(postingHourUTC: number = 17): boolean {
  return new Date().getUTCHours() >= postingHourUTC;
}
