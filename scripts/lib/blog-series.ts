/**
 * Blog series configuration, context building, and Giscus comment fetching.
 * @module blog-series
 */

import fs from "node:fs";
import path from "node:path";
import { parseFrontmatter } from "./frontmatter.ts";

// --- Types ---

export interface BlogSeriesConfig {
  readonly id: string;
  readonly name: string;
  readonly icon: string;
  readonly author: string;
  readonly baseUrl: string;
  readonly defaultTags: readonly string[];
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

// --- Series Registry ---

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

export const BLOG_SERIES: ReadonlyMap<string, BlogSeriesConfig> = new Map([
  [AUTO_BLOG_ZERO.id, AUTO_BLOG_ZERO],
  [CHICKIE_LOO.id, CHICKIE_LOO],
]);

// --- File Reading ---

export const readAgentsMd = (seriesDir: string): string => {
  const agentsPath = path.join(seriesDir, "AGENTS.md");
  return fs.existsSync(agentsPath) ? fs.readFileSync(agentsPath, "utf-8") : "";
};

const isPostFile = (filename: string): boolean =>
  filename.endsWith(".md") && !["index.md", "AGENTS.md", "IDEAS.md"].includes(filename);

const parsePostFile = (seriesDir: string) => (filename: string): BlogPost => {
  const content = fs.readFileSync(path.join(seriesDir, filename), "utf-8");
  const { frontmatter, body } = parseFrontmatter(content);
  const tagsRaw = content.match(/^tags:\s*\n((?:\s+-\s+.*\n)*)/m);
  const tags = tagsRaw
    ? (tagsRaw[1] ?? "").split("\n").map((l) => l.replace(/^\s*-\s*/, "").trim()).filter(Boolean)
    : [];
  return {
    filename,
    date: filename.match(/^(\d{4}-\d{2}-\d{2})/)?.[1] ?? "",
    title: frontmatter["title"] ?? filename.replace(/\.md$/, ""),
    body,
    tags,
  };
};

export const readSeriesPosts = (seriesDir: string): BlogPost[] =>
  !fs.existsSync(seriesDir)
    ? []
    : fs.readdirSync(seriesDir).filter(isPostFile).sort().reverse().map(parsePostFile(seriesDir));

// --- Context Building ---

export const lookupSeries = (seriesId: string): BlogSeriesConfig => {
  const series = BLOG_SERIES.get(seriesId);
  if (!series) throw new Error(`Unknown blog series: ${seriesId}. Available: ${[...BLOG_SERIES.keys()].join(", ")}`);
  return series;
};

export const buildBlogContext = (
  seriesId: string,
  repoRoot: string,
  comments: readonly BlogComment[],
  today: string,
): BlogContext => {
  const series = lookupSeries(seriesId);
  const seriesDir = path.join(repoRoot, series.id);
  return { series, agentsMd: readAgentsMd(seriesDir), previousPosts: readSeriesPosts(seriesDir), comments, today };
};

// --- Prompt Building ---

const MAX_FULL_POSTS = 5;
const MAX_POST_BODY_LENGTH = 3000;

const formatFullPost = (post: BlogPost): string =>
  `\n### ${post.title} (${post.date})\n${
    post.body.length > MAX_POST_BODY_LENGTH
      ? post.body.slice(0, MAX_POST_BODY_LENGTH) + "\n\n[...truncated...]"
      : post.body
  }\n`;

const buildPostHistory = (posts: readonly BlogPost[]): string => {
  if (posts.length === 0) return "";
  const full = posts.slice(0, MAX_FULL_POSTS).map(formatFullPost).join("");
  const titles = posts.slice(MAX_FULL_POSTS).map((p) => `- ${p.title} (${p.date})\n`).join("");
  return `\n\n## Previous Posts (most recent first)\n${full}${titles ? `\n### Older posts (titles only)\n${titles}` : ""}`;
};

const buildCommentsSection = (comments: readonly BlogComment[]): string => {
  if (comments.length === 0) return "";
  const sorted = [...comments].sort((a, b) => a.isPriority === b.isPriority ? 0 : a.isPriority ? -1 : 1);
  const formatted = sorted.map((c) =>
    `\n**${c.author}**${c.isPriority ? " ⭐ PRIORITY" : ""} (${c.createdAt}):\n${c.body}\n`
  ).join("");
  return `\n\n## Reader Comments (from Giscus/GitHub Discussions)\n${formatted}`;
};

export const buildBlogPrompt = (context: BlogContext): { system: string; user: string } => {
  const { series, agentsMd, previousPosts, comments, today } = context;

  const system = agentsMd || `You are ${series.name}, an automated blog. Write a blog post.`;
  const user = `Write a new blog post for today, ${today}.
${buildPostHistory(previousPosts)}${buildCommentsSection(comments)}

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
    ? "Address reader comments naturally in your post. Only incorporate what fits."
    : "No reader comments yet. Write based on the series theme and previous content."}

Write ONLY the markdown content. Do not wrap in code blocks. Start with the --- frontmatter delimiter.`;

  return { system, user };
};

// --- Index Generation ---

export const generateSeriesIndex = (series: BlogSeriesConfig, _posts: readonly BlogPost[]): string =>
  [
    "---", "share: true", "aliases:", `  - ${series.icon} ${series.name}`,
    `title: ${series.icon} ${series.name}`, `URL: ${series.baseUrl}/index`,
    `Author: "${series.author}"`, "backlinks: false",
    `updated: ${new Date().toISOString().split("T")[0]}`,
    "---", `[Home](../index.md)  `, `# ${series.icon} ${series.name}  `,
    "```dataview",
    `LIST FROM "${series.id}"`,
    `WHERE file.name != "index" AND file.name != "AGENTS" AND file.name != "IDEAS"`,
    "SORT file.name DESC", "```",
  ].join("\n") + "\n";

// --- Post Parsing ---

export const extractSlug = (filename: string): string =>
  filename.replace(/\.md$/, "").replace(/^\d{4}-\d{2}-\d{2}-?/, "");

export const parseGeneratedPost = (raw: string): { content: string; title: string } | null => {
  const trimmed = raw.trim();
  if (!trimmed.startsWith("---")) return null;
  if (trimmed.indexOf("---", 3) < 0) return null;
  const titleMatch = trimmed.match(/^title:\s*(.+)$/m);
  if (!titleMatch?.[1]) return null;
  if (trimmed.length < 500) return null;
  return { content: trimmed, title: titleMatch[1].trim() };
};

// --- Giscus / GitHub Discussions ---

const GISCUS_REPO = "bagrounds/obsidian-github-publisher-sync";

interface GqlDiscussionComment { readonly body: string; readonly author: { readonly login: string } | null; readonly createdAt: string; }
interface GqlDiscussion { readonly title: string; readonly comments: { readonly nodes: readonly GqlDiscussionComment[] }; }
interface GqlSearchResult { readonly data?: { readonly search: { readonly nodes: readonly GqlDiscussion[] } }; readonly errors?: ReadonlyArray<{ readonly message: string }>; }

const toComment = (priorityUser: string) => (c: GqlDiscussionComment): BlogComment => ({
  author: c.author?.login ?? "unknown",
  body: c.body,
  createdAt: c.createdAt.split("T")[0] as string,
  isPriority: priorityUser !== "" && c.author?.login === priorityUser,
});

const searchDiscussions = async (token: string, searchQuery: string, maxResults: number, maxComments: number): Promise<readonly GqlDiscussion[]> => {
  const query = `query($searchQuery: String!) {
    search(type: DISCUSSION, query: $searchQuery, first: ${maxResults}) {
      nodes { ... on Discussion { title, comments(first: ${maxComments}) { nodes { body, author { login }, createdAt } } } }
    }
  }`;

  const response = await fetch("https://api.github.com/graphql", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables: { searchQuery } }),
  });

  if (!response.ok) { console.warn(JSON.stringify({ event: "graphql_error", status: response.status })); return []; }
  const result = (await response.json()) as GqlSearchResult;
  if (result.errors) { console.warn(JSON.stringify({ event: "graphql_errors", errors: result.errors.map((e) => e.message) })); return []; }
  return result.data?.search?.nodes ?? [];
};

export const fetchGiscusComments = async (pathname: string, priorityUser: string): Promise<BlogComment[]> => {
  const token = process.env.GITHUB_TOKEN;
  if (!token) { console.log(JSON.stringify({ event: "skip_giscus", reason: "no GITHUB_TOKEN" })); return []; }
  try {
    const discussions = await searchDiscussions(token, `repo:${GISCUS_REPO} in:title "${pathname}"`, 1, 100);
    return (discussions[0]?.comments?.nodes ?? []).map(toComment(priorityUser));
  } catch (error) {
    console.warn(JSON.stringify({ event: "giscus_error", message: error instanceof Error ? error.message : String(error) }));
    return [];
  }
};

export const fetchAllSeriesComments = async (seriesId: string, priorityUser: string): Promise<BlogComment[]> => {
  const token = process.env.GITHUB_TOKEN;
  if (!token) { console.log(JSON.stringify({ event: "skip_giscus", reason: "no GITHUB_TOKEN" })); return []; }
  try {
    const discussions = await searchDiscussions(token, `repo:${GISCUS_REPO} in:title "${seriesId}/"`, 50, 50);
    return discussions
      .flatMap((d) => (d.comments?.nodes ?? []).map(toComment(priorityUser)))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  } catch (error) {
    console.warn(JSON.stringify({ event: "giscus_error", message: error instanceof Error ? error.message : String(error) }));
    return [];
  }
};

// --- Pacific Time ---

export const todayPacific = (): string =>
  new Date().toLocaleDateString("en-CA", { timeZone: "America/Los_Angeles" });
