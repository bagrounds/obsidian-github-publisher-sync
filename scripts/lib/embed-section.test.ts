/**
 * Tests for scripts/lib/embed-section.ts — Generic embed section building.
 *
 * Verifies the factory pattern: createSectionBuilder produces functions
 * that behave identically to the original per-platform implementations.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  createSectionBuilder,
  createSectionAppender,
  buildTweetSection,
  buildBlueskySection,
  buildMastodonSection,
  appendTweetSection,
} from "../lib/embed-section.ts";

describe("createSectionBuilder", () => {
  it("creates a function that builds a section with correct header", () => {
    const buildSection = createSectionBuilder("## Test Header");
    const result = buildSection("existing content\n", "<embed>test</embed>");
    assert.ok(result.includes("## Test Header"));
    assert.ok(result.includes("<embed>test</embed>"));
  });

  it("adds double newline when content does not end with newline", () => {
    const buildSection = createSectionBuilder("## Header");
    const result = buildSection("content without newline", "<embed/>");
    assert.ok(result.startsWith("\n\n"));
  });

  it("adds single newline when content ends with newline", () => {
    const buildSection = createSectionBuilder("## Header");
    const result = buildSection("content with newline\n", "<embed/>");
    assert.ok(result.startsWith("\n"));
    assert.ok(!result.startsWith("\n\n"));
  });
});

describe("platform section builders", () => {
  it("buildTweetSection uses tweet header", () => {
    const result = buildTweetSection("content\n", "<tweet/>");
    assert.ok(result.includes("## 🐦 Tweet"));
  });

  it("buildBlueskySection uses bluesky header", () => {
    const result = buildBlueskySection("content\n", "<bluesky/>");
    assert.ok(result.includes("## 🦋 Bluesky"));
  });

  it("buildMastodonSection uses mastodon header", () => {
    const result = buildMastodonSection("content\n", "<mastodon/>");
    assert.ok(result.includes("## 🐘 Mastodon"));
  });
});

describe("createSectionAppender", () => {
  it("appends section to file", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "embed-test-"));
    const filePath = path.join(tmpDir, "test.md");
    fs.writeFileSync(filePath, "# Test\n\nContent here\n", "utf-8");

    appendTweetSection(filePath, "<tweet>hello</tweet>");

    const result = fs.readFileSync(filePath, "utf-8");
    assert.ok(result.includes("## 🐦 Tweet"));
    assert.ok(result.includes("<tweet>hello</tweet>"));

    fs.rmSync(tmpDir, { recursive: true });
  });

  it("skips if section already exists (idempotent)", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "embed-test-"));
    const filePath = path.join(tmpDir, "test.md");
    const original = "# Test\n\n## 🐦 Tweet  \n<existing/>\n";
    fs.writeFileSync(filePath, original, "utf-8");

    appendTweetSection(filePath, "<new>should not appear</new>");

    const result = fs.readFileSync(filePath, "utf-8");
    assert.equal(result, original);

    fs.rmSync(tmpDir, { recursive: true });
  });
});

describe("factory consistency", () => {
  it("factory-created builder matches direct builder behavior", () => {
    const factoryBuilder = createSectionBuilder("## 🐦 Tweet");
    const content = "test content\n";
    const html = "<embed/>";

    const factoryResult = factoryBuilder(content, html);
    const directResult = buildTweetSection(content, html);

    assert.equal(factoryResult, directResult);
  });
});
