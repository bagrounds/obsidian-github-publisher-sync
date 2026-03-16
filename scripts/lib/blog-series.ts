export { type BlogSeriesConfig, BLOG_SERIES, lookupSeries } from "./blog-series-config.ts";
export { type BlogPost, readSeriesPosts, readAgentsMd } from "./blog-posts.ts";
export { type BlogComment, fetchGiscusComments, fetchAllSeriesComments } from "./blog-comments.ts";
export { type BlogContext, buildBlogPrompt, assembleFrontmatter, todayPacific } from "./blog-prompt.ts";
export { findMostRecentPost, buildNavLine, addNextLinkToContent, updatePreviousPost } from "./blog-nav.ts";
export { type BookEntry, readBookCatalog, buildBookRecommendationsPrompt } from "./blog-books.ts";

import path from "node:path";
import type { BlogSeriesConfig } from "./blog-series-config.ts";
import type { BlogPost } from "./blog-posts.ts";
import type { BlogComment } from "./blog-comments.ts";
import type { BlogContext } from "./blog-prompt.ts";
import { readAgentsMd, readSeriesPosts } from "./blog-posts.ts";
import { lookupSeries } from "./blog-series-config.ts";
import { readBookCatalog, buildBookRecommendationsPrompt } from "./blog-books.ts";

export const buildBlogContext = (
  seriesId: string,
  repoRoot: string,
  comments: readonly BlogComment[],
  today: string,
): BlogContext => {
  const series = lookupSeries(seriesId);
  const seriesDir = path.join(repoRoot, series.id);
  const booksDir = path.join(repoRoot, "content", "books");
  const bookCatalog = readBookCatalog(booksDir);
  return {
    series,
    agentsMd: readAgentsMd(seriesDir),
    previousPosts: readSeriesPosts(seriesDir),
    comments,
    today,
    bookRecommendationsPrompt: buildBookRecommendationsPrompt(bookCatalog),
  };
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
    `WHERE file.name != "index" AND file.name != "AGENTS"`,
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

export const stripRedundantFirstHeading = (body: string, title: string): string => {
  const match = body.match(/^(#{1,2})\s+(.+)\n*/);
  if (!match) return body;
  const headingText = (match[2] ?? "").trim();
  return headingText === title ? body.slice(match[0].length) : body;
};

export const appendModelSignature = (body: string, model: string): string =>
  `${body}\n✍️ Written by ${model}`;
