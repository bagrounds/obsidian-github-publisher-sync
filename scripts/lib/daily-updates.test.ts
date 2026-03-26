/**
 * Tests for scripts/lib/daily-updates.ts — Daily reflection Updates section.
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
  UPDATES_SECTION_HEADER,
  buildUpdateLink,
  addUpdateLinks,
  extractTitleFromFile,
  addUpdateLinksToReflection,
} from "./daily-updates.ts";

// --- Test Helpers ---

const makeTmpDir = (): string => fs.mkdtempSync(path.join(os.tmpdir(), "updates-test-"));

const cleanTmpDir = (dir: string): void => fs.rmSync(dir, { recursive: true });

const baseReflection = [
  "---",
  "share: true",
  "title: 2026-03-23",
  "---",
  "[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/2026-03-22|⏮️]]",
  "# 2026-03-23",
  "",
  "## [[chickie-loo/index|🐔 Chickie Loo]]",
  "- [[chickie-loo/2026-03-23-post|🐔 Post Title]]",
  "",
  "## 🦋 Bluesky",
  "> embed content",
  "",
].join("\n");

// --- Pure Function Tests ---

describe("UPDATES_SECTION_HEADER", () => {
  it("uses rocket/cycle emoji", () => {
    assert.equal(UPDATES_SECTION_HEADER, "## 🔄 Updates");
  });
});

describe("buildUpdateLink", () => {
  it("formats wiki link with stripped .md extension", () => {
    const link = buildUpdateLink("chickie-loo/2026-03-23-post.md", "🐔 Post Title");
    assert.equal(link, "- [[chickie-loo/2026-03-23-post|🐔 Post Title]]");
  });

  it("handles paths without .md extension", () => {
    const link = buildUpdateLink("books/some-book", "📚 Some Book");
    assert.equal(link, "- [[books/some-book|📚 Some Book]]");
  });

  it("preserves complex titles", () => {
    const link = buildUpdateLink("articles/my-article.md", "The Art of Code: A Journey");
    assert.equal(link, "- [[articles/my-article|The Art of Code: A Journey]]");
  });
});

describe("addUpdateLinks", () => {
  it("creates new Updates section when none exists", () => {
    const content = "---\ntitle: 2026-03-23\n---\n# 2026-03-23\n";
    const updated = addUpdateLinks(content, [
      { relativePath: "books/some-book.md", title: "📚 Some Book" },
    ]);
    assert.ok(updated.includes(UPDATES_SECTION_HEADER));
    assert.ok(updated.includes("- [[books/some-book|📚 Some Book]]"));
  });

  it("appends to existing Updates section", () => {
    const content = [
      "---",
      "title: 2026-03-23",
      "---",
      "# 2026-03-23",
      "",
      UPDATES_SECTION_HEADER,
      "",
      "- [[books/book-one|📚 Book One]]",
      "",
    ].join("\n");
    const updated = addUpdateLinks(content, [
      { relativePath: "books/book-two.md", title: "📚 Book Two" },
    ]);
    assert.ok(updated.includes("- [[books/book-one|📚 Book One]]"));
    assert.ok(updated.includes("- [[books/book-two|📚 Book Two]]"));
    const lines = updated.split("\n");
    const oneIdx = lines.findIndex((l) => l.includes("book-one"));
    const twoIdx = lines.findIndex((l) => l.includes("book-two"));
    assert.ok(twoIdx > oneIdx, "new link should be after existing link");
  });

  it("is idempotent — skips already-present links", () => {
    const content = [
      "# 2026-03-23",
      "",
      UPDATES_SECTION_HEADER,
      "",
      "- [[books/some-book|📚 Some Book]]",
      "",
    ].join("\n");
    const updated = addUpdateLinks(content, [
      { relativePath: "books/some-book.md", title: "📚 Some Book" },
    ]);
    assert.equal(updated, content);
  });

  it("adds multiple links at once", () => {
    const content = "# 2026-03-23\n";
    const updated = addUpdateLinks(content, [
      { relativePath: "books/book-one.md", title: "📚 Book One" },
      { relativePath: "videos/vid.md", title: "📺 Video" },
    ]);
    assert.ok(updated.includes("- [[books/book-one|📚 Book One]]"));
    assert.ok(updated.includes("- [[videos/vid|📺 Video]]"));
  });

  it("filters out already-present links from a batch", () => {
    const content = [
      "# 2026-03-23",
      "",
      UPDATES_SECTION_HEADER,
      "",
      "- [[books/book-one|📚 Book One]]",
      "",
    ].join("\n");
    const updated = addUpdateLinks(content, [
      { relativePath: "books/book-one.md", title: "📚 Book One" },
      { relativePath: "books/book-two.md", title: "📚 Book Two" },
    ]);
    assert.ok(updated.includes("- [[books/book-two|📚 Book Two]]"));
    const bookOneCount = updated.split("book-one").length - 1;
    assert.equal(bookOneCount, 1, "should not duplicate existing link");
  });

  it("returns content unchanged when all links present", () => {
    const content = [
      "# 2026-03-23",
      "",
      UPDATES_SECTION_HEADER,
      "",
      "- [[books/book-one|📚 Book One]]",
      "- [[books/book-two|📚 Book Two]]",
      "",
    ].join("\n");
    const updated = addUpdateLinks(content, [
      { relativePath: "books/book-one.md", title: "📚 Book One" },
      { relativePath: "books/book-two.md", title: "📚 Book Two" },
    ]);
    assert.equal(updated, content);
  });

  it("returns content unchanged for empty links array", () => {
    const content = "# 2026-03-23\n";
    const updated = addUpdateLinks(content, []);
    assert.equal(updated, content);
  });

  it("places Updates section at the end of content", () => {
    const updated = addUpdateLinks(baseReflection, [
      { relativePath: "books/new.md", title: "📚 New Book" },
    ]);
    const updatesIdx = updated.indexOf(UPDATES_SECTION_HEADER);
    const embedIdx = updated.indexOf("## 🦋 Bluesky");
    assert.ok(updatesIdx > embedIdx, "Updates section should be after embed sections");
  });

  it("ends with newline after adding new section", () => {
    const content = "# 2026-03-23";
    const updated = addUpdateLinks(content, [
      { relativePath: "books/some-book.md", title: "📚 Some Book" },
    ]);
    assert.ok(updated.endsWith("\n"));
  });
});

// --- I/O Function Tests ---

describe("extractTitleFromFile", () => {
  it("returns title from frontmatter", () => {
    const tmpDir = makeTmpDir();
    try {
      const filePath = path.join(tmpDir, "test.md");
      fs.writeFileSync(filePath, "---\ntitle: My Great Post\n---\n# Content\n");
      assert.equal(extractTitleFromFile(filePath), "My Great Post");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns filename without extension when no title", () => {
    const tmpDir = makeTmpDir();
    try {
      const filePath = path.join(tmpDir, "my-post.md");
      fs.writeFileSync(filePath, "# No frontmatter\n");
      assert.equal(extractTitleFromFile(filePath), "my-post");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns filename for non-existent file", () => {
    assert.equal(extractTitleFromFile("/tmp/nonexistent/file.md"), "file");
  });

  it("strips quotes from title value", () => {
    const tmpDir = makeTmpDir();
    try {
      const filePath = path.join(tmpDir, "test.md");
      fs.writeFileSync(filePath, '---\ntitle: "Quoted Title"\n---\n');
      assert.equal(extractTitleFromFile(filePath), "Quoted Title");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });
});

describe("addUpdateLinksToReflection", () => {
  it("adds links to existing reflection", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-23.md"), baseReflection, "utf-8");
      const result = addUpdateLinksToReflection(tmpDir, "2026-03-23", [
        { relativePath: "books/new.md", title: "📚 New Book" },
      ]);
      assert.equal(result, true);
      const content = fs.readFileSync(path.join(tmpDir, "2026-03-23.md"), "utf-8");
      assert.ok(content.includes(UPDATES_SECTION_HEADER));
      assert.ok(content.includes("- [[books/new|📚 New Book]]"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns false when reflection does not exist", () => {
    const tmpDir = makeTmpDir();
    try {
      const result = addUpdateLinksToReflection(tmpDir, "2026-03-23", [
        { relativePath: "books/new.md", title: "📚 New Book" },
      ]);
      assert.equal(result, false);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns false when no new links needed", () => {
    const tmpDir = makeTmpDir();
    try {
      const withUpdates = [
        baseReflection.trimEnd(),
        "",
        UPDATES_SECTION_HEADER,
        "",
        "- [[books/existing|📚 Existing]]",
        "",
      ].join("\n");
      fs.writeFileSync(path.join(tmpDir, "2026-03-23.md"), withUpdates, "utf-8");
      const result = addUpdateLinksToReflection(tmpDir, "2026-03-23", [
        { relativePath: "books/existing.md", title: "📚 Existing" },
      ]);
      assert.equal(result, false);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns false for empty links array", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-23.md"), baseReflection, "utf-8");
      const result = addUpdateLinksToReflection(tmpDir, "2026-03-23", []);
      assert.equal(result, false);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("is idempotent — calling twice does not duplicate", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-23.md"), baseReflection, "utf-8");
      addUpdateLinksToReflection(tmpDir, "2026-03-23", [
        { relativePath: "books/new.md", title: "📚 New Book" },
      ]);
      const firstContent = fs.readFileSync(path.join(tmpDir, "2026-03-23.md"), "utf-8");
      addUpdateLinksToReflection(tmpDir, "2026-03-23", [
        { relativePath: "books/new.md", title: "📚 New Book" },
      ]);
      const secondContent = fs.readFileSync(path.join(tmpDir, "2026-03-23.md"), "utf-8");
      assert.equal(firstContent, secondContent);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("accumulates links across multiple calls", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-23.md"), baseReflection, "utf-8");
      addUpdateLinksToReflection(tmpDir, "2026-03-23", [
        { relativePath: "books/book-one.md", title: "📚 Book One" },
      ]);
      addUpdateLinksToReflection(tmpDir, "2026-03-23", [
        { relativePath: "books/book-two.md", title: "📚 Book Two" },
      ]);
      const content = fs.readFileSync(path.join(tmpDir, "2026-03-23.md"), "utf-8");
      assert.ok(content.includes("- [[books/book-one|📚 Book One]]"));
      assert.ok(content.includes("- [[books/book-two|📚 Book Two]]"));
    } finally {
      cleanTmpDir(tmpDir);
    }
  });
});
