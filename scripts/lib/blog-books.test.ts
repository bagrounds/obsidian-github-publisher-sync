import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  readBookCatalog,
  formatBookCatalogForPrompt,
  buildBookRecommendationsPrompt,
} from "./blog-books.ts";

describe("readBookCatalog", () => {
  it("returns empty array for non-existent directory", () => {
    assert.deepEqual(readBookCatalog("/tmp/nonexistent-books-dir"), []);
  });

  it("reads book entries with titles from frontmatter", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "books-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "thinking-in-systems.md"), "---\ntitle: 🌐🔗🧠📖 Thinking in Systems\n---\nContent");
      fs.writeFileSync(path.join(tmpDir, "godel-escher-bach.md"), "---\ntitle: ♾️📐🎶🥨 Gödel, Escher, Bach\n---\nContent");
      const catalog = readBookCatalog(tmpDir);
      assert.equal(catalog.length, 2);
      assert.equal(catalog[0]?.filename, "godel-escher-bach.md");
      assert.equal(catalog[0]?.title, "♾️📐🎶🥨 Gödel, Escher, Bach");
      assert.equal(catalog[1]?.filename, "thinking-in-systems.md");
      assert.equal(catalog[1]?.title, "🌐🔗🧠📖 Thinking in Systems");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("excludes index.md", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "books-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "index.md"), "---\ntitle: Books Index\n---\n");
      fs.writeFileSync(path.join(tmpDir, "a-book.md"), "---\ntitle: 📖 A Book\n---\nContent");
      const catalog = readBookCatalog(tmpDir);
      assert.equal(catalog.length, 1);
      assert.equal(catalog[0]?.filename, "a-book.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("uses filename as title fallback when no frontmatter title", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "books-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "no-title.md"), "---\nshare: true\n---\nContent");
      const catalog = readBookCatalog(tmpDir);
      assert.equal(catalog[0]?.title, "no-title");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});

describe("formatBookCatalogForPrompt", () => {
  it("returns empty string for empty catalog", () => {
    assert.equal(formatBookCatalogForPrompt([]), "");
  });

  it("formats catalog entries as stem | title", () => {
    const catalog = [
      { filename: "thinking-in-systems.md", title: "🌐 Thinking in Systems" },
      { filename: "godel-escher-bach.md", title: "♾️ Gödel, Escher, Bach" },
    ];
    const result = formatBookCatalogForPrompt(catalog);
    assert.ok(result.includes("- thinking-in-systems | 🌐 Thinking in Systems"));
    assert.ok(result.includes("- godel-escher-bach | ♾️ Gödel, Escher, Bach"));
  });
});

describe("buildBookRecommendationsPrompt", () => {
  it("returns empty string for empty catalog", () => {
    assert.equal(buildBookRecommendationsPrompt([]), "");
  });

  it("includes instructions and catalog", () => {
    const catalog = [
      { filename: "test-book.md", title: "📖 Test Book" },
    ];
    const result = buildBookRecommendationsPrompt(catalog);
    assert.ok(result.includes("Book Recommendations Instructions"));
    assert.ok(result.includes("[[books/FILENAME_STEM|EMOJI_TITLE]]"));
    assert.ok(result.includes("test-book | 📖 Test Book"));
  });

  it("includes Similar and Deeper Exploration subsections", () => {
    const catalog = [{ filename: "test.md", title: "Test" }];
    const result = buildBookRecommendationsPrompt(catalog);
    assert.ok(result.includes("### ✨ Similar"));
    assert.ok(result.includes("### 🧠 Deeper Exploration"));
  });
});
