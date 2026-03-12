/**
 * Blog series infrastructure.
 *
 * Defines extensible blog series configurations and provides utilities
 * for reading previous posts, generating index files, and reading
 * Giscus comments (via GitHub Discussions GraphQL API) for context.
 *
 * Comments are sourced from Giscus, which maps each page's pathname
 * to a GitHub Discussion in the Announcements category. The GraphQL API
 * is used to fetch discussion replies for posts in each series.
 *
 * To add a new automated blog series:
 * 1. Add a new entry to BLOG_SERIES below
 * 2. Create a directory in the repo root with the series id
 * 3. Create an AGENTS.md in that directory defining the blog's style
 * 4. Create a GitHub Actions workflow (copy an existing one)
 * 5. Write the first post manually (or let the workflow generate it)
 *
 * @module blog-series
 */

import fs from "node:fs";
import path from "node:path";
import { parseFrontmatter } from "./frontmatter.ts";

// --- Types ---

export interface BlogSeriesConfig {
  /** Unique identifier, also the directory name in the repo and vault. */
  readonly id: string;
  /** Human-readable display name. */
  readonly name: string;
  /** Emoji icon for the series. */
  readonly icon: string;
  /** Author wiki-link for Obsidian. */
  readonly author: string;
  /** Base URL for the series on the website. */
  readonly baseUrl: string;
  /** Default tags applied to every post in the series. */
  readonly defaultTags: readonly string[];
  /** GitHub username whose comments get priority. Empty = use BLOG_PRIORITY_USER env var. */
  readonly defaultPriorityUser: string;
}

export interface BlogPost {
  readonly filename: string;
  readonly date: string;
  readonly title: string;
  readonly body: string;
  readonly tags: readonly string[];
}

export interface BlogComment {
  readonly author: string;
  readonly body: string;
  readonly createdAt: string;
  readonly isPriority: boolean;
}

export interface BlogContext {
  readonly series: BlogSeriesConfig;
  readonly agentsMd: string;
  readonly previousPosts: readonly BlogPost[];
  readonly comments: readonly BlogComment[];
  readonly today: string;
}

// --- Series Definitions ---

const AUTO_BLOG_ZERO: BlogSeriesConfig = {
  id: "auto-blog-zero",
  name: "Auto Blog Zero",
  icon: "🤖",
  author: "[[auto-blog-zero]]",
  baseUrl: "https://bagrounds.org/auto-blog-zero",
  defaultTags: ["ai-generated", "auto-blog-zero"],
  defaultPriorityUser: "bagrounds",
};

const CHICKIE_LOO: BlogSeriesConfig = {
  id: "chickie-loo",
  name: "Chickie Loo",
  icon: "🐔",
  author: "[[chickie-loo]]",
  baseUrl: "https://bagrounds.org/chickie-loo",
  defaultTags: ["ai-generated", "chickie-loo", "ranch-life"],
  defaultPriorityUser: "",
};

/**
 * Registry of all blog series. Add new series here.
 */
export const BLOG_SERIES: ReadonlyMap<string, BlogSeriesConfig> = new Map([
  [AUTO_BLOG_ZERO.id, AUTO_BLOG_ZERO],
  [CHICKIE_LOO.id, CHICKIE_LOO],
]);

// --- Post Reading ---

/**
 * Read the AGENTS.md file for a series. Returns the file contents, or
 * a fallback message if the file doesn't exist.
 */
export function readAgentsMd(seriesDir: string): string {
  const agentsPath = path.join(seriesDir, "AGENTS.md");
  if (fs.existsSync(agentsPath)) {
    return fs.readFileSync(agentsPath, "utf-8");
  }
  return "";
}

/**
 * Read all blog posts from a series directory, sorted by date (newest first).
 */
export function readSeriesPosts(seriesDir: string): BlogPost[] {
  if (!fs.existsSync(seriesDir)) return [];

  const files = fs.readdirSync(seriesDir)
    .filter((f) => f.endsWith(".md") && f !== "index.md" && f !== "AGENTS.md")
    .sort()
    .reverse();

  return files.map((filename) => {
    const content = fs.readFileSync(path.join(seriesDir, filename), "utf-8");
    const { frontmatter, body } = parseFrontmatter(content);

    const dateMatch = filename.match(/^(\d{4}-\d{2}-\d{2})/);
    const date = dateMatch ? dateMatch[1] as string : "";

    const tagsRaw = content.match(/^tags:\s*\n((?:\s+-\s+.*\n)*)/m);
    const tags = tagsRaw
      ? tagsRaw[1]!.split("\n").map((l) => l.replace(/^\s*-\s*/, "").trim()).filter(Boolean)
      : [];

    return {
      filename,
      date,
      title: frontmatter["title"] || filename.replace(/\.md$/, ""),
      body,
      tags,
    };
  });
}

/**
 * Build context for generating the next blog post in a series.
 *
 * @param seriesId - The blog series identifier
 * @param repoRoot - Path to the repository root
 * @param comments - Pre-fetched comments (from Giscus/GitHub Discussions)
 * @param today - Today's date in YYYY-MM-DD format
 */
export function buildBlogContext(
  seriesId: string,
  repoRoot: string,
  comments: readonly BlogComment[],
  today: string,
): BlogContext {
  const series = BLOG_SERIES.get(seriesId);
  if (!series) {
    throw new Error(`Unknown blog series: ${seriesId}. Available: ${[...BLOG_SERIES.keys()].join(", ")}`);
  }

  const seriesDir = path.join(repoRoot, series.id);
  const previousPosts = readSeriesPosts(seriesDir);
  const agentsMd = readAgentsMd(seriesDir);

  return { series, agentsMd, previousPosts, comments, today };
}

// --- Prompt Building ---

/** Maximum number of full posts to include as context. */
const MAX_FULL_POSTS = 5;

/**
 * Build the Gemini prompt for generating a new blog post.
 *
 * Returns { system, user } prompt pair compatible with Gemini API.
 */
export function buildBlogPrompt(context: BlogContext): { system: string; user: string } {
  const { series, agentsMd, previousPosts, comments, today } = context;

  // Build post history section
  let postHistory = "";
  if (previousPosts.length > 0) {
    const fullPosts = previousPosts.slice(0, MAX_FULL_POSTS);
    const titleOnly = previousPosts.slice(MAX_FULL_POSTS);

    postHistory += "\n\n## Previous Posts (most recent first)\n";

    for (const post of fullPosts) {
      postHistory += `\n### ${post.title} (${post.date})\n`;
      // Truncate very long posts to save tokens
      const truncatedBody = post.body.length > 3000
        ? post.body.slice(0, 3000) + "\n\n[...truncated...]"
        : post.body;
      postHistory += truncatedBody + "\n";
    }

    if (titleOnly.length > 0) {
      postHistory += "\n### Older posts (titles only)\n";
      for (const post of titleOnly) {
        postHistory += `- ${post.title} (${post.date})\n`;
      }
    }
  }

  // Build comments section
  let commentsSection = "";
  if (comments.length > 0) {
    // Sort priority comments first
    const sorted = [...comments].sort((a, b) => {
      if (a.isPriority && !b.isPriority) return -1;
      if (!a.isPriority && b.isPriority) return 1;
      return 0;
    });

    commentsSection += "\n\n## Reader Comments (from Giscus/GitHub Discussions)\n";
    for (const c of sorted) {
      const priority = c.isPriority ? " ⭐ PRIORITY" : "";
      commentsSection += `\n**${c.author}**${priority} (${c.createdAt}):\n${c.body}\n`;
    }
  }

  // Use AGENTS.md as the system prompt, with a minimal fallback
  const system = agentsMd || `You are ${series.name}, an automated blog. Write a blog post.`;

  const user = `Write a new blog post for today, ${today}.

${postHistory}${commentsSection}

## Instructions

Write the COMPLETE blog post in markdown format, including frontmatter.

The frontmatter MUST follow this exact format:
\`\`\`
---
share: true
aliases:
  - ${today} | ${series.icon} [Your Title Here] ${series.icon}
title: ${today} | ${series.icon} [Your Title Here] ${series.icon}
URL: ${series.baseUrl}/${today}-[slug]
Author: "${series.author}"
tags:
${series.defaultTags.map((t) => `  - ${t}`).join("\n")}
  - [add 2-4 topic-specific tags]
---
\`\`\`

After the frontmatter, start with:
\`\`\`
# ${today} | ${series.icon} [Your Title Here] ${series.icon}
\`\`\`

${previousPosts.length === 0
    ? "This is the FIRST post in the series. Introduce yourself and set the tone."
    : "Continue the series naturally. Reference previous posts where relevant using relative links like [title](./filename.md)."}

${comments.length > 0
    ? "Address reader comments naturally in your post. Don't force it — only incorporate what fits."
    : "No reader comments yet. Write based on the series theme and previous content."}

Write ONLY the markdown content. Do not wrap in code blocks. Start with the --- frontmatter delimiter.`;

  return { system, user };
}

// --- Index Generation ---

/**
 * Generate an index.md file for a blog series using a dataview query.
 * The dataview query dynamically lists all posts in the folder, sorted
 * newest first. This matches how other index pages work in the vault.
 */
export function generateSeriesIndex(
  series: BlogSeriesConfig,
  _posts: readonly BlogPost[],
): string {
  const lines: string[] = [
    "---",
    "share: true",
    "aliases:",
    `  - ${series.icon} ${series.name}`,
    `title: ${series.icon} ${series.name}`,
    `URL: ${series.baseUrl}/index`,
    `Author: "${series.author}"`,
    "backlinks: false",
    `updated: ${new Date().toISOString().split("T")[0]}`,
    "---",
    `[Home](../index.md)  `,
    `# ${series.icon} ${series.name}  `,
    "```dataview",
    `LIST FROM "${series.id}"`,
    `WHERE file.name != "index" AND file.name != "AGENTS"`,
    "SORT file.name DESC",
    "```",
  ];

  return lines.join("\n") + "\n";
}

// --- Post Frontmatter Parsing ---

/**
 * Extract the slug from a blog post filename.
 * e.g., "2026-03-12-fully-automated-blogging.md" → "fully-automated-blogging"
 */
export function extractSlug(filename: string): string {
  return filename.replace(/\.md$/, "").replace(/^\d{4}-\d{2}-\d{2}-?/, "");
}

/**
 * Parse a Gemini-generated blog post, extracting frontmatter and validating structure.
 * Returns null if the post is malformed.
 */
export function parseGeneratedPost(raw: string): { content: string; title: string } | null {
  const trimmed = raw.trim();

  // Must start with frontmatter
  if (!trimmed.startsWith("---")) return null;

  // Must have closing frontmatter delimiter
  const endIdx = trimmed.indexOf("---", 3);
  if (endIdx < 0) return null;

  // Extract title from frontmatter
  const titleMatch = trimmed.match(/^title:\s*(.+)$/m);
  if (!titleMatch) return null;

  // Basic length check — posts should be substantial
  if (trimmed.length < 500) return null;

  return {
    content: trimmed,
    title: titleMatch[1]!.trim(),
  };
}

// --- Giscus / GitHub Discussions Comments ---

/** Giscus configuration matching quartz.layout.ts. */
const GISCUS_REPO_OWNER = "bagrounds";
const GISCUS_REPO_NAME = "obsidian-github-publisher-sync";
const GISCUS_CATEGORY_ID = "DIC_kwDOLuWiLM4Ckd0H";

/**
 * GraphQL response types for GitHub Discussions.
 */
interface GqlDiscussionComment {
  body: string;
  author: { login: string } | null;
  createdAt: string;
}

interface GqlDiscussion {
  title: string;
  comments: {
    nodes: GqlDiscussionComment[];
  };
}

interface GqlSearchResult {
  data?: {
    search: {
      nodes: GqlDiscussion[];
    };
  };
  errors?: Array<{ message: string }>;
}

/**
 * Fetch comments from Giscus (GitHub Discussions) for a specific page pathname.
 *
 * Giscus maps each page to a discussion using strict pathname matching.
 * E.g., a post at /auto-blog-zero/2026-03-12-my-post maps to a discussion
 * whose title is "auto-blog-zero/2026-03-12-my-post".
 *
 * Uses the GitHub GraphQL API to search for discussions by title.
 */
export async function fetchGiscusComments(
  pathname: string,
  priorityUser: string,
): Promise<BlogComment[]> {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    console.log("ℹ️  No GITHUB_TOKEN, skipping Giscus comment fetch");
    return [];
  }

  const query = `query($searchQuery: String!) {
    search(type: DISCUSSION, query: $searchQuery, first: 1) {
      nodes {
        ... on Discussion {
          title
          comments(first: 100) {
            nodes {
              body
              author { login }
              createdAt
            }
          }
        }
      }
    }
  }`;

  const searchQuery = `repo:${GISCUS_REPO_OWNER}/${GISCUS_REPO_NAME} in:title "${pathname}"`;

  try {
    const response = await fetch("https://api.github.com/graphql", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query, variables: { searchQuery } }),
    });

    if (!response.ok) {
      console.warn(`⚠️  GraphQL request failed: ${response.status}`);
      return [];
    }

    const result = (await response.json()) as GqlSearchResult;

    if (result.errors) {
      console.warn(`⚠️  GraphQL errors: ${result.errors.map((e) => e.message).join(", ")}`);
      return [];
    }

    const discussions = result.data?.search?.nodes ?? [];
    if (discussions.length === 0) return [];

    // Take the first matching discussion
    const discussion = discussions[0]!;
    const comments = discussion.comments?.nodes ?? [];

    return comments.map((c) => ({
      author: c.author?.login || "unknown",
      body: c.body,
      createdAt: c.createdAt.split("T")[0] as string,
      isPriority: priorityUser !== "" && c.author?.login === priorityUser,
    }));
  } catch (error) {
    console.warn(`⚠️  Error fetching Giscus comments: ${error instanceof Error ? error.message : error}`);
    return [];
  }
}

/**
 * Fetch all Giscus comments across all posts in a blog series.
 *
 * Aggregates comments from all discussions whose titles match the series
 * URL prefix (e.g., "auto-blog-zero/").
 */
export async function fetchAllSeriesComments(
  seriesId: string,
  priorityUser: string,
): Promise<BlogComment[]> {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    console.log("ℹ️  No GITHUB_TOKEN, skipping Giscus series comment fetch");
    return [];
  }

  const query = `query($searchQuery: String!) {
    search(type: DISCUSSION, query: $searchQuery, first: 50) {
      nodes {
        ... on Discussion {
          title
          comments(first: 50) {
            nodes {
              body
              author { login }
              createdAt
            }
          }
        }
      }
    }
  }`;

  const searchQuery = `repo:${GISCUS_REPO_OWNER}/${GISCUS_REPO_NAME} in:title "${seriesId}/"`;

  try {
    const response = await fetch("https://api.github.com/graphql", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query, variables: { searchQuery } }),
    });

    if (!response.ok) {
      console.warn(`⚠️  GraphQL request failed: ${response.status}`);
      return [];
    }

    const result = (await response.json()) as GqlSearchResult;

    if (result.errors) {
      console.warn(`⚠️  GraphQL errors: ${result.errors.map((e) => e.message).join(", ")}`);
      return [];
    }

    const discussions = result.data?.search?.nodes ?? [];
    const allComments: BlogComment[] = [];

    for (const discussion of discussions) {
      const comments = discussion.comments?.nodes ?? [];
      for (const c of comments) {
        allComments.push({
          author: c.author?.login || "unknown",
          body: c.body,
          createdAt: c.createdAt.split("T")[0] as string,
          isPriority: priorityUser !== "" && c.author?.login === priorityUser,
        });
      }
    }

    // Sort newest first
    allComments.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    return allComments;
  } catch (error) {
    console.warn(`⚠️  Error fetching Giscus series comments: ${error instanceof Error ? error.message : error}`);
    return [];
  }
}
