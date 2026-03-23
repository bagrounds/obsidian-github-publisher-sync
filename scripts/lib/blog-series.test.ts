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
  buildBackLink,
  buildForwardLink,
  filterCommentsAfterLastPost,
  updatePreviousPost,
  stripEmbedSections,
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

  it("excludes index.md and AGENTS.md", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "index.md"), "---\ntitle: Index\n---\n");
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "# AGENTS");
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

  it("tells AI to continue the series naturally without link instructions", () => {
    const posts = [{ filename: "2026-03-10-test.md", date: "2026-03-10", title: "Test Post", body: "Body text" }];
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: posts, comments: [], today: "2026-03-12" });
    assert.ok(prompt.user.includes("Continue the series naturally"));
    assert.ok(!prompt.user.includes("wikilinks"));
  });
});

describe("buildBackLink", () => {
  const series = BLOG_SERIES.get("auto-blog-zero")!;

  it("builds a wikilink to the previous post using its filename", () => {
    const prev = { filename: "2026-03-12-fully-automated-blogging.md", date: "2026-03-12", title: "2026-03-12 | 🤖 Fully Automated Blogging 🤖", body: "" };
    const link = buildBackLink(series, prev);
    assert.equal(link, "[[auto-blog-zero/2026-03-12-fully-automated-blogging|⏮️]]");
  });

  it("strips .md extension from filename", () => {
    const prev = { filename: "2026-03-15-weekly-recap.md", date: "2026-03-15", title: "Weekly Recap", body: "" };
    const link = buildBackLink(series, prev);
    assert.ok(!link.includes(".md"));
  });

  it("uses the series id as the path prefix", () => {
    const chickieSeries = BLOG_SERIES.get("chickie-loo")!;
    const prev = { filename: "2026-03-10-hello.md", date: "2026-03-10", title: "Hello", body: "" };
    const link = buildBackLink(chickieSeries, prev);
    assert.ok(link.startsWith("[[chickie-loo/"));
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
    assert.ok(!fm.includes("⏮"));
    assert.ok(!fm.includes("⏮️"));
  });

  it("includes correct nav link for chickie-loo", () => {
    const chickieSeries = BLOG_SERIES.get("chickie-loo")!;
    const fm = assembleFrontmatter(chickieSeries, "2026-03-12", "My Great Post", "my-great-post");
    assert.ok(fm.includes("[[index|Home]] > [[chickie-loo/index|🐔 Chickie Loo]]"));
  });

  it("appends back link on nav line when previous post provided", () => {
    const prev = { filename: "2026-03-11-previous-post.md", date: "2026-03-11", title: "Previous Post Title", body: "" };
    const navLine = assembleFrontmatter(series, "2026-03-12", "My Great Post", "my-great-post", prev)
      .split("\n").find((line) => line.includes("[[index|Home]]"));
    assert.ok(navLine?.includes("[[auto-blog-zero/2026-03-11-previous-post|⏮️]]"));
  });
});

describe("BLOG_SERIES priorityUser config", () => {
  it("auto-blog-zero has bagrounds as priority user", () => {
    assert.equal(BLOG_SERIES.get("auto-blog-zero")?.priorityUser, "bagrounds");
  });

  it("chickie-loo has ChickieLoo as priority user", () => {
    assert.equal(BLOG_SERIES.get("chickie-loo")?.priorityUser, "ChickieLoo");
  });

  it("systems-for-public-good has bagrounds as priority user", () => {
    assert.equal(BLOG_SERIES.get("systems-for-public-good")?.priorityUser, "bagrounds");
  });
});

describe("generateSeriesIndex", () => {
  it("generates dataview index excluding AGENTS", () => {
    const series = BLOG_SERIES.get("auto-blog-zero")!;
    const index = generateSeriesIndex(series, []);
    assert.ok(index.includes("```dataview"));
    assert.ok(index.includes('LIST FROM "auto-blog-zero"'));
    assert.ok(index.includes('file.name != "AGENTS"'));
    assert.ok(!index.includes('file.name != "IDEAS"'));
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
  it("appends model signature with blank line before it", () => {
    const body = "## My Post\n\nThis is content.";
    const result = appendModelSignature(body, "gemini-3.1-flash");
    assert.equal(result, "## My Post\n\nThis is content.\n\n✍️ Written by gemini-3.1-flash");
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

describe("filterCommentsAfterLastPost", () => {
  type C = { author: string; body: string; createdAt: string; isPriority: boolean };
  type P = { filename: string; date: string; title: string; body: string };
  const makeComment = (iso: string): C => ({ author: "test", body: "hi", createdAt: iso, isPriority: false });
  const makePost = (date: string): P => ({ filename: `${date}-post.md`, date, title: "Post", body: "" });

  it("returns all comments when no previous posts", () => {
    const comments = [makeComment("2026-03-10T12:00:00Z"), makeComment("2026-03-12T14:00:00Z")];
    assert.equal(filterCommentsAfterLastPost(comments, [], "16:00").length, 2);
  });

  it("filters out comments older than the exact post time", () => {
    const comments = [makeComment("2026-03-13T15:45:00Z"), makeComment("2026-03-13T16:30:00Z")];
    const filtered = filterCommentsAfterLastPost(comments, [makePost("2026-03-13")], "16:00");
    assert.equal(filtered.length, 1);
    assert.equal(filtered[0]!.createdAt, "2026-03-13T16:30:00Z");
  });

  it("excludes comments written minutes before the scheduled post time", () => {
    const comments = [makeComment("2026-03-14T15:45:00Z"), makeComment("2026-03-14T16:05:00Z")];
    const filtered = filterCommentsAfterLastPost(comments, [makePost("2026-03-14")], "16:00");
    assert.equal(filtered.length, 1);
    assert.equal(filtered[0]!.createdAt, "2026-03-14T16:05:00Z");
  });

  it("uses the correct post time for different series", () => {
    const comments = [makeComment("2026-03-14T14:50:00Z"), makeComment("2026-03-14T15:10:00Z")];
    const filtered = filterCommentsAfterLastPost(comments, [makePost("2026-03-14")], "15:00");
    assert.equal(filtered.length, 1);
    assert.equal(filtered[0]!.createdAt, "2026-03-14T15:10:00Z");
  });

  it("includes all comments from days after the last post", () => {
    const comments = [makeComment("2026-03-15T08:00:00Z"), makeComment("2026-03-16T10:00:00Z")];
    const filtered = filterCommentsAfterLastPost(comments, [makePost("2026-03-14")], "16:00");
    assert.equal(filtered.length, 2);
  });
});

describe("buildForwardLink", () => {
  const series = BLOG_SERIES.get("auto-blog-zero")!;

  it("builds a wikilink to the next post using its filename", () => {
    assert.equal(buildForwardLink(series, "2026-03-14-my-post.md"), "[[auto-blog-zero/2026-03-14-my-post|⏭️]]");
  });

  it("strips .md extension from filename", () => {
    assert.ok(!buildForwardLink(series, "2026-03-14-my-post.md").includes(".md"));
  });

  it("uses the series id as the path prefix", () => {
    const chickieSeries = BLOG_SERIES.get("chickie-loo")!;
    assert.ok(buildForwardLink(chickieSeries, "2026-03-14-hello.md").startsWith("[[chickie-loo/"));
  });
});

describe("updatePreviousPost", () => {
  const series = BLOG_SERIES.get("auto-blog-zero")!;

  it("adds a forward link to the nav line of the previous post", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-10-test.md"),
        `---\nshare: true\n---\n${series.navLink}\n## Test\n\nBody.\n`);
      const prev = { filename: "2026-03-10-test.md", date: "2026-03-10", title: "Test", body: "" };
      updatePreviousPost(tmpDir, prev, series, "2026-03-11-new-post.md");
      const updated = fs.readFileSync(path.join(tmpDir, "2026-03-10-test.md"), "utf-8");
      const navLine = updated.split("\n").find((line) => line.startsWith(series.navLink));
      assert.ok(navLine?.includes("[[auto-blog-zero/2026-03-11-new-post|⏭️]]"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("does not add a duplicate forward link if already present", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-10-test.md"),
        `---\nshare: true\n---\n${series.navLink} | [[auto-blog-zero/2026-03-11-new-post|⏭️]]\n## Test\n\nBody.\n`);
      const prev = { filename: "2026-03-10-test.md", date: "2026-03-10", title: "Test", body: "" };
      updatePreviousPost(tmpDir, prev, series, "2026-03-11-new-post.md");
      const updated = fs.readFileSync(path.join(tmpDir, "2026-03-10-test.md"), "utf-8");
      assert.equal((updated.match(/⏭/g) ?? []).length, 1);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("does nothing when the previous post file does not exist", () => {
    const prev = { filename: "nonexistent.md", date: "2026-03-10", title: "Test", body: "" };
    assert.doesNotThrow(() => updatePreviousPost("/tmp/nonexistent-dir", prev, series, "2026-03-11-new.md"));
  });
});

describe("stripEmbedSections", () => {
  it("returns body unchanged when no embed sections present", () => {
    const body = "## Hello\n\nSome content here.";
    assert.equal(stripEmbedSections(body), body);
  });

  it("strips tweet section from end of body", () => {
    const body = "## Hello\n\nContent.\n\n## 🐦 Tweet  \n<blockquote>tweet embed</blockquote>";
    assert.equal(stripEmbedSections(body), "## Hello\n\nContent.");
  });

  it("strips bluesky section from end of body", () => {
    const body = "## Hello\n\nContent.\n\n## 🦋 Bluesky  \n<blockquote>bluesky embed</blockquote>";
    assert.equal(stripEmbedSections(body), "## Hello\n\nContent.");
  });

  it("strips mastodon section from end of body", () => {
    const body = "## Hello\n\nContent.\n\n## 🐘 Mastodon  \n<iframe>mastodon embed</iframe>";
    assert.equal(stripEmbedSections(body), "## Hello\n\nContent.");
  });

  it("strips all embed sections when multiple are present", () => {
    const body = "## Hello\n\nContent.\n\n## 🐦 Tweet  \n<blockquote>tweet</blockquote>\n\n## 🦋 Bluesky  \n<blockquote>bluesky</blockquote>\n\n## 🐘 Mastodon  \n<iframe>mastodon</iframe>";
    assert.equal(stripEmbedSections(body), "## Hello\n\nContent.");
  });

  it("handles empty body", () => {
    assert.equal(stripEmbedSections(""), "");
  });

  it("preserves content before the first embed section", () => {
    const body = "## Post Title\n\nParagraph one.\n\n## Analysis\n\nParagraph two.\n\n## 🐦 Tweet  \n<blockquote>embed</blockquote>";
    assert.equal(stripEmbedSections(body), "## Post Title\n\nParagraph one.\n\n## Analysis\n\nParagraph two.");
  });
});

describe("buildBlogPrompt embed stripping", () => {
  const series = BLOG_SERIES.get("auto-blog-zero")!;

  it("excludes social media embeds from post history in prompt", () => {
    const posts = [{
      filename: "2026-03-10-test.md",
      date: "2026-03-10",
      title: "Test Post",
      body: "Real content.\n\n## 🐦 Tweet  \n<blockquote>tweet embed</blockquote>\n\n## 🦋 Bluesky  \n<blockquote>bluesky embed</blockquote>",
    }];
    const prompt = buildBlogPrompt({ series, agentsMd: "test", previousPosts: posts, comments: [], today: "2026-03-12" });
    assert.ok(prompt.user.includes("Real content."));
    assert.ok(!prompt.user.includes("🐦 Tweet"));
    assert.ok(!prompt.user.includes("blockquote"));
    assert.ok(!prompt.user.includes("🦋 Bluesky"));
  });
});
