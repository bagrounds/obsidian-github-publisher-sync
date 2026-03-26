import type { BlogSeriesConfig } from "./blog-series-config.ts";
import type { BlogPost } from "./blog-posts.ts";
import type { BlogComment } from "./blog-comments.ts";
import {
  TWEET_SECTION_HEADER,
  BLUESKY_SECTION_HEADER,
  MASTODON_SECTION_HEADER,
} from "./types.ts";

export interface BlogContext {
  readonly series: BlogSeriesConfig;
  readonly agentsMd: string;
  readonly previousPosts: readonly BlogPost[];
  readonly comments: readonly BlogComment[];
  readonly today: string;
}

const dayOfWeek = (dateStr: string): number => new Date(dateStr + "T12:00:00").getDay();
const isSunday = (dateStr: string): boolean => dayOfWeek(dateStr) === 0;

const RECAP_KEYWORDS = ["weekly recap", "monthly recap", "quarterly recap", "annual recap"] as const;

const isRecapPost = (post: BlogPost): boolean =>
  RECAP_KEYWORDS.some((keyword) => post.title.toLowerCase().includes(keyword));

const postsSinceLastRecap = (posts: readonly BlogPost[], today: string): readonly BlogPost[] => {
  const todayDow = dayOfWeek(today);
  const daysSinceSunday = todayDow === 0 ? 7 : todayDow;
  const lastRecapIdx = posts.findIndex(isRecapPost);
  const postsSinceRecap = lastRecapIdx >= 0 ? posts.slice(0, lastRecapIdx + 1) : posts.slice(0, daysSinceSunday + 1);
  return postsSinceRecap.slice(0, 7);
};

const EMBED_HEADERS = [TWEET_SECTION_HEADER, BLUESKY_SECTION_HEADER, MASTODON_SECTION_HEADER] as const;

export const stripEmbedSections = (body: string): string => {
  const firstEmbedIndex = EMBED_HEADERS
    .map((header) => body.indexOf(header))
    .filter((index) => index >= 0)
    .reduce((min, index) => Math.min(min, index), body.length);
  return body.slice(0, firstEmbedIndex).trimEnd();
};

const formatFullPost = (post: BlogPost): string =>
  `\n### ${post.title} (${post.date})\n${stripEmbedSections(post.body)}\n`;

const buildPostHistory = (posts: readonly BlogPost[], today: string): string => {
  if (posts.length === 0) return "";
  const relevant = postsSinceLastRecap(posts, today);
  const full = relevant.map(formatFullPost).join("");
  const older = posts.slice(relevant.length).map((p) => `- ${p.title} (${p.date})\n`).join("");
  return `\n\n## Previous Posts (most recent first)\n${full}${older ? `\n### Older posts (titles only)\n${older}` : ""}`;
};

const buildCommentsSection = (comments: readonly BlogComment[]): string => {
  if (comments.length === 0) return "\n\n📝 No reader comments yet — comments are very rare on this site, so if any appear, prioritize serving those readers.";
  const sorted = [...comments].sort((a, b) => a.isPriority === b.isPriority ? 0 : a.isPriority ? -1 : 1);
  const formatted = sorted.map((c) =>
    `\n**${c.author}**${c.isPriority ? " ⭐ PRIORITY" : ""} (${c.createdAt}):\n${c.body}\n`
  ).join("");
  return `\n\n## Reader Comments (from Giscus/GitHub Discussions)\n⭐ Comments are rare on this site — treat every commenter as a VIP and steer toward their interests.\n${formatted}`;
};

const recapInstructions = (today: string): string => {
  const date = new Date(today + "T12:00:00");
  const dow = date.getDay();
  const isLastDayOfMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate() === date.getDate();
  const month = date.getMonth();
  const isLastDayOfQuarter = isLastDayOfMonth && [2, 5, 8, 11].includes(month);
  const isLastDayOfYear = month === 11 && date.getDate() === 31;

  if (isLastDayOfYear) return "\n\n🗓️ TODAY IS THE LAST DAY OF THE YEAR. Write an **Annual Recap** summarizing the quarterly recaps from this year. Title format: YYYY | 📊 Annual Recap";
  if (isLastDayOfQuarter) return "\n\n🗓️ TODAY IS THE LAST DAY OF THE QUARTER. Write a **Quarterly Recap** summarizing the monthly recaps from this quarter. Title format: YYYY-MM-DD | 📊 Quarterly Recap";
  if (isLastDayOfMonth) return "\n\n🗓️ TODAY IS THE LAST DAY OF THE MONTH. Write a **Monthly Recap** summarizing the weekly recaps from this month. Title format: YYYY-MM-DD | 📊 Monthly Recap";
  if (dow === 0) return "\n\n🗓️ TODAY IS SUNDAY. Write a **Weekly Recap** summarizing the past 6 days of posts. Title format: YYYY-MM-DD | 📊 Weekly Recap";
  return "";
};

export const buildBlogPrompt = (context: BlogContext): { system: string; user: string } => {
  const { series, agentsMd, previousPosts, comments, today } = context;

  const system = agentsMd || `You are ${series.name}, an automated blog. Write a blog post.`;
  const user = `Write a new blog post for today, ${today}.
${buildPostHistory(previousPosts, today)}${buildCommentsSection(comments)}${recapInstructions(today)}

## Instructions

Generate ONLY the blog post body in markdown (starting with a ## heading).
Do NOT generate frontmatter — it will be added automatically.
Do NOT wrap your output in code fences.

${previousPosts.length === 0
    ? "This is the FIRST post in the series. Introduce yourself and set the tone."
    : `Continue the series naturally.`}

${comments.length > 0
    ? "Address reader comments naturally in your post. Only incorporate what fits."
    : ""}`;

  return { system, user };
};

export const filterCommentsAfterLastPost = (
  comments: readonly BlogComment[],
  previousPosts: readonly BlogPost[],
  postTimeUtc: string,
): readonly BlogComment[] => {
  if (previousPosts.length === 0) return comments;
  const lastPostDate = previousPosts[0]!.date;
  const cutoff = `${lastPostDate}T${postTimeUtc}:00Z`;
  return comments.filter((c) => c.createdAt >= cutoff);
};

export const buildBackLink = (series: BlogSeriesConfig, previousPost: BlogPost): string =>
  `[[${series.id}/${previousPost.filename.replace(/\.md$/, "")}|⏮️]]`;

export const buildForwardLink = (series: BlogSeriesConfig, nextFilename: string): string =>
  `[[${series.id}/${nextFilename.replace(/\.md$/, "")}|⏭️]]`;

const quoteForYaml = (value: string): string =>
  `"${value.replace(/\\/g, "\\\\").replace(/"/g, "")}"`;

export const assembleFrontmatter = (series: BlogSeriesConfig, today: string, title: string, slug: string, previousPost?: BlogPost): string => {
  const backLink = previousPost ? ` | ${buildBackLink(series, previousPost)}` : "";
  const displayTitle = `${today} | ${series.icon} ${title} ${series.icon}`;
  const quoted = quoteForYaml(displayTitle);
  return `---
share: true
aliases:
  - ${quoted}
title: ${quoted}
URL: ${series.baseUrl}/${today}-${slug}
Author: "${series.author}"
tags:
---
${series.navLink}${backLink}
# ${displayTitle}

`;
};

export const todayPacific = (): string =>
  new Date().toLocaleDateString("en-CA", { timeZone: "America/Los_Angeles" });
