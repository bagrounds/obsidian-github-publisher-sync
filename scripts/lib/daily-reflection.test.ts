/**
 * Tests for scripts/lib/daily-reflection.ts — Daily reflection management.
 *
 * Covers pure functions (string manipulation) and I/O functions (filesystem).
 * Uses temporary directories for filesystem tests, matching existing test patterns.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  buildReflectionContent,
  buildSeriesSectionHeading,
  buildPostLink,
  addForwardLink,
  insertPostLink,
  findPreviousReflectionDate,
  ensureDailyReflection,
  updateDailyReflection,
} from "./daily-reflection.ts";
import { lookupSeries } from "./blog-series-config.ts";

// --- Test Helpers ---

const makeTmpDir = (): string => fs.mkdtempSync(path.join(os.tmpdir(), "reflection-test-"));

const cleanTmpDir = (dir: string): void => fs.rmSync(dir, { recursive: true });

const CHICKIE_LOO = lookupSeries("chickie-loo");
const AUTO_BLOG_ZERO = lookupSeries("auto-blog-zero");

// --- Pure Function Tests ---

describe("buildReflectionContent", () => {
  it("generates correct frontmatter and heading", () => {
    const content = buildReflectionContent("2026-03-23");
    assert.ok(content.includes("share: true"));
    assert.ok(content.includes("title: 2026-03-23"));
    assert.ok(content.includes("URL: https://bagrounds.org/reflections/2026-03-23"));
    assert.ok(content.includes('Author: "[[bryan-grounds]]"'));
    assert.ok(content.includes("# 2026-03-23"));
  });

  it("includes back link when previousDate is provided", () => {
    const content = buildReflectionContent("2026-03-23", "2026-03-22");
    assert.ok(content.includes("[[reflections/2026-03-22|⏮️]]"));
  });

  it("omits back link when no previousDate", () => {
    const content = buildReflectionContent("2026-03-23");
    assert.ok(!content.includes("⏮️"));
    assert.ok(content.includes("[[index|Home]] > [[reflections/index|Reflections]]"));
  });

  it("includes nav breadcrumb", () => {
    const content = buildReflectionContent("2026-03-23", "2026-03-22");
    assert.ok(content.includes("[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/2026-03-22|⏮️]]"));
  });

  it("ends with newline", () => {
    const content = buildReflectionContent("2026-03-23");
    assert.ok(content.endsWith("\n"));
  });

  it("aliases match title", () => {
    const content = buildReflectionContent("2026-03-23");
    assert.ok(content.includes("aliases:\n  - 2026-03-23"));
  });
});

describe("buildSeriesSectionHeading", () => {
  it("formats chickie-loo heading", () => {
    assert.equal(buildSeriesSectionHeading(CHICKIE_LOO), "## [[chickie-loo/index|🐔 Chickie Loo]]");
  });

  it("formats auto-blog-zero heading", () => {
    assert.equal(buildSeriesSectionHeading(AUTO_BLOG_ZERO), "## [[auto-blog-zero/index|🤖 Auto Blog Zero]]");
  });
});

describe("buildPostLink", () => {
  it("formats wiki link with series prefix", () => {
    const link = buildPostLink("chickie-loo", "2026-03-23-my-post", "2026-03-23 | 🐔 My Post 🐔");
    assert.equal(link, "- [[chickie-loo/2026-03-23-my-post|2026-03-23 | 🐔 My Post 🐔]]");
  });

  it("handles complex titles with special characters", () => {
    const link = buildPostLink("auto-blog-zero", "2026-03-23-the-crucible", "2026-03-23 | 🤖 The Crucible: A Test 🤖");
    assert.equal(link, "- [[auto-blog-zero/2026-03-23-the-crucible|2026-03-23 | 🤖 The Crucible: A Test 🤖]]");
  });
});

describe("addForwardLink", () => {
  it("adds forward link after back link", () => {
    const content = "[[reflections/2026-03-22|⏮️]]\n# 2026-03-23\n";
    const updated = addForwardLink(content, "2026-03-24");
    assert.ok(updated.includes("⏮️]] [[reflections/2026-03-24|⏭️]]"));
  });

  it("is idempotent — skips if forward link already exists", () => {
    const content = "[[reflections/2026-03-22|⏮️]] [[reflections/2026-03-24|⏭️]]\n# 2026-03-23\n";
    const updated = addForwardLink(content, "2026-03-25");
    assert.equal(updated, content);
  });

  it("returns content unchanged when no back link marker exists", () => {
    const content = "# 2026-03-23\nNo navigation here\n";
    const updated = addForwardLink(content, "2026-03-24");
    assert.equal(updated, content);
  });
});

describe("insertPostLink", () => {
  const baseContent = [
    "---", "share: true", "title: 2026-03-23", "---",
    "[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/2026-03-22|⏮️]]",
    "# 2026-03-23",
    "",
  ].join("\n") + "\n";

  it("creates new section when none exists", () => {
    const updated = insertPostLink(baseContent, CHICKIE_LOO, "2026-03-23-my-post", "2026-03-23 | 🐔 My Post 🐔");
    assert.ok(updated.includes("## [[chickie-loo/index|🐔 Chickie Loo]]"));
    assert.ok(updated.includes("- [[chickie-loo/2026-03-23-my-post|2026-03-23 | 🐔 My Post 🐔]]"));
  });

  it("appends link to existing section", () => {
    const withSection = baseContent + "\n## [[chickie-loo/index|🐔 Chickie Loo]]\n- [[chickie-loo/2026-03-23-post1|Title 1]]\n";
    const updated = insertPostLink(withSection, CHICKIE_LOO, "2026-03-23-post2", "Title 2");
    assert.ok(updated.includes("- [[chickie-loo/2026-03-23-post1|Title 1]]"));
    assert.ok(updated.includes("- [[chickie-loo/2026-03-23-post2|Title 2]]"));
    const lines = updated.split("\n");
    const post1Idx = lines.findIndex((l) => l.includes("post1"));
    const post2Idx = lines.findIndex((l) => l.includes("post2"));
    assert.ok(post2Idx > post1Idx, "new link should be after existing link");
  });

  it("is idempotent — skips if link already exists", () => {
    const withLink = baseContent + "\n## [[chickie-loo/index|🐔 Chickie Loo]]\n- [[chickie-loo/2026-03-23-post|Title]]\n";
    const updated = insertPostLink(withLink, CHICKIE_LOO, "2026-03-23-post", "Title");
    assert.equal(updated, withLink);
  });

  it("inserts new section before embed sections", () => {
    const withEmbed = baseContent + "\n## 🐦 Tweet\n<embed/>\n";
    const updated = insertPostLink(withEmbed, CHICKIE_LOO, "2026-03-23-post", "Title");
    const sectionIdx = updated.indexOf("## [[chickie-loo/index|🐔 Chickie Loo]]");
    const embedIdx = updated.indexOf("## 🐦 Tweet");
    assert.ok(sectionIdx >= 0, "section should be inserted");
    assert.ok(embedIdx >= 0, "embed section should still exist");
    assert.ok(sectionIdx < embedIdx, "series section should be before embed section");
  });

  it("inserts before bluesky embed section", () => {
    const withEmbed = baseContent + "\n## 🦋 Bluesky\n<embed/>\n";
    const updated = insertPostLink(withEmbed, AUTO_BLOG_ZERO, "2026-03-23-post", "Title");
    const sectionIdx = updated.indexOf("## [[auto-blog-zero/index|🤖 Auto Blog Zero]]");
    const embedIdx = updated.indexOf("## 🦋 Bluesky");
    assert.ok(sectionIdx < embedIdx);
  });

  it("inserts before mastodon embed section", () => {
    const withEmbed = baseContent + "\n## 🐘 Mastodon\n<embed/>\n";
    const updated = insertPostLink(withEmbed, AUTO_BLOG_ZERO, "2026-03-23-post", "Title");
    const sectionIdx = updated.indexOf("## [[auto-blog-zero/index|🤖 Auto Blog Zero]]");
    const embedIdx = updated.indexOf("## 🐘 Mastodon");
    assert.ok(sectionIdx < embedIdx);
  });

  it("preserves existing sections when adding new one", () => {
    const withChickie = baseContent + "\n## [[chickie-loo/index|🐔 Chickie Loo]]\n- [[chickie-loo/2026-03-23-post|CL Title]]\n";
    const updated = insertPostLink(withChickie, AUTO_BLOG_ZERO, "2026-03-23-post", "ABZ Title");
    assert.ok(updated.includes("## [[chickie-loo/index|🐔 Chickie Loo]]"));
    assert.ok(updated.includes("- [[chickie-loo/2026-03-23-post|CL Title]]"));
    assert.ok(updated.includes("## [[auto-blog-zero/index|🤖 Auto Blog Zero]]"));
    assert.ok(updated.includes("- [[auto-blog-zero/2026-03-23-post|ABZ Title]]"));
  });

  it("handles content with multiple embed sections", () => {
    const withEmbeds = baseContent + "\n## 🦋 Bluesky\n<bsky/>\n\n## 🐘 Mastodon\n<masto/>\n";
    const updated = insertPostLink(withEmbeds, CHICKIE_LOO, "2026-03-23-post", "Title");
    const sectionIdx = updated.indexOf("## [[chickie-loo/index|🐔 Chickie Loo]]");
    const bskyIdx = updated.indexOf("## 🦋 Bluesky");
    const mastoIdx = updated.indexOf("## 🐘 Mastodon");
    assert.ok(sectionIdx < bskyIdx);
    assert.ok(sectionIdx < mastoIdx);
  });

  it("adds section between existing content sections and embed sections", () => {
    const content = [
      baseContent.trimEnd(),
      "",
      "## [[chickie-loo/index|🐔 Chickie Loo]]",
      "- [[chickie-loo/2026-03-23-post|CL Title]]",
      "",
      "## 🐦 Tweet",
      "<tweet/>",
      "",
    ].join("\n");
    const updated = insertPostLink(content, AUTO_BLOG_ZERO, "2026-03-23-post", "ABZ Title");
    const clIdx = updated.indexOf("## [[chickie-loo/index|🐔 Chickie Loo]]");
    const abzIdx = updated.indexOf("## [[auto-blog-zero/index|🤖 Auto Blog Zero]]");
    const tweetIdx = updated.indexOf("## 🐦 Tweet");
    assert.ok(clIdx < abzIdx, "chickie-loo section should be before auto-blog-zero");
    assert.ok(abzIdx < tweetIdx, "auto-blog-zero section should be before tweet embed");
  });
});

// --- I/O Function Tests ---

describe("findPreviousReflectionDate", () => {
  it("returns undefined for non-existent directory", () => {
    assert.equal(findPreviousReflectionDate("/tmp/nonexistent-reflections", "2026-03-23"), undefined);
  });

  it("returns undefined for empty directory", () => {
    const tmpDir = makeTmpDir();
    try {
      assert.equal(findPreviousReflectionDate(tmpDir, "2026-03-23"), undefined);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns most recent date before today", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-20.md"), "");
      fs.writeFileSync(path.join(tmpDir, "2026-03-21.md"), "");
      fs.writeFileSync(path.join(tmpDir, "2026-03-22.md"), "");
      assert.equal(findPreviousReflectionDate(tmpDir, "2026-03-23"), "2026-03-22");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("excludes today's date", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-22.md"), "");
      fs.writeFileSync(path.join(tmpDir, "2026-03-23.md"), "");
      assert.equal(findPreviousReflectionDate(tmpDir, "2026-03-23"), "2026-03-22");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("excludes non-date files", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "index.md"), "");
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "");
      fs.writeFileSync(path.join(tmpDir, "2026-03-22.md"), "");
      assert.equal(findPreviousReflectionDate(tmpDir, "2026-03-23"), "2026-03-22");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("handles gaps in dates", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-15.md"), "");
      fs.writeFileSync(path.join(tmpDir, "2026-03-20.md"), "");
      assert.equal(findPreviousReflectionDate(tmpDir, "2026-03-23"), "2026-03-20");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });
});

describe("ensureDailyReflection", () => {
  it("creates new reflection when none exists", () => {
    const tmpDir = makeTmpDir();
    try {
      const result = ensureDailyReflection(tmpDir, "2026-03-23");
      assert.equal(result.created, true);
      assert.ok(fs.existsSync(path.join(tmpDir, "2026-03-23.md")));
      const content = fs.readFileSync(path.join(tmpDir, "2026-03-23.md"), "utf-8");
      assert.ok(content.includes("title: 2026-03-23"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("does not overwrite existing reflection", () => {
    const tmpDir = makeTmpDir();
    try {
      const existing = "---\nshare: true\ntitle: Custom Title\n---\n# Custom\n";
      fs.writeFileSync(path.join(tmpDir, "2026-03-23.md"), existing, "utf-8");
      const result = ensureDailyReflection(tmpDir, "2026-03-23");
      assert.equal(result.created, false);
      assert.equal(fs.readFileSync(path.join(tmpDir, "2026-03-23.md"), "utf-8"), existing);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("includes back link to previous reflection", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-22.md"), "---\ntitle: 2026-03-22\n---\n[[reflections/2026-03-21|⏮️]]\n# 2026-03-22\n", "utf-8");
      const result = ensureDailyReflection(tmpDir, "2026-03-23");
      assert.equal(result.created, true);
      assert.equal(result.previousDate, "2026-03-22");
      const content = fs.readFileSync(path.join(tmpDir, "2026-03-23.md"), "utf-8");
      assert.ok(content.includes("[[reflections/2026-03-22|⏮️]]"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("adds forward link to previous reflection", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-22.md"), "---\ntitle: 2026-03-22\n---\n[[reflections/2026-03-21|⏮️]]\n# 2026-03-22\n", "utf-8");
      const result = ensureDailyReflection(tmpDir, "2026-03-23");
      assert.equal(result.forwardLinkAdded, true);
      const prevContent = fs.readFileSync(path.join(tmpDir, "2026-03-22.md"), "utf-8");
      assert.ok(prevContent.includes("[[reflections/2026-03-23|⏭️]]"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("does not add forward link if already present", () => {
    const tmpDir = makeTmpDir();
    try {
      const prevContent = "---\ntitle: 2026-03-22\n---\n[[reflections/2026-03-21|⏮️]] [[reflections/2026-03-23|⏭️]]\n# 2026-03-22\n";
      fs.writeFileSync(path.join(tmpDir, "2026-03-22.md"), prevContent, "utf-8");
      fs.writeFileSync(path.join(tmpDir, "2026-03-23.md"), "existing", "utf-8");
      const result = ensureDailyReflection(tmpDir, "2026-03-23");
      assert.equal(result.created, false);
      assert.equal(result.forwardLinkAdded, false);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("creates directory if it does not exist", () => {
    const tmpDir = makeTmpDir();
    const nestedDir = path.join(tmpDir, "reflections");
    try {
      const result = ensureDailyReflection(nestedDir, "2026-03-23");
      assert.equal(result.created, true);
      assert.ok(fs.existsSync(path.join(nestedDir, "2026-03-23.md")));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });
});

describe("updateDailyReflection", () => {
  it("creates reflection and inserts post link", () => {
    const tmpDir = makeTmpDir();
    const reflectionsDir = path.join(tmpDir, "reflections");
    fs.mkdirSync(reflectionsDir, { recursive: true });
    try {
      const result = updateDailyReflection(tmpDir, "2026-03-23", CHICKIE_LOO, "2026-03-23-my-post.md", "2026-03-23 | 🐔 My Post 🐔");
      assert.equal(result.reflectionCreated, true);
      assert.equal(result.sectionCreated, true);
      assert.equal(result.linkInserted, true);
      const content = fs.readFileSync(path.join(reflectionsDir, "2026-03-23.md"), "utf-8");
      assert.ok(content.includes("## [[chickie-loo/index|🐔 Chickie Loo]]"));
      assert.ok(content.includes("- [[chickie-loo/2026-03-23-my-post|2026-03-23 | 🐔 My Post 🐔]]"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("adds post link to existing reflection", () => {
    const tmpDir = makeTmpDir();
    const reflectionsDir = path.join(tmpDir, "reflections");
    fs.mkdirSync(reflectionsDir, { recursive: true });
    const existing = buildReflectionContent("2026-03-23", "2026-03-22");
    fs.writeFileSync(path.join(reflectionsDir, "2026-03-23.md"), existing, "utf-8");
    try {
      const result = updateDailyReflection(tmpDir, "2026-03-23", CHICKIE_LOO, "2026-03-23-my-post.md", "2026-03-23 | 🐔 My Post 🐔");
      assert.equal(result.reflectionCreated, false);
      assert.equal(result.sectionCreated, true);
      assert.equal(result.linkInserted, true);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("handles multiple series on the same day", () => {
    const tmpDir = makeTmpDir();
    const reflectionsDir = path.join(tmpDir, "reflections");
    fs.mkdirSync(reflectionsDir, { recursive: true });
    try {
      updateDailyReflection(tmpDir, "2026-03-23", CHICKIE_LOO, "2026-03-23-cl-post.md", "2026-03-23 | 🐔 CL Post 🐔");
      const result = updateDailyReflection(tmpDir, "2026-03-23", AUTO_BLOG_ZERO, "2026-03-23-abz-post.md", "2026-03-23 | 🤖 ABZ Post 🤖");
      assert.equal(result.reflectionCreated, false);
      assert.equal(result.sectionCreated, true);
      assert.equal(result.linkInserted, true);
      const content = fs.readFileSync(path.join(reflectionsDir, "2026-03-23.md"), "utf-8");
      assert.ok(content.includes("## [[chickie-loo/index|🐔 Chickie Loo]]"));
      assert.ok(content.includes("## [[auto-blog-zero/index|🤖 Auto Blog Zero]]"));
      assert.ok(content.includes("- [[chickie-loo/2026-03-23-cl-post|2026-03-23 | 🐔 CL Post 🐔]]"));
      assert.ok(content.includes("- [[auto-blog-zero/2026-03-23-abz-post|2026-03-23 | 🤖 ABZ Post 🤖]]"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("is idempotent — calling twice does not duplicate link", () => {
    const tmpDir = makeTmpDir();
    const reflectionsDir = path.join(tmpDir, "reflections");
    fs.mkdirSync(reflectionsDir, { recursive: true });
    try {
      updateDailyReflection(tmpDir, "2026-03-23", CHICKIE_LOO, "2026-03-23-post.md", "Title");
      const firstContent = fs.readFileSync(path.join(reflectionsDir, "2026-03-23.md"), "utf-8");
      const result = updateDailyReflection(tmpDir, "2026-03-23", CHICKIE_LOO, "2026-03-23-post.md", "Title");
      assert.equal(result.linkInserted, false);
      assert.equal(result.sectionCreated, false);
      const secondContent = fs.readFileSync(path.join(reflectionsDir, "2026-03-23.md"), "utf-8");
      assert.equal(firstContent, secondContent);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("handles forward link to previous day", () => {
    const tmpDir = makeTmpDir();
    const reflectionsDir = path.join(tmpDir, "reflections");
    fs.mkdirSync(reflectionsDir, { recursive: true });
    fs.writeFileSync(
      path.join(reflectionsDir, "2026-03-22.md"),
      "---\ntitle: 2026-03-22\n---\n[[reflections/2026-03-21|⏮️]]\n# 2026-03-22\n",
      "utf-8",
    );
    try {
      const result = updateDailyReflection(tmpDir, "2026-03-23", CHICKIE_LOO, "2026-03-23-post.md", "Title");
      assert.equal(result.forwardLinkAdded, true);
      assert.equal(result.previousDate, "2026-03-22");
      const prevContent = fs.readFileSync(path.join(reflectionsDir, "2026-03-22.md"), "utf-8");
      assert.ok(prevContent.includes("[[reflections/2026-03-23|⏭️]]"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("strips .md extension from filename in link target", () => {
    const tmpDir = makeTmpDir();
    const reflectionsDir = path.join(tmpDir, "reflections");
    fs.mkdirSync(reflectionsDir, { recursive: true });
    try {
      updateDailyReflection(tmpDir, "2026-03-23", CHICKIE_LOO, "2026-03-23-my-post.md", "Title");
      const content = fs.readFileSync(path.join(reflectionsDir, "2026-03-23.md"), "utf-8");
      assert.ok(content.includes("[[chickie-loo/2026-03-23-my-post|"));
      assert.ok(!content.includes(".md|"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });
});
