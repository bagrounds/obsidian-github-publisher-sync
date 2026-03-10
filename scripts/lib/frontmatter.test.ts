/**
 * Tests for scripts/lib/frontmatter.ts — Frontmatter parsing and note I/O.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  parseFrontmatter,
  getReflectionPath,
  readReflection,
  readNote,
} from "../lib/frontmatter.ts";

describe("parseFrontmatter", () => {
  it("parses key-value pairs from frontmatter", () => {
    const content = `---\ntitle: Hello World\nURL: https://example.com\n---\n\nBody text`;
    const result = parseFrontmatter(content);
    assert.equal(result.frontmatter["title"], "Hello World");
    assert.equal(result.frontmatter["URL"], "https://example.com");
    assert.equal(result.body.trim(), "Body text");
  });

  it("returns empty frontmatter when no --- markers", () => {
    const content = "Just body text";
    const result = parseFrontmatter(content);
    assert.deepEqual(result.frontmatter, {});
    assert.equal(result.body, content);
  });

  it("strips quotes from values", () => {
    const content = `---\ntitle: "Quoted Title"\n---\nBody`;
    const result = parseFrontmatter(content);
    assert.equal(result.frontmatter["title"], "Quoted Title");
  });

  it("handles empty frontmatter block", () => {
    const content = `---\n---\nBody after empty frontmatter`;
    const result = parseFrontmatter(content);
    assert.deepEqual(result.frontmatter, {});
    assert.equal(result.body.trim(), "Body after empty frontmatter");
  });

  it("handles missing closing --- marker", () => {
    const content = `---\ntitle: broken\nno closing marker`;
    const result = parseFrontmatter(content);
    assert.deepEqual(result.frontmatter, {});
    assert.equal(result.body, content);
  });

  it("parses single-quoted values", () => {
    const content = `---\ntitle: 'Single Quoted'\n---\nBody`;
    const result = parseFrontmatter(content);
    assert.equal(result.frontmatter["title"], "Single Quoted");
  });
});

describe("getReflectionPath", () => {
  it("constructs correct path", () => {
    const result = getReflectionPath("2026-03-10", "/vault");
    assert.equal(result, path.join("/vault", "2026-03-10.md"));
  });
});

describe("readReflection", () => {
  it("reads and parses a reflection file", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "reflection-test-"));
    const content = `---\ntitle: Test Reflection\nURL: https://example.com/test\n---\n\n# Reflection\n\nSome content here.`;
    fs.writeFileSync(path.join(tmpDir, "2026-03-10.md"), content, "utf-8");

    const result = readReflection("2026-03-10", tmpDir);
    assert.ok(result);
    assert.equal(result.title, "Test Reflection");
    assert.equal(result.url, "https://example.com/test");
    assert.equal(result.date, "2026-03-10");
    assert.equal(result.hasTweetSection, false);

    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns null for missing file", () => {
    assert.equal(readReflection("2099-01-01", "/nonexistent"), null);
  });

  it("detects existing sections", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "reflection-test-"));
    const content = `---\ntitle: Test\n---\n\n## 🐦 Tweet  \n<tweet/>\n\n## 🦋 Bluesky  \n<bsky/>`;
    fs.writeFileSync(path.join(tmpDir, "2026-03-10.md"), content, "utf-8");

    const result = readReflection("2026-03-10", tmpDir);
    assert.ok(result);
    assert.equal(result.hasTweetSection, true);
    assert.equal(result.hasBlueskySection, true);
    assert.equal(result.hasMastodonSection, false);

    fs.rmSync(tmpDir, { recursive: true });
  });
});

describe("readNote", () => {
  it("reads an arbitrary note by relative path", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "note-test-"));
    fs.mkdirSync(path.join(tmpDir, "books"), { recursive: true });
    const content = `---\ntitle: My Book\nURL: https://example.com/books/my-book\n---\n\n# My Book\n\nGreat content.`;
    fs.writeFileSync(path.join(tmpDir, "books", "my-book.md"), content, "utf-8");

    const result = readNote("books/my-book.md", tmpDir);
    assert.ok(result);
    assert.equal(result.title, "My Book");
    assert.equal(result.url, "https://example.com/books/my-book");

    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns null for missing file", () => {
    assert.equal(readNote("nonexistent.md", "/tmp"), null);
  });

  it("derives title from filename when no frontmatter title", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "note-test-"));
    fs.writeFileSync(path.join(tmpDir, "untitled.md"), "Just body", "utf-8");

    const result = readNote("untitled.md", tmpDir);
    assert.ok(result);
    assert.equal(result.title, "untitled");

    fs.rmSync(tmpDir, { recursive: true });
  });

  it("extracts date from date-named file", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "note-test-"));
    fs.mkdirSync(path.join(tmpDir, "reflections"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "reflections", "2026-03-10.md"), "---\ntitle: Test\n---\nBody", "utf-8");

    const result = readNote("reflections/2026-03-10.md", tmpDir);
    assert.ok(result);
    assert.equal(result.date, "2026-03-10");

    fs.rmSync(tmpDir, { recursive: true });
  });
});
