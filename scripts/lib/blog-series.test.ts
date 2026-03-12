/**
 * Tests for scripts/lib/blog-series.ts — Blog series infrastructure.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  BLOG_SERIES,
  readSeriesPosts,
  readAgentsMd,
  buildBlogContext,
  buildBlogPrompt,
  generateSeriesIndex,
  extractSlug,
  parseGeneratedPost,
} from "./blog-series.ts";

// --- BLOG_SERIES registry ---

describe("BLOG_SERIES", () => {
  it("contains auto-blog-zero", () => {
    const series = BLOG_SERIES.get("auto-blog-zero");
    assert.ok(series);
    assert.equal(series.id, "auto-blog-zero");
    assert.equal(series.icon, "🤖");
  });

  it("contains chickie-loo", () => {
    const series = BLOG_SERIES.get("chickie-loo");
    assert.ok(series);
    assert.equal(series.id, "chickie-loo");
    assert.equal(series.icon, "🐔");
  });

  it("each series has required fields", () => {
    for (const [id, series] of BLOG_SERIES) {
      assert.equal(series.id, id);
      assert.ok(series.name, `${id} missing name`);
      assert.ok(series.icon, `${id} missing icon`);
      assert.ok(series.author, `${id} missing author`);
      assert.ok(series.baseUrl, `${id} missing baseUrl`);
      assert.ok(series.defaultTags.length > 0, `${id} missing defaultTags`);
    }
  });
});

// --- readSeriesPosts ---

describe("readSeriesPosts", () => {
  it("returns empty array for non-existent directory", () => {
    const result = readSeriesPosts("/tmp/nonexistent-blog-series");
    assert.deepEqual(result, []);
  });

  it("reads posts sorted newest first", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(
        path.join(tmpDir, "2026-03-01-first.md"),
        "---\ntitle: First Post\n---\nBody one",
      );
      fs.writeFileSync(
        path.join(tmpDir, "2026-03-02-second.md"),
        "---\ntitle: Second Post\n---\nBody two",
      );
      fs.writeFileSync(
        path.join(tmpDir, "2026-03-03-third.md"),
        "---\ntitle: Third Post\n---\nBody three",
      );

      const posts = readSeriesPosts(tmpDir);
      assert.equal(posts.length, 3);
      assert.equal(posts[0]!.filename, "2026-03-03-third.md");
      assert.equal(posts[1]!.filename, "2026-03-02-second.md");
      assert.equal(posts[2]!.filename, "2026-03-01-first.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("excludes index.md", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "index.md"), "---\ntitle: Index\n---\n");
      fs.writeFileSync(
        path.join(tmpDir, "2026-03-01-post.md"),
        "---\ntitle: A Post\n---\nBody",
      );

      const posts = readSeriesPosts(tmpDir);
      assert.equal(posts.length, 1);
      assert.equal(posts[0]!.filename, "2026-03-01-post.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("excludes AGENTS.md", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "# AGENTS\nSome instructions");
      fs.writeFileSync(
        path.join(tmpDir, "2026-03-01-post.md"),
        "---\ntitle: A Post\n---\nBody",
      );

      const posts = readSeriesPosts(tmpDir);
      assert.equal(posts.length, 1);
      assert.equal(posts[0]!.filename, "2026-03-01-post.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("extracts date from filename", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(
        path.join(tmpDir, "2026-03-15-my-post.md"),
        "---\ntitle: My Post\n---\nBody",
      );

      const posts = readSeriesPosts(tmpDir);
      assert.equal(posts[0]!.date, "2026-03-15");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("extracts title from frontmatter", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(
        path.join(tmpDir, "2026-03-01-post.md"),
        "---\ntitle: My Cool Title\n---\nBody",
      );

      const posts = readSeriesPosts(tmpDir);
      assert.equal(posts[0]!.title, "My Cool Title");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});

// --- buildBlogContext ---

describe("buildBlogContext", () => {
  it("throws for unknown series", () => {
    assert.throws(() => buildBlogContext("nonexistent", "/tmp", [], "2026-03-12"), {
      message: /Unknown blog series: nonexistent/,
    });
  });

  it("builds context with empty posts and comments", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      const ctx = buildBlogContext("auto-blog-zero", tmpDir, [], "2026-03-12");
      assert.equal(ctx.series.id, "auto-blog-zero");
      assert.deepEqual(ctx.previousPosts, []);
      assert.deepEqual(ctx.comments, []);
      assert.equal(ctx.today, "2026-03-12");
      assert.equal(ctx.agentsMd, ""); // no AGENTS.md in tmp dir
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("reads posts from the series directory", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      const seriesDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(seriesDir);
      fs.writeFileSync(
        path.join(seriesDir, "2026-03-10-test.md"),
        "---\ntitle: Test Post\n---\nBody",
      );

      const ctx = buildBlogContext("auto-blog-zero", tmpDir, [], "2026-03-12");
      assert.equal(ctx.previousPosts.length, 1);
      assert.equal(ctx.previousPosts[0]!.title, "Test Post");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("reads AGENTS.md into context", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      const seriesDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(seriesDir);
      fs.writeFileSync(path.join(seriesDir, "AGENTS.md"), "# Test Agent\nInstructions here.");

      const ctx = buildBlogContext("auto-blog-zero", tmpDir, [], "2026-03-12");
      assert.ok(ctx.agentsMd.includes("Test Agent"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});

// --- buildBlogPrompt ---

describe("buildBlogPrompt", () => {
  it("uses AGENTS.md as system prompt when present", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const agentsMd = "# Auto Blog Zero\nYou are a test blog.";
    const ctx = { series, agentsMd, previousPosts: [], comments: [], today: "2026-03-12" };
    const prompt = buildBlogPrompt(ctx);
    assert.equal(prompt.system, agentsMd);
  });

  it("falls back to minimal prompt when AGENTS.md is empty", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const ctx = { series, agentsMd: "", previousPosts: [], comments: [], today: "2026-03-12" };
    const prompt = buildBlogPrompt(ctx);
    assert.ok(prompt.system.includes("Auto Blog Zero"));
    assert.ok(prompt.system.includes("automated blog"));
  });

  it("includes today's date in user prompt", () => {
    const series = BLOG_SERIES.get("chickie-loo")!;
    const ctx = { series, agentsMd: "You are Chickie Loo.", previousPosts: [], comments: [], today: "2026-03-15" };
    const prompt = buildBlogPrompt(ctx);
    assert.ok(prompt.user.includes("2026-03-15"));
  });

  it("mentions first post when no previous posts", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const ctx = { series, agentsMd: "test", previousPosts: [], comments: [], today: "2026-03-12" };
    const prompt = buildBlogPrompt(ctx);
    assert.ok(prompt.user.includes("FIRST post"));
  });

  it("includes previous posts in prompt", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const posts = [
      { filename: "2026-03-10-test.md", date: "2026-03-10", title: "Test Post", body: "Some body", tags: [] },
    ];
    const ctx = { series, agentsMd: "test", previousPosts: posts, comments: [], today: "2026-03-12" };
    const prompt = buildBlogPrompt(ctx);
    assert.ok(prompt.user.includes("Test Post"));
    assert.ok(prompt.user.includes("Some body"));
  });

  it("includes comments with priority marker", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const comments = [
      { author: "alice", body: "Great post!", createdAt: "2026-03-11", isPriority: false },
      { author: "bagrounds", body: "Write about testing", createdAt: "2026-03-11", isPriority: true },
    ];
    const ctx = { series, agentsMd: "test", previousPosts: [], comments, today: "2026-03-12" };
    const prompt = buildBlogPrompt(ctx);
    assert.ok(prompt.user.includes("PRIORITY"));
    assert.ok(prompt.user.includes("Write about testing"));
    assert.ok(prompt.user.includes("Great post!"));
  });

  it("includes frontmatter template with series details", () => {
    const series = BLOG_SERIES.get("chickie-loo")!;
    const ctx = { series, agentsMd: "test", previousPosts: [], comments: [], today: "2026-03-12" };
    const prompt = buildBlogPrompt(ctx);
    assert.ok(prompt.user.includes("[[chickie-loo]]"));
    assert.ok(prompt.user.includes("chickie-loo"));
    assert.ok(prompt.user.includes("ranch-life"));
  });

  it("truncates very long post bodies", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const longBody = "x".repeat(5000);
    const posts = [
      { filename: "2026-03-10-long.md", date: "2026-03-10", title: "Long Post", body: longBody, tags: [] },
    ];
    const ctx = { series, agentsMd: "test", previousPosts: posts, comments: [], today: "2026-03-12" };
    const prompt = buildBlogPrompt(ctx);
    assert.ok(prompt.user.includes("[...truncated...]"));
    assert.ok(!prompt.user.includes("x".repeat(5000)));
  });
});

// --- generateSeriesIndex ---

describe("generateSeriesIndex", () => {
  it("generates index with dataview query", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const posts = [
      { filename: "2026-03-12-first.md", date: "2026-03-12", title: "First Post", body: "", tags: [] },
    ];
    const index = generateSeriesIndex(series, posts);

    assert.ok(index.includes("share: true"));
    assert.ok(index.includes("🤖 Auto Blog Zero"));
    assert.ok(index.includes("[Home](../index.md)"));
    assert.ok(index.includes("```dataview"));
    assert.ok(index.includes('LIST FROM "auto-blog-zero"'));
    assert.ok(index.includes("SORT file.name DESC"));
    // Should NOT contain static post links
    assert.ok(!index.includes("[First Post]"));
  });

  it("generates index with zero posts (same dataview query)", () => {
    const series = BLOG_SERIES.get("chickie-loo")!;
    const index = generateSeriesIndex(series, []);
    assert.ok(index.includes("🐔 Chickie Loo"));
    assert.ok(index.includes("```dataview"));
    assert.ok(index.includes('LIST FROM "chickie-loo"'));
  });

  it("excludes AGENTS from dataview query", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const index = generateSeriesIndex(series, []);
    assert.ok(index.includes('file.name != "AGENTS"'));
  });
});

// --- extractSlug ---

describe("extractSlug", () => {
  it("extracts slug from dated filename", () => {
    assert.equal(extractSlug("2026-03-12-my-cool-post.md"), "my-cool-post");
  });

  it("handles filename without date prefix", () => {
    assert.equal(extractSlug("just-a-name.md"), "just-a-name");
  });

  it("handles filename with only date", () => {
    assert.equal(extractSlug("2026-03-12.md"), "");
  });

  it("handles filename with date and extension only", () => {
    assert.equal(extractSlug("2026-03-12-.md"), "");
  });
});

// --- parseGeneratedPost ---

describe("parseGeneratedPost", () => {
  it("parses valid post", () => {
    const raw = `---\ntitle: My Title\ntags:\n  - test\n---\n# My Title\n\n${"Lorem ipsum ".repeat(50)}`;
    const result = parseGeneratedPost(raw);
    assert.ok(result);
    assert.equal(result.title, "My Title");
    assert.ok(result.content.startsWith("---"));
  });

  it("rejects post without frontmatter", () => {
    const raw = "# No Frontmatter\n\nJust body text.";
    assert.equal(parseGeneratedPost(raw), null);
  });

  it("rejects post without closing frontmatter", () => {
    const raw = "---\ntitle: Broken\nNo closing delimiter and some more text to pad length";
    assert.equal(parseGeneratedPost(raw), null);
  });

  it("rejects post without title", () => {
    const raw = `---\nnotitle: true\n---\n${"x".repeat(600)}`;
    assert.equal(parseGeneratedPost(raw), null);
  });

  it("rejects post that is too short", () => {
    const raw = "---\ntitle: Short\n---\nToo short.";
    assert.equal(parseGeneratedPost(raw), null);
  });

  it("handles whitespace around post", () => {
    const raw = `  \n---\ntitle: Whitespace Test\n---\n# Test\n\n${"Content ".repeat(100)}\n  `;
    const result = parseGeneratedPost(raw);
    assert.ok(result);
    assert.equal(result.title, "Whitespace Test");
  });
});

// --- readAgentsMd ---

describe("readAgentsMd", () => {
  it("reads AGENTS.md when present", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "# My Blog Instructions\nBe awesome.");
      const content = readAgentsMd(tmpDir);
      assert.ok(content.includes("My Blog Instructions"));
      assert.ok(content.includes("Be awesome"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns empty string when AGENTS.md is missing", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      const content = readAgentsMd(tmpDir);
      assert.equal(content, "");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});
