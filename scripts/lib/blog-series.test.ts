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
  todayPacific,
} from "./blog-series.ts";

// --- readSeriesPosts ---

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

// --- readAgentsMd ---

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

// --- buildBlogContext ---

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

// --- buildBlogPrompt ---

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
    const posts = [{ filename: "2026-03-10-test.md", date: "2026-03-10", title: "Test Post", body: "Body text", tags: [] }];
    const comments = [{ author: "bagrounds", body: "Write about testing", createdAt: "2026-03-11", isPriority: true }];
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: posts, comments, today: "2026-03-12" });
    assert.ok(prompt.user.includes("Test Post"));
    assert.ok(prompt.user.includes("PRIORITY"));
    assert.ok(prompt.user.includes("Write about testing"));
  });

  it("truncates very long post bodies", () => {
    const posts = [{ filename: "2026-03-10-long.md", date: "2026-03-10", title: "Long", body: "x".repeat(5000), tags: [] }];
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: posts, comments: [], today: "2026-03-12" });
    assert.ok(prompt.user.includes("[...truncated...]"));
  });
});

// --- generateSeriesIndex ---

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

// --- extractSlug ---

describe("extractSlug", () => {
  it("extracts slug from dated filename", () => assert.equal(extractSlug("2026-03-12-my-post.md"), "my-post"));
  it("handles filename without date", () => assert.equal(extractSlug("just-a-name.md"), "just-a-name"));
  it("handles date-only filename", () => assert.equal(extractSlug("2026-03-12.md"), ""));
});

// --- parseGeneratedPost ---

describe("parseGeneratedPost", () => {
  it("parses valid post", () => {
    const raw = `---\ntitle: My Title\n---\n# My Title\n\n${"Lorem ipsum ".repeat(50)}`;
    const result = parseGeneratedPost(raw);
    assert.ok(result);
    assert.equal(result.title, "My Title");
  });

  it("rejects post without frontmatter", () => assert.equal(parseGeneratedPost("# No FM\nBody"), null));
  it("rejects post without title", () => assert.equal(parseGeneratedPost(`---\nnotitle: x\n---\n${"x".repeat(600)}`), null));
  it("rejects too-short post", () => assert.equal(parseGeneratedPost("---\ntitle: S\n---\nShort"), null));
});

// --- todayPacific ---

describe("todayPacific", () => {
  it("returns YYYY-MM-DD format", () => {
    assert.match(todayPacific(), /^\d{4}-\d{2}-\d{2}$/);
  });
});
