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
 * The BFS starts at the most recent reflection and follows both standard
 * markdown links and Obsidian wiki links. Since reflections form a doubly
 * linked list (each links to previous/next), the BFS naturally traverses
 * the full chain of reflections and all content linked from them.
 *
 * It skips index pages and the home page, only returning pages with actual
 * content that are missing social media embeds for at least one configured
 * platform.
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
  /**
   * Shortest path from the BFS root (most recent reflection) to this note.
   * Each element is a relative path (e.g. "reflections/2026-03-08.md").
   * The first element is the BFS root, the last is this note.
   *
   * Used to update the "updated" frontmatter timestamp along the path,
   * creating a trail of modified files that Enveloppe can follow when
   * publishing from Obsidian mobile.
   */
  readonly pathFromRoot: readonly string[];
}

/** Configuration for the BFS content finder */
export interface FindContentConfig {
  /** Root content directory (absolute path) */
  readonly contentDir: string;
  /** Platforms to find content for (only those with configured credentials) */
  readonly platforms: readonly Platform[];
  /** UTC hour at which reflections become eligible for posting the next day (default: 17 = 9 AM PST) */
  readonly postingHourUTC?: number;
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
 * Extract link targets from note content.
 *
 * Handles two link formats:
 * 1. Standard markdown links: `[text](../path/to/file.md)` — resolved relative to the current file
 * 2. Obsidian wiki links: `[[path/to/file]]` or `[[path/to/file|display text]]` — resolved from vault root
 *
 * The Obsidian vault (source of truth) uses wiki links natively.
 * The GitHub repo (published via Enveloppe) converts them to markdown links.
 * Supporting both formats ensures the BFS works regardless of which source is read.
 *
 * Only follows internal .md links; external URLs are ignored.
 */
export function extractMarkdownLinks(
  body: string,
  noteRelativePath: string,
  contentDir: string,
): readonly string[] {
  const noteDir = path.dirname(
    path.join(contentDir, noteRelativePath),
  );
  const links: string[] = [];
  const seen = new Set<string>();

  function addLink(relativePath: string): void {
    if (!relativePath.startsWith("..") && !seen.has(relativePath)) {
      seen.add(relativePath);
      links.push(relativePath);
    }
  }

  // 1. Standard markdown links: [text](path.md)
  const markdownLinkRegex = /\]\(([^)]+\.md)\)/g;
  let match: RegExpExecArray | null;
  while ((match = markdownLinkRegex.exec(body)) !== null) {
    const target = match[1] as string;

    // Skip external URLs
    if (target.startsWith("http://") || target.startsWith("https://")) {
      continue;
    }

    // Resolve relative path to absolute, then back to content-relative
    const absoluteTarget = path.resolve(noteDir, target);
    const relativePath = path.relative(contentDir, absoluteTarget);
    addLink(relativePath);
  }

  // 2. Obsidian wiki links: [[path]] or [[path|display text]] or [[path#heading]]
  // Regex breakdown:
  //   \[\[           — opening [[
  //   ([^\]|#]+)     — capture group 1: the link path (everything before #, |, or ]])
  //   (?:#[^\]|]*)?  — optional heading anchor (after #, before | or ]])
  //   (?:\|[^\]]+)?  — optional display text (after |, before ]])
  //   \]\]           — closing ]]
  const wikiLinkRegex = /\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]+)?\]\]/g;
  while ((match = wikiLinkRegex.exec(body)) !== null) {
    let target = (match[1] as string).trim();

    // Add .md extension if not present
    if (!target.endsWith(".md")) {
      target = target + ".md";
    }

    // Wiki links in Obsidian are typically relative to vault root.
    // If the target has a directory separator, treat as vault-root-relative.
    // If it's just a filename, try resolving relative to the current file's directory.
    if (target.includes("/")) {
      addLink(target);
    } else {
      // Filename-only wiki link — resolve relative to current file's directory
      const absoluteTarget = path.resolve(noteDir, target);
      const relativePath = path.relative(contentDir, absoluteTarget);
      addLink(relativePath);
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
 *
 * This is the single BFS seed — reflections form a doubly linked list
 * (each links to previous/next via wiki links), so starting from the
 * most recent reflection and following links eventually reaches all
 * reflections and all content linked from them.
 */
export function findMostRecentReflection(
  contentDir: string,
): string | null {
  const reflectionsDir = path.join(contentDir, "reflections");

  if (!fs.existsSync(reflectionsDir)) {
    return null;
  }

  const datePattern = /^\d{4}-\d{2}-\d{2}\.md$/;
  const files = fs
    .readdirSync(reflectionsDir)
    .filter((f) => datePattern.test(f))
    .sort()
    .reverse();

  return files.length > 0 ? `reflections/${files[0]}` : null;
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
 * Check if a reflection file is eligible for posting based on its date.
 *
 * A reflection from date D should not be posted until postingHourUTC on D+1.
 * For example, a reflection from 2026-03-08 with postingHourUTC=17 (9 AM PST)
 * is not eligible until 2026-03-09 at 17:00 UTC.
 *
 * Non-reflection files are always eligible (returns true).
 *
 * @param relativePath - Path relative to content root (e.g. "reflections/2026-03-08.md")
 * @param postingHourUTC - UTC hour when reflections become eligible (default: 17)
 * @param now - Current time (default: new Date(), injectable for testing)
 * @returns true if the note is eligible for posting
 */
export function isReflectionEligibleForPosting(
  relativePath: string,
  postingHourUTC: number = 17,
  now: Date = new Date(),
): boolean {
  const match = relativePath.match(/^reflections\/(\d{4}-\d{2}-\d{2})\.md$/);
  if (!match) return true; // Not a reflection — always eligible

  const reflectionDate = match[1]!;
  // A reflection from date D should not be posted until postingHourUTC on D+1
  const eligibleAfter = new Date(reflectionDate + "T00:00:00Z");
  eligibleAfter.setUTCDate(eligibleAfter.getUTCDate() + 1);
  eligibleAfter.setUTCHours(postingHourUTC, 0, 0, 0);

  return now >= eligibleAfter;
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
 * Reconstruct the shortest path from the BFS root to a target node
 * using the parent map built during BFS traversal.
 *
 * @param target - The target node's relative path
 * @param parentMap - Map from each visited node to its parent (null for root)
 * @returns Array of relative paths from root to target, inclusive
 */
export function reconstructPath(
  target: string,
  parentMap: ReadonlyMap<string, string | null>,
): readonly string[] {
  const path: string[] = [];
  let current: string | null = target;

  while (current !== null) {
    path.unshift(current);
    const parent = parentMap.get(current);
    if (parent === undefined) break; // not in map — shouldn't happen
    current = parent;
  }

  return path;
}

/**
 * Update the "updated" property in the frontmatter of a markdown file.
 *
 * This sets the "updated" field to the given ISO 8601 timestamp, creating
 * the field if it doesn't exist. If the file has no frontmatter block,
 * one is added.
 *
 * Used to create a trail of modified files along the BFS path so that
 * Enveloppe (running from Obsidian mobile) follows the chain of modified
 * files when publishing the daily reflection.
 *
 * @param filePath - Absolute path to the markdown file
 * @param timestamp - ISO 8601 timestamp string (e.g. "2026-03-10T00:01:08.852Z")
 */
export function updateFrontmatterTimestamp(
  filePath: string,
  timestamp: string,
): void {
  if (!fs.existsSync(filePath)) {
    return;
  }

  let content = fs.readFileSync(filePath, "utf-8");
  const lines = content.split("\n");

  if (lines[0]?.trim() === "---") {
    // File has frontmatter — find the closing ---
    let endIndex = -1;
    let updatedLineIndex = -1;

    for (let i = 1; i < lines.length; i++) {
      if (lines[i]?.trim() === "---") {
        endIndex = i;
        break;
      }
      if (lines[i]?.match(/^updated:\s/)) {
        updatedLineIndex = i;
      }
    }

    if (endIndex >= 0) {
      if (updatedLineIndex >= 0) {
        // Replace existing "updated" line
        lines[updatedLineIndex] = `updated: ${timestamp}`;
      } else {
        // Insert "updated" before the closing ---
        lines.splice(endIndex, 0, `updated: ${timestamp}`);
      }
      content = lines.join("\n");
    }
  } else {
    // No frontmatter — add a minimal block
    content = `---\nupdated: ${timestamp}\n---\n${content}`;
  }

  fs.writeFileSync(filePath, content, "utf-8");
}

/**
 * Update the "updated" frontmatter timestamp for all files along a BFS path.
 *
 * This creates a trail of modified files from the daily reflection to the
 * note that was posted to social media. When the user publishes the daily
 * reflection from Obsidian mobile via Enveloppe, the plugin's BFS will
 * follow the chain of files with recently modified "updated" timestamps
 * and ultimately reach the posted note with its new embeds.
 *
 * @param pathFromRoot - Array of relative paths from root to target (from reconstructPath)
 * @param contentDir - Root content directory (absolute path)
 * @param timestamp - ISO 8601 timestamp to set (default: current time)
 */
export function updatePathTimestamps(
  pathFromRoot: readonly string[],
  contentDir: string,
  timestamp: string = new Date().toISOString(),
): void {
  for (const relativePath of pathFromRoot) {
    const filePath = path.join(contentDir, relativePath);
    updateFrontmatterTimestamp(filePath, timestamp);
    console.log(`🕐 Updated "updated" timestamp: ${relativePath}`);
  }
}

/**
 * Breadth-first search across the content graph to find notes that
 * haven't been posted to all configured platforms.
 *
 * Seeds the BFS from the most recent reflection. Since reflections form
 * a doubly linked list (each links to previous/next via wiki links),
 * the BFS naturally traverses the full chain. Each reflection also links
 * to the content consumed that day (books, videos, articles, etc.),
 * so the BFS covers the full content graph from a single entry point.
 *
 * The BFS follows both standard markdown links and Obsidian wiki links,
 * ensuring it works whether reading from the vault (wiki links) or the
 * repo (markdown links).
 *
 * Skips index/home pages and reflections that are too recent to post.
 * Returns up to one note per platform that still needs posting.
 *
 * A reflection from date D is not eligible for posting until
 * postingHourUTC on D+1 (e.g., 9 AM Pacific the next day).
 *
 * Tracks parent pointers to reconstruct the shortest path from the BFS
 * root to each discovered note. This path is included in the results so
 * that callers can update the "updated" frontmatter timestamp along the
 * path, creating a trail for Enveloppe to follow.
 *
 * @returns Array of content-to-post items, at most one per platform.
 */
export function bfsContentDiscovery(
  config: FindContentConfig,
): readonly ContentToPost[] {
  const { contentDir, platforms } = config;
  const postingHourUTC = config.postingHourUTC ?? 17;

  // Seed from the most recent reflection.
  // Reflections form a doubly linked list (each links to previous/next),
  // so starting from the most recent and following wiki links reaches
  // all reflections and all content linked from them.
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

  // Parent map for shortest-path reconstruction.
  // Maps each visited node to its BFS parent (null for root).
  const parentMap = new Map<string, string | null>();
  parentMap.set(startPath, null);

  console.log(`🔍 Starting BFS from: ${startPath}`);
  console.log(
    `📋 Looking for content for: ${[...platformsNeedingContent].join(", ")}`,
  );

  while (queue.length > 0 && platformsNeedingContent.size > 0) {
    const currentPath = queue.shift();
    if (!currentPath) continue;

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
      // Skip reflections that are too recent to post (must wait until 9am next day)
      if (!isReflectionEligibleForPosting(note.relativePath, postingHourUTC)) {
        const dateMatch = note.relativePath.match(/(\d{4}-\d{2}-\d{2})/);
        const eligibleDate = dateMatch ? (() => {
          const d = new Date(dateMatch[1] + "T00:00:00Z");
          d.setUTCDate(d.getUTCDate() + 1);
          return d.toISOString().split("T")[0];
        })() : "the next day";
        console.log(
          `⏳ Reflection too recent to post: ${note.relativePath} (eligible after ${eligibleDate} ${postingHourUTC}:00 UTC)`,
        );
      } else {
        // Reconstruct path once for this note (shared across platforms)
        const pathFromRoot = reconstructPath(note.relativePath, parentMap);

        // Check each platform that still needs content
        for (const platform of [...platformsNeedingContent]) {
          if (!note.postedPlatforms.has(platform)) {
            results.push({ platform, note, pathFromRoot });
            platformsNeedingContent.delete(platform);
            console.log(
              `✅ Found content for ${platform}: ${note.title} (${note.relativePath})`,
            );
          }
        }

        if (results.some((r) => r.note.relativePath === note.relativePath)) {
          console.log(
            `  🗺️ Path from root (${pathFromRoot.length} hops): ${pathFromRoot.join(" → ")}`,
          );
        }
      }
    }

    // Enqueue linked notes (BFS expansion) — always follow links,
    // even from reflections that are too recent to post
    for (const linkedPath of note.linkedNotePaths) {
      if (!visited.has(linkedPath)) {
        // Record parent pointer only for the first time we see this path
        // (BFS guarantees shortest path for unweighted graphs)
        if (!parentMap.has(linkedPath)) {
          parentMap.set(linkedPath, currentPath);
        }
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
 *    (Reflections form a doubly linked list, so BFS from the latest reaches all content.)
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
      // Return this note for all platforms that haven't posted it yet.
      // The path is just the reflection itself (it's the root).
      const pathFromRoot = [priorDayReflection.relativePath];
      return platforms
        .filter((p) => !priorDayReflection.postedPlatforms.has(p))
        .map((platform) => ({ platform, note: priorDayReflection, pathFromRoot }));
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
