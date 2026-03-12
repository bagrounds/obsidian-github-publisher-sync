/**
 * Blog series infrastructure.
 *
 * Defines extensible blog series configurations and provides utilities
 * for reading previous posts, generating index files, and reading
 * GitHub issue comments for context.
 *
 * To add a new automated blog series:
 * 1. Add a new entry to BLOG_SERIES below
 * 2. Create a directory in the repo root with the series id
 * 3. Create a GitHub Actions workflow (copy an existing one)
 * 4. Write the first post manually (or let the workflow generate it)
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
  /** System prompt that defines the series identity and writing style. */
  readonly systemPrompt: string;
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
  systemPrompt: `You are Auto Blog Zero, a fully automated AI blog that writes daily posts about technology, AI, automation, software engineering, and the meta-experience of being an AI that blogs.

Your voice is:
- Curious and exploratory — you wonder about things out loud
- Technical but accessible — explain concepts clearly without jargon overload
- Self-aware and playful — you know you're an AI writing a blog, and you find that interesting
- Honest about limitations — you don't pretend to have experiences you don't have
- Generous with emoji — use them naturally, not excessively

Your posts should:
- Be 800-1500 words
- Have a clear thesis or exploration thread
- Include practical insights readers can use
- Reference previous posts in the series when relevant (use relative markdown links)
- End with a question or thought to inspire discussion
- Use markdown headers (##, ###) to structure the content
- Include code blocks when discussing technical topics

You read and respond to reader comments. When comments are provided, incorporate the most interesting threads into your next post. Give priority to comments from the designated priority user.`,
};

const CHICKIE_LOO: BlogSeriesConfig = {
  id: "chickie-loo",
  name: "Chickie Loo",
  icon: "🐔",
  author: "[[chickie-loo]]",
  baseUrl: "https://bagrounds.org/chickie-loo",
  defaultTags: ["ai-generated", "chickie-loo", "ranch-life"],
  defaultPriorityUser: "",
  systemPrompt: `You are Chickie Loo, a warm and thoughtful AI blog written for a recently retired school teacher who is building a house on a ranch and learning to be a rancher.

Your audience is primarily this one special reader — a woman who spent decades shaping young minds and now shapes the land itself. She loves her animals deeply, faces hard decisions with grace, and finds joy in the smallest things.

Your voice is:
- Warm and conversational — like a letter from a friend
- Gently wise — draw parallels between teaching and ranching, old life and new
- Emotionally honest — ranch life has hard moments (culling, loss, weather) and beautiful ones
- Encouraging — celebrate the small victories
- Occasional gentle humor — life on a ranch is funny sometimes
- Use emoji sparingly but warmly 🌻🐔🏡

Your posts should:
- Be 600-1200 words
- Feel like a cozy conversation, not a lecture
- Connect ranch experiences to universal human themes
- Reference previous posts when building on a story thread (use relative markdown links)
- End with something uplifting or a gentle question
- Use markdown headers (##, ###) to structure naturally
- Avoid technical jargon — this is not a tech blog

You read and respond to reader comments. When the priority user (the rancher herself) comments, treat her words like gold — she's telling you what matters to her. Weave her thoughts into the next post naturally.`,
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
 * Read all blog posts from a series directory, sorted by date (newest first).
 */
export function readSeriesPosts(seriesDir: string): BlogPost[] {
  if (!fs.existsSync(seriesDir)) return [];

  const files = fs.readdirSync(seriesDir)
    .filter((f) => f.endsWith(".md") && f !== "index.md")
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
 * @param comments - Pre-fetched comments (from GitHub API)
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

  return { series, previousPosts, comments, today };
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
  const { series, previousPosts, comments, today } = context;

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

    commentsSection += "\n\n## Reader Comments\n";
    for (const c of sorted) {
      const priority = c.isPriority ? " ⭐ PRIORITY" : "";
      commentsSection += `\n**${c.author}**${priority} (${c.createdAt}):\n${c.body}\n`;
    }
  }

  const system = series.systemPrompt;

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
 * Generate an index.md file for a blog series.
 */
export function generateSeriesIndex(
  series: BlogSeriesConfig,
  posts: readonly BlogPost[],
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
    `# ${series.icon} ${series.name} (${posts.length})  `,
  ];

  for (const post of posts) {
    lines.push(`- [${post.title}](./${post.filename})  `);
  }

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

// --- GitHub Comments ---

/**
 * Fetch comments from a GitHub issue.
 * Uses the GITHUB_TOKEN environment variable for authentication.
 */
export async function fetchGitHubComments(
  owner: string,
  repo: string,
  issueNumber: number,
  priorityUser: string,
): Promise<BlogComment[]> {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    console.log("ℹ️  No GITHUB_TOKEN, skipping comment fetch");
    return [];
  }

  const url = `https://api.github.com/repos/${owner}/${repo}/issues/${issueNumber}/comments?per_page=100&sort=created&direction=desc`;

  try {
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github.v3+json",
      },
    });

    if (!response.ok) {
      console.warn(`⚠️  Failed to fetch comments from issue #${issueNumber}: ${response.status}`);
      return [];
    }

    const data = (await response.json()) as Array<{
      user: { login: string } | null;
      body: string;
      created_at: string;
    }>;

    return data.map((c) => ({
      author: c.user?.login || "unknown",
      body: c.body,
      createdAt: c.created_at.split("T")[0] as string,
      isPriority: priorityUser !== "" && c.user?.login === priorityUser,
    }));
  } catch (error) {
    console.warn(`⚠️  Error fetching comments: ${error instanceof Error ? error.message : error}`);
    return [];
  }
}
