import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  findMostRecentPost,
  buildNavLine,
  addNextLinkToContent,
  updatePreviousPost,
} from "./blog-nav.ts";

describe("findMostRecentPost", () => {
  it("returns undefined for empty directories", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      assert.equal(findMostRecentPost(tmpDir, "some-series"), undefined);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("finds post in root series dir", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      const seriesDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(seriesDir);
      fs.writeFileSync(path.join(seriesDir, "2026-03-12-first.md"), "test");
      fs.writeFileSync(path.join(seriesDir, "2026-03-14-third.md"), "test");
      assert.equal(findMostRecentPost(tmpDir, "auto-blog-zero"), "2026-03-14-third.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("finds post in content series dir", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      const contentDir = path.join(tmpDir, "content", "auto-blog-zero");
      fs.mkdirSync(contentDir, { recursive: true });
      fs.writeFileSync(path.join(contentDir, "2026-03-15-latest.md"), "test");
      assert.equal(findMostRecentPost(tmpDir, "auto-blog-zero"), "2026-03-15-latest.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns most recent across both directories", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      const rootDir = path.join(tmpDir, "auto-blog-zero");
      const contentDir = path.join(tmpDir, "content", "auto-blog-zero");
      fs.mkdirSync(rootDir);
      fs.mkdirSync(contentDir, { recursive: true });
      fs.writeFileSync(path.join(rootDir, "2026-03-12-old.md"), "test");
      fs.writeFileSync(path.join(contentDir, "2026-03-15-newest.md"), "test");
      assert.equal(findMostRecentPost(tmpDir, "auto-blog-zero"), "2026-03-15-newest.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("deduplicates filenames across directories", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      const rootDir = path.join(tmpDir, "auto-blog-zero");
      const contentDir = path.join(tmpDir, "content", "auto-blog-zero");
      fs.mkdirSync(rootDir);
      fs.mkdirSync(contentDir, { recursive: true });
      fs.writeFileSync(path.join(rootDir, "2026-03-12-same.md"), "root");
      fs.writeFileSync(path.join(contentDir, "2026-03-12-same.md"), "content");
      assert.equal(findMostRecentPost(tmpDir, "auto-blog-zero"), "2026-03-12-same.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("excludes AGENTS.md and index.md", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      const seriesDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(seriesDir);
      fs.writeFileSync(path.join(seriesDir, "AGENTS.md"), "test");
      fs.writeFileSync(path.join(seriesDir, "index.md"), "test");
      assert.equal(findMostRecentPost(tmpDir, "auto-blog-zero"), undefined);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});

describe("buildNavLine", () => {
  it("builds nav line without prev link", () => {
    const navLink = "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]";
    const result = buildNavLine("auto-blog-zero", navLink, undefined);
    assert.equal(result, navLink);
  });

  it("builds nav line with prev link", () => {
    const navLink = "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]";
    const result = buildNavLine("auto-blog-zero", navLink, "2026-03-14-my-post.md");
    assert.equal(result, "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]] | [[auto-blog-zero/2026-03-14-my-post|⏮️]]");
  });

  it("strips .md extension from prev filename", () => {
    const navLink = "[[index|Home]] > [[chickie-loo/index|🐔 Chickie Loo]]";
    const result = buildNavLine("chickie-loo", navLink, "2026-03-15-weekly-recap.md");
    assert.ok(result.includes("[[chickie-loo/2026-03-15-weekly-recap|⏮️]]"));
    assert.ok(!result.includes(".md"));
  });
});

describe("addNextLinkToContent", () => {
  it("adds next link to wikilink nav line", () => {
    const content = [
      "---", "share: true", "title: Test", "---",
      "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]] | [[auto-blog-zero/2026-03-14-prev|⏮️]]",
      "# 2026-03-15 | 🤖 Test 🤖",
      "",
      "## Body",
    ].join("\n");
    const result = addNextLinkToContent(content, "auto-blog-zero", "2026-03-16-next-post.md");
    assert.ok(result);
    assert.ok(result.includes("[[auto-blog-zero/2026-03-16-next-post|⏭️]]"));
  });

  it("adds next link to markdown nav line", () => {
    const content = [
      "---", "share: true", "title: Test", "---",
      "[Home](../index.md) > [🤖 Auto Blog Zero](./index.md) | [⏮️](./2026-03-14-prev.md)",
      "# 2026-03-15 | 🤖 Test 🤖",
      "",
      "## Body",
    ].join("\n");
    const result = addNextLinkToContent(content, "auto-blog-zero", "2026-03-16-next-post.md");
    assert.ok(result);
    assert.ok(result.includes("[⏭️](./2026-03-16-next-post.md)"));
  });

  it("adds pipe separator when nav line has no prev link", () => {
    const content = [
      "---", "share: true", "title: Test", "---",
      "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]",
      "# 2026-03-15 | 🤖 Test 🤖",
      "",
      "## Body",
    ].join("\n");
    const result = addNextLinkToContent(content, "auto-blog-zero", "2026-03-16-next-post.md");
    assert.ok(result);
    assert.ok(result.includes("]] | [[auto-blog-zero/2026-03-16-next-post|⏭️]]"));
  });

  it("returns undefined when next link already present", () => {
    const content = [
      "---", "share: true", "title: Test", "---",
      "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]] | [[auto-blog-zero/2026-03-14-prev|⏮️]] [[auto-blog-zero/2026-03-16-next|⏭️]]",
      "# 2026-03-15 | 🤖 Test 🤖",
    ].join("\n");
    const result = addNextLinkToContent(content, "auto-blog-zero", "2026-03-17-newer.md");
    assert.equal(result, undefined);
  });

  it("returns undefined when no nav line found", () => {
    const content = "# Just a heading\n\n## Body";
    const result = addNextLinkToContent(content, "auto-blog-zero", "2026-03-16-next.md");
    assert.equal(result, undefined);
  });
});

describe("updatePreviousPost", () => {
  it("updates previous post in root series dir", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      const seriesDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(seriesDir);
      const prevContent = [
        "---", "share: true", "title: Test", "---",
        "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]",
        "# 2026-03-15 | 🤖 Test 🤖",
        "", "## Body",
      ].join("\n");
      fs.writeFileSync(path.join(seriesDir, "2026-03-15-test.md"), prevContent);

      const result = updatePreviousPost(tmpDir, "auto-blog-zero", "2026-03-15-test.md", "2026-03-16-new.md");
      assert.ok(result);
      const updated = fs.readFileSync(result, "utf-8");
      assert.ok(updated.includes("[[auto-blog-zero/2026-03-16-new|⏭️]]"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("falls back to content dir when not in root", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      const contentDir = path.join(tmpDir, "content", "auto-blog-zero");
      fs.mkdirSync(contentDir, { recursive: true });
      const prevContent = [
        "---", "share: true", "title: Test", "---",
        "[Home](../index.md) > [🤖 Auto Blog Zero](./index.md) | [⏮️](./2026-03-14-earlier.md)",
        "# 2026-03-15 | 🤖 Test 🤖",
        "", "## Body",
      ].join("\n");
      fs.writeFileSync(path.join(contentDir, "2026-03-15-test.md"), prevContent);

      const rootDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(rootDir, { recursive: true });

      const result = updatePreviousPost(tmpDir, "auto-blog-zero", "2026-03-15-test.md", "2026-03-16-new.md");
      assert.ok(result);
      const updated = fs.readFileSync(result, "utf-8");
      assert.ok(updated.includes("[⏭️](./2026-03-16-new.md)"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns undefined when previous post not found", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nav-test-"));
    try {
      const result = updatePreviousPost(tmpDir, "auto-blog-zero", "nonexistent.md", "2026-03-16-new.md");
      assert.equal(result, undefined);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});
