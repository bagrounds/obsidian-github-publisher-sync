export { type BlogSeriesConfig, BLOG_SERIES, BACKFILL_CONTENT_IDS, lookupSeries } from "./blog-series-config.ts";
export { type BlogPost, readSeriesPosts, readAgentsMd } from "./blog-posts.ts";
export { type BlogComment, fetchGiscusComments, fetchAllSeriesComments } from "./blog-comments.ts";
export { type BlogContext, buildBlogPrompt, assembleFrontmatter, buildBackLink, buildForwardLink, filterCommentsAfterLastPost, todayPacific, stripEmbedSections } from "./blog-prompt.ts";

import fs from "node:fs";
import path from "node:path";
import type { BlogSeriesConfig } from "./blog-series-config.ts";
import type { BlogPost } from "./blog-posts.ts";
import type { BlogComment } from "./blog-comments.ts";
import { readAgentsMd, readSeriesPosts } from "./blog-posts.ts";
import { lookupSeries } from "./blog-series-config.ts";
import { filterCommentsAfterLastPost, buildForwardLink } from "./blog-prompt.ts";

export const buildBlogContext = (
  seriesId: string,
  repoRoot: string,
  comments: readonly BlogComment[],
  today: string,
): { series: BlogSeriesConfig; agentsMd: string; previousPosts: readonly BlogPost[]; comments: readonly BlogComment[]; today: string } => {
  const series = lookupSeries(seriesId);
  const seriesDir = path.join(repoRoot, series.id);
  const previousPosts = readSeriesPosts(seriesDir);
  return { series, agentsMd: readAgentsMd(seriesDir), previousPosts, comments: filterCommentsAfterLastPost(comments, previousPosts, series.postTimeUtc), today };
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

export const appendModelSignature = (body: string, model: string): string =>
  `${body}\n\n✍️ Written by ${model}`;

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

export const updatePreviousPost = (
  seriesDir: string,
  previousPost: BlogPost,
  series: BlogSeriesConfig,
  nextFilename: string,
): void => {
  const filePath = path.join(seriesDir, previousPost.filename);
  if (!fs.existsSync(filePath)) {
    log({ event: "update_previous_skip", reason: "file_not_found", filePath, previousPost: previousPost.filename });
    return;
  }
  const content = fs.readFileSync(filePath, "utf-8");
  const forwardLink = buildForwardLink(series, nextFilename);
  const navLineFound = content.split("\n").some((line) => line.startsWith(series.navLink));
  const alreadyHasForward = content.includes("⏭");
  log({
    event: "update_previous_check",
    previousPost: previousPost.filename,
    navLineFound,
    alreadyHasForward,
    forwardLink,
    nextFilename,
  });
  const updated = content.split("\n").map((line) =>
    line.startsWith(series.navLink) && !line.includes("⏭") ? `${line} ${forwardLink}` : line
  ).join("\n");
  if (updated !== content) {
    fs.writeFileSync(filePath, updated, "utf-8");
    log({ event: "update_previous_written", previousPost: previousPost.filename, forwardLink });
  } else {
    log({ event: "update_previous_no_change", previousPost: previousPost.filename, reason: alreadyHasForward ? "already_has_forward" : "nav_line_not_matched" });
  }
};
