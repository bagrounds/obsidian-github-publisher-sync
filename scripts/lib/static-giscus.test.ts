/**
 * Tests for scripts/lib/static-giscus.ts — Static Giscus comment rendering and injection.
 *
 * Tests cover pure functions only: normalizePathname, slugToPathname,
 * buildCommentsMap, renderStaticCommentsHtml, extractSlug, injectStaticComments.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  normalizePathname,
  slugToPathname,
  buildCommentsMap,
  renderStaticCommentsHtml,
  extractSlug,
  injectStaticComments,
  type GqlDiscussion,
  type StaticComment,
  type CommentsMap,
} from "./static-giscus.ts";

// --- normalizePathname ---

describe("normalizePathname", () => {
  it("preserves root path", () => {
    assert.equal(normalizePathname("/"), "/");
  });

  it("strips trailing slash", () => {
    assert.equal(normalizePathname("/topics/javascript/"), "/topics/javascript");
  });

  it("strips multiple trailing slashes", () => {
    assert.equal(normalizePathname("/topics/javascript///"), "/topics/javascript");
  });

  it("preserves path without trailing slash", () => {
    assert.equal(normalizePathname("/topics/javascript"), "/topics/javascript");
  });

  it("handles empty string", () => {
    assert.equal(normalizePathname(""), "");
  });

  it("is idempotent", () => {
    const paths = ["/", "/a", "/a/b/", "///", "/x///", ""];
    paths.forEach((p) => {
      assert.equal(normalizePathname(normalizePathname(p)), normalizePathname(p));
    });
  });

  it("result never ends with slash (except root)", () => {
    const paths = ["/a/", "/a/b/", "/x///", "/abc"];
    paths.forEach((p) => {
      const result = normalizePathname(p);
      assert.ok(result === "/" || !result.endsWith("/"));
    });
  });
});

// --- slugToPathname ---

describe("slugToPathname", () => {
  it("converts index to root", () => {
    assert.equal(slugToPathname("index"), "/");
  });

  it("prepends slash to slug", () => {
    assert.equal(slugToPathname("topics/javascript"), "/topics/javascript");
  });

  it("prepends slash to simple slug", () => {
    assert.equal(slugToPathname("about"), "/about");
  });
});

// --- buildCommentsMap ---

describe("buildCommentsMap", () => {
  it("returns empty map for empty discussions", () => {
    assert.deepEqual(buildCommentsMap([]), {});
  });

  it("maps discussion title to comments", () => {
    const discussions: readonly GqlDiscussion[] = [
      {
        title: "/topics/javascript",
        comments: {
          nodes: [
            {
              bodyHTML: "<p>Great!</p>",
              author: { login: "user1", url: "https://github.com/user1" },
              createdAt: "2024-01-15T10:30:00Z",
            },
          ],
        },
      },
    ];
    const result = buildCommentsMap(discussions);
    assert.equal(Object.keys(result).length, 1);
    assert.equal(result["/topics/javascript"]?.length, 1);
    assert.equal(result["/topics/javascript"]?.[0]?.author, "user1");
  });

  it("filters out discussions with no comments", () => {
    const discussions: readonly GqlDiscussion[] = [
      { title: "/empty-page", comments: { nodes: [] } },
    ];
    assert.deepEqual(buildCommentsMap(discussions), {});
  });

  it("normalizes pathnames by stripping trailing slashes", () => {
    const discussions: readonly GqlDiscussion[] = [
      {
        title: "/topics/javascript/",
        comments: {
          nodes: [
            {
              bodyHTML: "<p>Hi</p>",
              author: { login: "u", url: "https://github.com/u" },
              createdAt: "2024-01-01T00:00:00Z",
            },
          ],
        },
      },
    ];
    const result = buildCommentsMap(discussions);
    assert.ok(result["/topics/javascript"]);
    assert.equal(result["/topics/javascript/"], undefined);
  });

  it("handles null author", () => {
    const discussions: readonly GqlDiscussion[] = [
      {
        title: "/page",
        comments: {
          nodes: [
            { bodyHTML: "<p>Anon</p>", author: null, createdAt: "2024-01-01T00:00:00Z" },
          ],
        },
      },
    ];
    const result = buildCommentsMap(discussions);
    assert.equal(result["/page"]?.[0]?.author, "unknown");
    assert.equal(result["/page"]?.[0]?.authorUrl, "https://github.com");
  });

  it("handles multiple discussions", () => {
    const discussions: readonly GqlDiscussion[] = [
      {
        title: "/page-a",
        comments: {
          nodes: [
            {
              bodyHTML: "<p>A</p>",
              author: { login: "a", url: "https://github.com/a" },
              createdAt: "2024-01-01T00:00:00Z",
            },
          ],
        },
      },
      {
        title: "/page-b",
        comments: {
          nodes: [
            {
              bodyHTML: "<p>B</p>",
              author: { login: "b", url: "https://github.com/b" },
              createdAt: "2024-01-02T00:00:00Z",
            },
          ],
        },
      },
    ];
    const result = buildCommentsMap(discussions);
    assert.equal(Object.keys(result).length, 2);
    assert.equal(result["/page-a"]?.[0]?.author, "a");
    assert.equal(result["/page-b"]?.[0]?.author, "b");
  });
});

// --- renderStaticCommentsHtml ---

describe("renderStaticCommentsHtml", () => {
  it("returns empty string for empty comments", () => {
    assert.equal(renderStaticCommentsHtml([]), "");
  });

  it("renders section with data-static-giscus attribute", () => {
    const comments: readonly StaticComment[] = [
      {
        author: "user1",
        authorUrl: "https://github.com/user1",
        bodyHtml: "<p>Hello</p>",
        createdAt: "2024-03-10T10:00:00Z",
      },
    ];
    const html = renderStaticCommentsHtml(comments);
    assert.ok(html.includes("data-static-giscus"));
    assert.ok(html.includes("static-giscus-comments"));
    assert.ok(html.includes("user1"));
    assert.ok(html.includes("<p>Hello</p>"));
    assert.ok(html.includes("March 10, 2024"));
  });

  it("renders semantic HTML with article elements", () => {
    const comments: readonly StaticComment[] = [
      {
        author: "user1",
        authorUrl: "https://github.com/user1",
        bodyHtml: "<p>Test</p>",
        createdAt: "2024-01-01T00:00:00Z",
      },
    ];
    const html = renderStaticCommentsHtml(comments);
    assert.ok(html.includes("<section"));
    assert.ok(html.includes("<article"));
    assert.ok(html.includes("<header"));
    assert.ok(html.includes("<time"));
    assert.ok(html.includes('aria-label="Comments"'));
  });

  it("escapes author names to prevent XSS", () => {
    const comments: readonly StaticComment[] = [
      {
        author: '<script>alert("xss")</script>',
        authorUrl: "https://github.com/x",
        bodyHtml: "<p>Test</p>",
        createdAt: "2024-01-01T00:00:00Z",
      },
    ];
    const html = renderStaticCommentsHtml(comments);
    assert.ok(!html.includes('<script>alert'));
    assert.ok(html.includes("&lt;script&gt;"));
  });

  it("escapes author URL to prevent XSS", () => {
    const comments: readonly StaticComment[] = [
      {
        author: "user",
        authorUrl: '"><script>alert(1)</script>',
        bodyHtml: "<p>Test</p>",
        createdAt: "2024-01-01T00:00:00Z",
      },
    ];
    const html = renderStaticCommentsHtml(comments);
    assert.ok(!html.includes('"><script>'));
    assert.ok(html.includes("&quot;&gt;&lt;script&gt;"));
  });

  it("renders multiple comments", () => {
    const comments: readonly StaticComment[] = [
      {
        author: "a",
        authorUrl: "https://github.com/a",
        bodyHtml: "<p>1</p>",
        createdAt: "2024-01-01T00:00:00Z",
      },
      {
        author: "b",
        authorUrl: "https://github.com/b",
        bodyHtml: "<p>2</p>",
        createdAt: "2024-01-02T00:00:00Z",
      },
    ];
    const html = renderStaticCommentsHtml(comments);
    assert.equal((html.match(/static-giscus-comment"/g) ?? []).length, 2);
  });

  it("includes CSS styles", () => {
    const comments: readonly StaticComment[] = [
      {
        author: "u",
        authorUrl: "https://github.com/u",
        bodyHtml: "<p>x</p>",
        createdAt: "2024-01-01T00:00:00Z",
      },
    ];
    const html = renderStaticCommentsHtml(comments);
    assert.ok(html.includes("<style>"));
    assert.ok(html.includes("static-giscus-comment-header"));
  });
});

// --- extractSlug ---

describe("extractSlug", () => {
  it("extracts slug from body data-slug", () => {
    const html = '<html><body data-slug="topics/javascript"><div></div></body></html>';
    assert.equal(extractSlug(html), "topics/javascript");
  });

  it("returns undefined when no body data-slug", () => {
    const html = "<html><body><div></div></body></html>";
    assert.equal(extractSlug(html), undefined);
  });

  it("handles empty slug", () => {
    const html = '<html><body data-slug=""><div></div></body></html>';
    assert.equal(extractSlug(html), "");
  });

  it("handles index slug", () => {
    const html = '<html><body data-slug="index"><div></div></body></html>';
    assert.equal(extractSlug(html), "index");
  });

  it("handles body with other attributes", () => {
    const html = '<html><body class="page" data-slug="about" id="main"><div></div></body></html>';
    assert.equal(extractSlug(html), "about");
  });
});

// --- injectStaticComments ---

describe("injectStaticComments", () => {
  const sampleHtml = `<html><body data-slug="topics/javascript"><div class="page-footer"><div class="giscus" data-repo="bagrounds/test"></div></div></body></html>`;

  it("returns unchanged HTML when no comments for page", () => {
    assert.equal(injectStaticComments(sampleHtml, {}), sampleHtml);
  });

  it("injects static comments before giscus div", () => {
    const commentsMap: CommentsMap = {
      "/topics/javascript": [
        {
          author: "user1",
          authorUrl: "https://github.com/user1",
          bodyHtml: "<p>Great article!</p>",
          createdAt: "2024-03-10T10:00:00Z",
        },
      ],
    };
    const result = injectStaticComments(sampleHtml, commentsMap);
    assert.ok(result.includes("data-static-giscus"));
    const staticIdx = result.indexOf("data-static-giscus");
    const giscusIdx = result.indexOf('class="giscus"');
    assert.ok(staticIdx < giscusIdx, "static comments should appear before giscus div");
  });

  it("preserves original giscus div", () => {
    const commentsMap: CommentsMap = {
      "/topics/javascript": [
        {
          author: "u",
          authorUrl: "https://github.com/u",
          bodyHtml: "<p>Hi</p>",
          createdAt: "2024-01-01T00:00:00Z",
        },
      ],
    };
    const result = injectStaticComments(sampleHtml, commentsMap);
    assert.ok(result.includes('class="giscus"'));
    assert.ok(result.includes('data-repo="bagrounds/test"'));
  });

  it("returns unchanged HTML when no giscus div", () => {
    const html = '<html><body data-slug="page"><div>content</div></body></html>';
    const commentsMap: CommentsMap = {
      "/page": [
        {
          author: "u",
          authorUrl: "https://github.com/u",
          bodyHtml: "<p>Hi</p>",
          createdAt: "2024-01-01T00:00:00Z",
        },
      ],
    };
    assert.equal(injectStaticComments(html, commentsMap), html);
  });

  it("handles index slug mapping to root pathname", () => {
    const indexHtml = `<html><body data-slug="index"><div class="giscus" data-repo="test"></div></body></html>`;
    const commentsMap: CommentsMap = {
      "/": [
        {
          author: "u",
          authorUrl: "https://github.com/u",
          bodyHtml: "<p>Root page comment</p>",
          createdAt: "2024-01-01T00:00:00Z",
        },
      ],
    };
    const result = injectStaticComments(indexHtml, commentsMap);
    assert.ok(result.includes("data-static-giscus"));
  });

  it("handles giscus div with display class prefix", () => {
    const html = `<html><body data-slug="page"><div class="desktop-only giscus" data-repo="test"></div></body></html>`;
    const commentsMap: CommentsMap = {
      "/page": [
        {
          author: "u",
          authorUrl: "https://github.com/u",
          bodyHtml: "<p>Comment</p>",
          createdAt: "2024-01-01T00:00:00Z",
        },
      ],
    };
    const result = injectStaticComments(html, commentsMap);
    assert.ok(result.includes("data-static-giscus"));
  });

  it("returns same HTML with empty comments map", () => {
    const htmlSamples = [
      sampleHtml,
      "<html><body><div>hello</div></body></html>",
      "",
      '<body data-slug="x"><div class="giscus"></div></body>',
    ];
    htmlSamples.forEach((html) => {
      assert.equal(injectStaticComments(html, {}), html);
    });
  });

  it("returns unchanged HTML when no data-slug", () => {
    const noSlugHtmls = [
      "<html><body><div>no slug</div></body></html>",
      "<div>fragment</div>",
      "",
    ];
    const map: CommentsMap = {
      "/page": [
        {
          author: "u",
          authorUrl: "https://github.com/u",
          bodyHtml: "<p>x</p>",
          createdAt: "2024-01-01T00:00:00Z",
        },
      ],
    };
    noSlugHtmls.forEach((html) => {
      assert.equal(injectStaticComments(html, map), html);
    });
  });
});
