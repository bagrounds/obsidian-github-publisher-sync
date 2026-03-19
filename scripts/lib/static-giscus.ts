/**
 * Static Giscus comments: fetch, render, and inject.
 *
 * Pure functions for building static HTML representations of Giscus comments,
 * plus an IO function for fetching discussion data from GitHub's GraphQL API.
 *
 * Architecture: A post-build script fetches all Giscus discussions, builds a
 * pathname → comments map, then injects static HTML into generated pages.
 * Client-side code swaps static comments for live Giscus iframe when loaded.
 *
 * @module static-giscus
 */

import { escapeHtml, formatDisplayDate } from "./html.ts";

// --- Types ---

export interface StaticComment {
  readonly author: string;
  readonly authorUrl: string;
  readonly bodyHtml: string;
  readonly createdAt: string;
}

export type CommentsMap = Readonly<Record<string, readonly StaticComment[]>>;

export interface GqlAuthor {
  readonly login: string;
  readonly url: string;
}

export interface GqlComment {
  readonly bodyHTML: string;
  readonly author: GqlAuthor | null;
  readonly createdAt: string;
}

export interface GqlDiscussion {
  readonly title: string;
  readonly comments: {
    readonly nodes: readonly GqlComment[];
  };
}

interface GqlPageInfo {
  readonly hasNextPage: boolean;
  readonly endCursor: string | null;
}

interface GqlResponse {
  readonly data?: {
    readonly repository?: {
      readonly discussions?: {
        readonly nodes: readonly GqlDiscussion[];
        readonly pageInfo: GqlPageInfo;
      };
    };
  };
  readonly errors?: readonly { readonly message: string }[];
}

// --- Pure Functions ---

export const normalizePathname = (p: string): string =>
  p === "/" ? "/" : p.replace(/\/+$/, "");

export const slugToPathname = (slug: string): string =>
  slug === "index" ? "/" : `/${slug}`;

const toStaticComment = (c: GqlComment): StaticComment => ({
  author: c.author?.login ?? "unknown",
  authorUrl: c.author?.url ?? "https://github.com",
  bodyHtml: c.bodyHTML,
  createdAt: c.createdAt,
});

export const buildCommentsMap = (discussions: readonly GqlDiscussion[]): CommentsMap =>
  Object.fromEntries(
    discussions
      .map((d) => [normalizePathname(d.title), d.comments.nodes.map(toStaticComment)] as const)
      .filter(([, comments]) => comments.length > 0),
  );

const STATIC_GISCUS_CSS = `<style>
.static-giscus-comments { margin-top: 1rem; }
.static-giscus-comment {
  margin-bottom: 1rem;
  padding: 0.75rem 1rem;
  border: 1px solid var(--lightgray);
  border-radius: 8px;
}
.static-giscus-comment-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
  font-size: 0.875rem;
}
.static-giscus-author {
  font-weight: 600;
  color: var(--secondary);
  text-decoration: none;
}
.static-giscus-author:hover { text-decoration: underline; }
.static-giscus-time { color: var(--gray); font-size: 0.8rem; }
.static-giscus-body { line-height: 1.6; color: var(--darkgray); }
.static-giscus-body p { margin: 0.5em 0; }
.static-giscus-body p:first-child { margin-top: 0; }
.static-giscus-body p:last-child { margin-bottom: 0; }
</style>`;

const renderComment = (c: StaticComment): string =>
  `<article class="static-giscus-comment">
<header class="static-giscus-comment-header">
<a href="${escapeHtml(c.authorUrl)}" rel="nofollow" class="static-giscus-author">${escapeHtml(c.author)}</a>
<time datetime="${c.createdAt}" class="static-giscus-time">${formatDisplayDate(c.createdAt.slice(0, 10))}</time>
</header>
<div class="static-giscus-body">${c.bodyHtml}</div>
</article>`;

export const renderStaticCommentsHtml = (comments: readonly StaticComment[]): string =>
  comments.length === 0
    ? ""
    : `<section data-static-giscus class="static-giscus-comments" aria-label="Comments">
${STATIC_GISCUS_CSS}
${comments.map(renderComment).join("\n")}
</section>`;

const GISCUS_DIV_PATTERN = /<div class="[^"]*\bgiscus\b[^"]*"/;

export const extractSlug = (html: string): string | undefined => {
  const match = html.match(/<body[^>]*data-slug="([^"]*)"/);
  return match?.[1];
};

export const injectStaticComments = (html: string, commentsMap: CommentsMap): string => {
  const slug = extractSlug(html);
  if (slug === undefined) return html;

  const pathname = normalizePathname(slugToPathname(slug));
  const comments = commentsMap[pathname];
  if (!comments || comments.length === 0) return html;

  const staticHtml = renderStaticCommentsHtml(comments);
  const match = html.match(GISCUS_DIV_PATTERN);
  if (!match || match.index === undefined) return html;

  return html.slice(0, match.index) + staticHtml + "\n" + html.slice(match.index);
};

// --- IO Functions ---

export const fetchAllDiscussions = async (
  token: string,
  owner: string,
  repo: string,
  categoryId: string,
): Promise<readonly GqlDiscussion[]> => {
  const discussions: GqlDiscussion[] = [];
  let after: string | null = null;
  let hasMore = true;

  const query = `query($owner: String!, $name: String!, $categoryId: ID!, $after: String) {
    repository(owner: $owner, name: $name) {
      discussions(categoryId: $categoryId, first: 100, after: $after, orderBy: { field: UPDATED_AT, direction: DESC }) {
        pageInfo { hasNextPage, endCursor }
        nodes {
          title
          comments(first: 100) {
            nodes {
              bodyHTML
              author { login, url }
              createdAt
            }
          }
        }
      }
    }
  }`;

  while (hasMore) {
    const response = await fetch("https://api.github.com/graphql", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        query,
        variables: { owner, name: repo, categoryId, after },
      }),
    });

    if (!response.ok) {
      console.warn(
        JSON.stringify({ event: "static_giscus_fetch_error", status: response.status }),
      );
      break;
    }

    const result = (await response.json()) as GqlResponse;
    if (result.errors) {
      console.warn(
        JSON.stringify({
          event: "static_giscus_graphql_errors",
          errors: result.errors.map((e) => e.message),
        }),
      );
      break;
    }

    const page = result.data?.repository?.discussions;
    if (!page) break;

    discussions.push(...page.nodes);
    hasMore = page.pageInfo.hasNextPage;
    after = page.pageInfo.endCursor;
  }

  return discussions;
};
