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
  appendModelSignature,
  todayPacific,
  assembleFrontmatter,
} from "./blog-series.ts";

describe("readSeriesPosts", () => {
  it("returns empty array for non-existent directory", () => {
    assert.deepEqual(readSeriesPosts("/tmp/nonexistent-blog-series"), []);
  });

  it("reads posts sorted newest first", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-01-first.md"), "---\ntitle: First Post\n---\nBody one");
      fs.writeFileSync(path.join(tmpDir, "2026-03-02-second.md"), "---\ntitle: Second Post\n---\nBody two");
      fs.writeFileSync(path.join(tmpDir, "2026-03-03-third.md"), "---\ntitle: Third Post\n---\nBody three");

      const posts = readSeriesPosts(tmpDir);
      assert.equal(posts.length, 3);
      assert.equal(posts[0]?.filename, "2026-03-03-third.md");
      assert.equal(posts[2]?.filename, "2026-03-01-first.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("excludes index.md, AGENTS.md, and IDEAS.md", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "index.md"), "---\ntitle: Index\n---\n");
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "# AGENTS");
      fs.writeFileSync(path.join(tmpDir, "IDEAS.md"), "# IDEAS");
      fs.writeFileSync(path.join(tmpDir, "2026-03-01-post.md"), "---\ntitle: A Post\n---\nBody");

      assert.equal(readSeriesPosts(tmpDir).length, 1);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("extracts date and title from posts", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-15-my-post.md"), "---\ntitle: My Cool Title\n---\nBody");
      const posts = readSeriesPosts(tmpDir);
      assert.equal(posts[0]?.date, "2026-03-15");
      assert.equal(posts[0]?.title, "My Cool Title");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});

describe("readAgentsMd", () => {
  it("reads AGENTS.md when present", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "# My Blog Instructions\nBe awesome.");
      assert.ok(readAgentsMd(tmpDir).includes("My Blog Instructions"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns empty string when AGENTS.md is missing", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      assert.equal(readAgentsMd(tmpDir), "");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});

describe("buildBlogContext", () => {
  it("throws for unknown series", () => {
    assert.throws(() => buildBlogContext("nonexistent", "/tmp", [], "2026-03-12"), /Unknown blog series/);
  });

  it("builds context with posts and AGENTS.md", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      const seriesDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(seriesDir);
      fs.writeFileSync(path.join(seriesDir, "AGENTS.md"), "# Test Agent");
      fs.writeFileSync(path.join(seriesDir, "2026-03-10-test.md"), "---\ntitle: Test Post\n---\nBody");

      const ctx = buildBlogContext("auto-blog-zero", tmpDir, [], "2026-03-12");
      assert.equal(ctx.series.id, "auto-blog-zero");
      assert.equal(ctx.previousPosts.length, 1);
      assert.ok(ctx.agentsMd.includes("Test Agent"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});

describe("buildBlogPrompt", () => {
  const series = BLOG_SERIES.get("auto-blog-zero")!;

  it("uses AGENTS.md as system prompt", () => {
    const prompt = buildBlogPrompt({ series, agentsMd: "You are a test blog.", previousPosts: [], comments: [], today: "2026-03-12" });
    assert.equal(prompt.system, "You are a test blog.");
  });

  it("falls back when AGENTS.md is empty", () => {
    const prompt = buildBlogPrompt({ series, agentsMd: "", previousPosts: [], comments: [], today: "2026-03-12" });
    assert.ok(prompt.system.includes("Auto Blog Zero"));
  });

  it("includes previous posts and comments in user prompt", () => {
    const posts = [{ filename: "2026-03-10-test.md", date: "2026-03-10", title: "Test Post", body: "Body text" }];
    const comments = [{ author: "bagrounds", body: "Write about testing", createdAt: "2026-03-11", isPriority: true }];
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: posts, comments, today: "2026-03-12" });
    assert.ok(prompt.user.includes("Test Post"));
    assert.ok(prompt.user.includes("PRIORITY"));
    assert.ok(prompt.user.includes("Write about testing"));
  });

  it("tells AI to generate only body, not frontmatter", () => {
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: [], comments: [], today: "2026-03-12" });
    assert.ok(prompt.user.includes("Generate ONLY the blog post body"));
    assert.ok(prompt.user.includes("Do NOT generate frontmatter"));
  });

  it("instructs weekly recap on Sundays", () => {
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: [], comments: [], today: "2026-03-15" });
    assert.ok(prompt.user.includes("Weekly Recap"));
  });

  it("instructs monthly recap on last day of month", () => {
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: [], comments: [], today: "2026-04-30" });
    assert.ok(prompt.user.includes("Monthly Recap"));
  });

  it("instructs quarterly recap on last day of quarter", () => {
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: [], comments: [], today: "2026-03-31" });
    assert.ok(prompt.user.includes("Quarterly Recap"));
  });

  it("notes sparse comment traffic when no comments", () => {
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: [], comments: [], today: "2026-03-12" });
    assert.ok(prompt.user.includes("comments are very rare"));
  });

  it("uses wikilinks format for internal references", () => {
    const posts = [{ filename: "2026-03-10-test.md", date: "2026-03-10", title: "Test Post", body: "Body text" }];
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: posts, comments: [], today: "2026-03-12" });
    assert.ok(prompt.user.includes("wikilinks"));
    assert.ok(prompt.user.includes("[[auto-blog-zero/"));
  });
});

describe("assembleFrontmatter", () => {
  const series = BLOG_SERIES.get("auto-blog-zero")!;

  it("generates deterministic frontmatter with title and slug", () => {
    const fm = assembleFrontmatter(series, "2026-03-12", "My Great Post", "my-great-post");
    assert.ok(fm.includes("share: true"));
    assert.ok(fm.includes("2026-03-12 | 🤖 My Great Post 🤖"));
    assert.ok(fm.includes("URL: https://bagrounds.org/auto-blog-zero/2026-03-12-my-great-post"));
    assert.ok(fm.includes('Author: "[[auto-blog-zero]]"'));
    assert.ok(!fm.includes("[Your Title Here]"));
    assert.ok(fm.includes("[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]"));
  });

  it("includes correct nav link for auto-blog-zero", () => {
    const fm = assembleFrontmatter(series, "2026-03-12", "My Great Post", "my-great-post");
    assert.ok(fm.includes("[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]"));
  });

  it("includes correct nav link for chickie-loo", () => {
    const chickieSeries = BLOG_SERIES.get("chickie-loo")!;
    const fm = assembleFrontmatter(chickieSeries, "2026-03-12", "My Great Post", "my-great-post");
    assert.ok(fm.includes("[[index|Home]] > [[chickie-loo/index|🐔 Chickie Loo]]"));
  });
});

describe("generateSeriesIndex", () => {
  it("generates dataview index excluding AGENTS and IDEAS", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const index = generateSeriesIndex(series, []);
    assert.ok(index.includes("```dataview"));
    assert.ok(index.includes('LIST FROM "auto-blog-zero"'));
    assert.ok(index.includes('file.name != "AGENTS"'));
    assert.ok(index.includes('file.name != "IDEAS"'));
    assert.ok(index.includes("SORT file.name DESC"));
  });
});

describe("extractSlug", () => {
  it("extracts slug from dated filename", () => assert.equal(extractSlug("2026-03-12-my-post.md"), "my-post"));
  it("handles filename without date", () => assert.equal(extractSlug("just-a-name.md"), "just-a-name"));
  it("handles date-only filename", () => assert.equal(extractSlug("2026-03-12.md"), ""));
});

describe("parseGeneratedPost", () => {
  it("parses valid post with markdown heading", () => {
    const raw = `## Hello World\n\n${"Lorem ipsum ".repeat(20)}`;
    const result = parseGeneratedPost(raw);
    assert.ok(result);
    assert.equal(result.title, "Hello World");
  });

  it("rejects post without heading", () => assert.equal(parseGeneratedPost("Just some body text here."), null));
  it("rejects too-short post", () => assert.equal(parseGeneratedPost("## Title\nShort"), null));
});

describe("appendModelSignature", () => {
  it("appends model signature with placeholder", () => {
    const body = "## My Post\n\nThis is content.";
    const result = appendModelSignature(body, "gemini-3.1-flash");
    assert.equal(result, "## My Post\n\nThis is content.\n✍️ Written by gemini-3.1-flash");
  });

  it("works with different model names", () => {
    const body = "## Post\n\nContent here.";
    const result = appendModelSignature(body, "claude-3-opus");
    assert.ok(result.includes("✍️ Written by claude-3-opus"));
  });
});

describe("todayPacific", () => {
  it("returns YYYY-MM-DD format", () => {
    assert.match(todayPacific(), /^\d{4}-\d{2}-\d{2}$/);
  });
});
