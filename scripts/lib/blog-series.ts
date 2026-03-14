export { type BlogSeriesConfig, BLOG_SERIES, lookupSeries } from "./blog-series-config.ts";
export { type BlogPost, readSeriesPosts, readAgentsMd, readIdeasMd } from "./blog-posts.ts";
export { type BlogComment, fetchGiscusComments, fetchAllSeriesComments } from "./blog-comments.ts";
export { type BlogContext, buildBlogPrompt, assembleFrontmatter, todayPacific } from "./blog-prompt.ts";

import path from "node:path";
import type { BlogSeriesConfig } from "./blog-series-config.ts";
import type { BlogPost } from "./blog-posts.ts";
import type { BlogComment } from "./blog-comments.ts";
import { readAgentsMd, readSeriesPosts } from "./blog-posts.ts";
import { lookupSeries } from "./blog-series-config.ts";

export const buildBlogContext = (
  seriesId: string,
  repoRoot: string,
  comments: readonly BlogComment[],
  today: string,
): { series: BlogSeriesConfig; agentsMd: string; previousPosts: readonly BlogPost[]; comments: readonly BlogComment[]; today: string } => {
  const series = lookupSeries(seriesId);
  const seriesDir = path.join(repoRoot, series.id);
  return { series, agentsMd: readAgentsMd(seriesDir), previousPosts: readSeriesPosts(seriesDir), comments, today };
};

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

export const extractSlug = (filename: string): string =>
  filename.replace(/\.md$/, "").replace(/^\d{4}-\d{2}-\d{2}-?/, "");

export const parseGeneratedPost = (raw: string): { body: string; title: string } | null => {
  const trimmed = raw.trim();
  if (trimmed.length < 200) return null;
  const titleMatch = trimmed.match(/^#{1,2}\s+(.+)$/m);
  if (!titleMatch?.[1]) return null;
  return { body: trimmed, title: titleMatch[1].trim() };
};

export const appendModelSignature = (body: string, model: string): string =>
  `${body}\n✍️ Written by ${model}`;
