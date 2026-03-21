import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  hasEmbeddedImage,
  titleToKebabCase,
  extractTitle,
  insertImageEmbed,
  buildImagePrompt,
  mimeTypeToExtension,
  isQuotaError,
  processNote,
  isPostFile,
  extractDateFromFilename,
  listNotesNewestFirst,
  backfillImages,
  updateFrontmatterTimestamp,
  syncMarkdownDir,
  syncAttachmentsDir,
  isImagenModel,
  resolveImageProvider,
  makeCloudflareGenerator,
  type ImageGenerator,
} from "./blog-image.ts";

describe("hasEmbeddedImage", () => {
  it("detects Obsidian wiki image embeds", () => {
    assert.equal(hasEmbeddedImage("![[attachments/photo.jpg]]"), true);
  });

  it("detects Obsidian wiki image embeds without attachments prefix", () => {
    assert.equal(hasEmbeddedImage("![[photo.png]]"), true);
  });

  it("detects standard markdown image embeds", () => {
    assert.equal(
      hasEmbeddedImage("![alt text](../some-image.jpg)"),
      true,
    );
  });

  it("detects jpeg images", () => {
    assert.equal(hasEmbeddedImage("![[attachments/img.jpeg]]"), true);
  });

  it("detects png images", () => {
    assert.equal(hasEmbeddedImage("![](path/to/img.png)"), true);
  });

  it("detects webp images", () => {
    assert.equal(hasEmbeddedImage("![[attachments/img.webp]]"), true);
  });

  it("returns false for text-only content", () => {
    assert.equal(hasEmbeddedImage("# Hello World\n\nSome text"), false);
  });

  it("returns false for wiki links to non-image files", () => {
    assert.equal(hasEmbeddedImage("![[some-note]]"), false);
  });

  it("returns false for markdown links to non-image files", () => {
    assert.equal(hasEmbeddedImage("![alt](file.pdf)"), false);
  });

  it("returns false for empty content", () => {
    assert.equal(hasEmbeddedImage(""), false);
  });

  it("detects image embedded in larger document", () => {
    const content = [
      "---",
      "title: Test",
      "---",
      "# Test Post",
      "![[attachments/hero.jpg]]",
      "Some content after image",
    ].join("\n");
    assert.equal(hasEmbeddedImage(content), true);
  });
});

describe("titleToKebabCase", () => {
  it("converts simple title to kebab case", () => {
    assert.equal(titleToKebabCase("Hello World"), "hello-world");
  });

  it("strips emojis", () => {
    assert.equal(titleToKebabCase("🤖 Robot Post 🐔"), "robot-post");
  });

  it("strips date prefix with pipe", () => {
    assert.equal(
      titleToKebabCase("2026-03-18 | Some Title"),
      "some-title",
    );
  });

  it("strips date prefix without pipe", () => {
    assert.equal(titleToKebabCase("2026-03-18 Some Title"), "some-title");
  });

  it("removes special characters", () => {
    assert.equal(
      titleToKebabCase("Hello — World: A Story"),
      "hello-world-a-story",
    );
  });

  it("collapses multiple hyphens", () => {
    assert.equal(titleToKebabCase("a---b"), "a-b");
  });

  it("trims leading and trailing hyphens", () => {
    assert.equal(titleToKebabCase("---hello---"), "hello");
  });

  it("handles complex blog title", () => {
    const title =
      "2026-03-12 | 🤖 Fully Automated Blogging — When AI Writes About Writing 🤖";
    const result = titleToKebabCase(title);
    assert.equal(
      result,
      "fully-automated-blogging-when-ai-writes-about-writing",
    );
  });

  it("handles title with only emojis and date", () => {
    assert.equal(titleToKebabCase("2026-01-01 | 🎉🎊"), "");
  });
});

describe("extractTitle", () => {
  it("extracts title from frontmatter", () => {
    const content = "---\ntitle: My Great Post\n---\n# H1 Title\nBody";
    assert.equal(extractTitle(content), "My Great Post");
  });

  it("extracts quoted title from frontmatter", () => {
    const content = '---\ntitle: "Quoted Title"\n---\nBody';
    assert.equal(extractTitle(content), "Quoted Title");
  });

  it("falls back to H1 when no frontmatter title", () => {
    const content = "---\nshare: true\n---\n# Heading One\nBody";
    assert.equal(extractTitle(content), "Heading One");
  });

  it("falls back to H1 with no frontmatter", () => {
    const content = "# Direct H1\nSome body text";
    assert.equal(extractTitle(content), "Direct H1");
  });

  it("returns empty string when no title found", () => {
    const content = "Just body text with no title or frontmatter";
    assert.equal(extractTitle(content), "");
  });

  it("extracts title from blog post frontmatter", () => {
    const content = [
      "---",
      "share: true",
      "title: 2026-03-12 | 🤖 Fully Automated Blogging",
      "URL: https://example.com",
      "---",
      "# 2026-03-12 | 🤖 Fully Automated Blogging",
      "Body",
    ].join("\n");
    assert.equal(
      extractTitle(content),
      "2026-03-12 | 🤖 Fully Automated Blogging",
    );
  });
});

describe("insertImageEmbed", () => {
  it("inserts image embed after H1", () => {
    const content = "# Title\nBody text";
    const result = insertImageEmbed(content, "my-image.jpg");
    assert.equal(result, "# Title\n![[attachments/my-image.jpg]]\nBody text");
  });

  it("returns unchanged content when no H1", () => {
    const content = "## Subtitle\nBody text";
    const result = insertImageEmbed(content, "my-image.jpg");
    assert.equal(result, content);
  });

  it("handles content with frontmatter before H1", () => {
    const content = "---\ntitle: Test\n---\n# Title\nBody";
    const result = insertImageEmbed(content, "hero.jpg");
    assert.equal(
      result,
      "---\ntitle: Test\n---\n# Title\n![[attachments/hero.jpg]]\nBody",
    );
  });

  it("inserts after first H1 when multiple exist", () => {
    const content = "# First\nText\n# Second\nMore text";
    const result = insertImageEmbed(content, "img.jpg");
    assert.equal(
      result,
      "# First\n![[attachments/img.jpg]]\nText\n# Second\nMore text",
    );
  });

  it("handles H1 with trailing whitespace in line", () => {
    const content = "# Title  \nBody";
    const result = insertImageEmbed(content, "img.jpg");
    assert.equal(
      result,
      "# Title  \n![[attachments/img.jpg]]\nBody",
    );
  });
});

describe("buildImagePrompt", () => {
  it("wraps content in image generation prompt", () => {
    const result = buildImagePrompt("Hello world post");
    assert.equal(
      result,
      "generate an image to illustrate the following blog post: Hello world post",
    );
  });
});

describe("mimeTypeToExtension", () => {
  it("maps jpeg mime type", () => {
    assert.equal(mimeTypeToExtension("image/jpeg"), ".jpg");
  });

  it("maps png mime type", () => {
    assert.equal(mimeTypeToExtension("image/png"), ".png");
  });

  it("defaults to .jpg for unknown type", () => {
    assert.equal(mimeTypeToExtension("image/unknown"), ".jpg");
  });
});

describe("isQuotaError", () => {
  it("detects 429 error", () => {
    assert.equal(isQuotaError(new Error("HTTP 429 Too Many Requests")), true);
  });

  it("detects RESOURCE_EXHAUSTED", () => {
    assert.equal(isQuotaError(new Error("RESOURCE_EXHAUSTED")), true);
  });

  it("detects quota error", () => {
    assert.equal(isQuotaError(new Error("quota exceeded")), true);
  });

  it("returns false for non-quota errors", () => {
    assert.equal(isQuotaError(new Error("network timeout")), false);
  });

  it("returns false for null", () => {
    assert.equal(isQuotaError(null), false);
  });

  it("returns false for non-object", () => {
    assert.equal(isQuotaError("string error"), false);
  });
});

describe("isImagenModel", () => {
  it("returns true for imagen-4.0-generate-001", () => {
    assert.equal(isImagenModel("imagen-4.0-generate-001"), true);
  });

  it("returns true for imagen-4.0-fast-generate-001", () => {
    assert.equal(isImagenModel("imagen-4.0-fast-generate-001"), true);
  });

  it("returns true for imagen-4.0-ultra-generate-001", () => {
    assert.equal(isImagenModel("imagen-4.0-ultra-generate-001"), true);
  });

  it("returns false for gemini models", () => {
    assert.equal(isImagenModel("gemini-2.0-flash-exp"), false);
  });

  it("returns false for empty string", () => {
    assert.equal(isImagenModel(""), false);
  });
});

describe("isPostFile", () => {
  it("accepts dated markdown files", () => {
    assert.equal(isPostFile("2026-03-12-some-title.md"), true);
  });

  it("accepts reflection files", () => {
    assert.equal(isPostFile("2026-03-18.md"), true);
  });

  it("rejects index.md", () => {
    assert.equal(isPostFile("index.md"), false);
  });

  it("rejects AGENTS.md", () => {
    assert.equal(isPostFile("AGENTS.md"), false);
  });

  it("rejects IDEAS.md", () => {
    assert.equal(isPostFile("IDEAS.md"), false);
  });

  it("rejects non-markdown files", () => {
    assert.equal(isPostFile("image.jpg"), false);
  });

  it("rejects undated markdown files", () => {
    assert.equal(isPostFile("random-note.md"), false);
  });
});

describe("extractDateFromFilename", () => {
  it("extracts date from blog post filename", () => {
    assert.equal(
      extractDateFromFilename("2026-03-12-some-title.md"),
      "2026-03-12",
    );
  });

  it("extracts date from reflection filename", () => {
    assert.equal(extractDateFromFilename("2026-03-18.md"), "2026-03-18");
  });

  it("returns empty for non-dated filename", () => {
    assert.equal(extractDateFromFilename("index.md"), "");
  });
});

describe("processNote", () => {
  let tempDir: string;
  let attachmentsDir: string;

  const mockGenerate: ImageGenerator = async () => ({
    data: Buffer.from("fake-image-data"),
    mimeType: "image/jpeg",
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-image-test-"));
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("generates image and embeds it for note without image", async () => {
    const notePath = path.join(tempDir, "test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\n---\n# Test Post\nBody text\n",
    );

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
    );

    assert.equal(result.skipped, false);
    assert.equal(result.imageName, "test-post.jpg");
    assert.ok(fs.existsSync(path.join(attachmentsDir, "test-post.jpg")));

    const updated = fs.readFileSync(notePath, "utf-8");
    assert.ok(updated.includes("![[attachments/test-post.jpg]]"));
  });

  it("skips note that already has an image", async () => {
    const notePath = path.join(tempDir, "test.md");
    fs.writeFileSync(
      notePath,
      "# Title\n![[attachments/existing.jpg]]\nBody\n",
    );

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
    );

    assert.equal(result.skipped, true);
  });

  it("skips note with no title", async () => {
    const notePath = path.join(tempDir, "test.md");
    fs.writeFileSync(notePath, "Just body text, no title\n");

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
    );

    assert.equal(result.skipped, true);
  });

  it("creates attachments directory if missing", async () => {
    const notePath = path.join(tempDir, "test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: New Post\n---\n# New Post\nContent\n",
    );

    await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
    );

    assert.ok(fs.existsSync(attachmentsDir));
  });

  it("uses kebab-case title for image name", async () => {
    const notePath = path.join(tempDir, "test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: 2026-03-18 | 🤖 My Amazing Post\n---\n# 2026-03-18 | 🤖 My Amazing Post\nBody\n",
    );

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
    );

    assert.equal(result.imageName, "my-amazing-post.jpg");
  });
});

describe("listNotesNewestFirst", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-image-list-"));
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("lists dated markdown files in reverse order", () => {
    fs.writeFileSync(path.join(tempDir, "2026-03-10-a.md"), "");
    fs.writeFileSync(path.join(tempDir, "2026-03-12-b.md"), "");
    fs.writeFileSync(path.join(tempDir, "2026-03-11-c.md"), "");

    const result = listNotesNewestFirst(tempDir);
    assert.deepEqual(result, [
      "2026-03-12-b.md",
      "2026-03-11-c.md",
      "2026-03-10-a.md",
    ]);
  });

  it("excludes non-post files", () => {
    fs.writeFileSync(path.join(tempDir, "2026-03-10-a.md"), "");
    fs.writeFileSync(path.join(tempDir, "index.md"), "");
    fs.writeFileSync(path.join(tempDir, "AGENTS.md"), "");
    fs.writeFileSync(path.join(tempDir, "IDEAS.md"), "");

    const result = listNotesNewestFirst(tempDir);
    assert.deepEqual(result, ["2026-03-10-a.md"]);
  });

  it("returns empty array for nonexistent directory", () => {
    const result = listNotesNewestFirst("/nonexistent/dir");
    assert.deepEqual(result, []);
  });
});

describe("backfillImages", () => {
  let tempDir: string;
  let attachmentsDir: string;

  const mockGenerate: ImageGenerator = async () => ({
    data: Buffer.from("fake-image-data"),
    mimeType: "image/jpeg",
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "backfill-test-"));
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("generates images for notes without them", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
    });

    assert.equal(result.imagesGenerated, 1);
    assert.equal(result.stoppedByQuota, false);
  });

  it("skips notes that already have images", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "# Title\n![[attachments/existing.jpg]]\nBody\n",
    );

    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
    });

    assert.equal(result.imagesGenerated, 0);
  });

  it("stops on quota error", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const quotaGenerate: ImageGenerator = async () => {
      throw new Error("429 Too Many Requests");
    };

    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: quotaGenerate,
    });

    assert.equal(result.stoppedByQuota, true);
    assert.equal(result.imagesGenerated, 0);
  });

  it("updates frontmatter chain when image generated", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-12-latest.md"),
      "---\ntitle: Latest\n---\n# Latest\n![[attachments/img.jpg]]\n",
    );
    fs.writeFileSync(
      path.join(dir, "2026-03-11-middle.md"),
      "---\ntitle: Middle\n---\n# Middle\n![[attachments/img2.jpg]]\n",
    );
    fs.writeFileSync(
      path.join(dir, "2026-03-10-needs-image.md"),
      "---\ntitle: Needs Image\n---\n# Needs Image\nBody\n",
    );

    await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
    });

    const latestContent = fs.readFileSync(
      path.join(dir, "2026-03-12-latest.md"),
      "utf-8",
    );
    const middleContent = fs.readFileSync(
      path.join(dir, "2026-03-11-middle.md"),
      "utf-8",
    );
    const needsImageContent = fs.readFileSync(
      path.join(dir, "2026-03-10-needs-image.md"),
      "utf-8",
    );

    assert.ok(latestContent.includes("updated:"));
    assert.ok(middleContent.includes("updated:"));
    assert.ok(needsImageContent.includes("updated:"));
    assert.ok(needsImageContent.includes("![[attachments/needs-image.jpg]]"));
  });

  it("handles missing directories gracefully", async () => {
    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: "/nonexistent/dir", id: "missing" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
      onProgress: (e) => events.push(e),
    });

    assert.equal(result.imagesGenerated, 0);
    assert.ok(events.some((e) => e["event"] === "directory_missing"));
  });

  it("continues past non-quota errors", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-11-second.md"),
      "---\ntitle: Second\n---\n# Second\nBody\n",
    );
    fs.writeFileSync(
      path.join(dir, "2026-03-10-first.md"),
      "---\ntitle: First\n---\n# First\nBody\n",
    );

    let callCount = 0;
    const failOnceGenerate: ImageGenerator = async () => {
      callCount++;
      if (callCount === 1) throw new Error("Random API error");
      return { data: Buffer.from("image"), mimeType: "image/jpeg" };
    };

    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: failOnceGenerate,
    });

    assert.equal(result.imagesGenerated, 1);
    assert.equal(result.stoppedByQuota, false);
  });
});

describe("updateFrontmatterTimestamp", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(
      path.join(os.tmpdir(), "frontmatter-timestamp-"),
    );
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("updates existing updated field", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(
      filePath,
      "---\ntitle: Test\nupdated: 2026-01-01T00:00:00Z\n---\nBody\n",
    );

    updateFrontmatterTimestamp(filePath, "2026-03-19T12:00:00Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("updated: 2026-03-19T12:00:00Z"));
    assert.ok(!content.includes("2026-01-01"));
  });

  it("inserts updated field when missing", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, "---\ntitle: Test\n---\nBody\n");

    updateFrontmatterTimestamp(filePath, "2026-03-19T12:00:00Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("updated: 2026-03-19T12:00:00Z"));
  });

  it("adds frontmatter when none exists", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, "# Title\nBody\n");

    updateFrontmatterTimestamp(filePath, "2026-03-19T12:00:00Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.startsWith("---\nupdated: 2026-03-19T12:00:00Z\n---"));
  });

  it("handles nonexistent file gracefully", () => {
    assert.doesNotThrow(() => {
      updateFrontmatterTimestamp("/nonexistent/file.md", "2026-03-19T12:00:00Z");
    });
  });
});

describe("syncMarkdownDir", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-md-test-"));
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("copies new markdown files to vault", () => {
    const localDir = path.join(tempDir, "local");
    const vaultDir = path.join(tempDir, "vault");
    fs.mkdirSync(localDir);
    fs.mkdirSync(vaultDir);
    fs.writeFileSync(path.join(localDir, "post.md"), "# Post\nBody\n");

    const synced = syncMarkdownDir(localDir, "series", vaultDir);
    assert.equal(synced, 1);
    assert.ok(fs.existsSync(path.join(vaultDir, "series", "post.md")));
  });

  it("skips files already in sync", () => {
    const localDir = path.join(tempDir, "local");
    const vaultDir = path.join(tempDir, "vault");
    const vaultSeries = path.join(vaultDir, "series");
    fs.mkdirSync(localDir);
    fs.mkdirSync(vaultSeries, { recursive: true });
    fs.writeFileSync(path.join(localDir, "post.md"), "# Same\n");
    fs.writeFileSync(path.join(vaultSeries, "post.md"), "# Same\n");

    const synced = syncMarkdownDir(localDir, "series", vaultDir);
    assert.equal(synced, 0);
  });

  it("overwrites changed markdown files", () => {
    const localDir = path.join(tempDir, "local");
    const vaultDir = path.join(tempDir, "vault");
    const vaultSeries = path.join(vaultDir, "series");
    fs.mkdirSync(localDir);
    fs.mkdirSync(vaultSeries, { recursive: true });
    fs.writeFileSync(path.join(localDir, "post.md"), "# Updated\n");
    fs.writeFileSync(path.join(vaultSeries, "post.md"), "# Old\n");

    const synced = syncMarkdownDir(localDir, "series", vaultDir);
    assert.equal(synced, 1);
    assert.equal(
      fs.readFileSync(path.join(vaultSeries, "post.md"), "utf-8"),
      "# Updated\n",
    );
  });

  it("ignores non-markdown files", () => {
    const localDir = path.join(tempDir, "local");
    const vaultDir = path.join(tempDir, "vault");
    fs.mkdirSync(localDir);
    fs.mkdirSync(vaultDir);
    fs.writeFileSync(path.join(localDir, "image.jpg"), "binary");

    const synced = syncMarkdownDir(localDir, "series", vaultDir);
    assert.equal(synced, 0);
  });

  it("returns 0 for nonexistent local dir", () => {
    const vaultDir = path.join(tempDir, "vault");
    fs.mkdirSync(vaultDir);
    const synced = syncMarkdownDir("/nonexistent/dir", "series", vaultDir);
    assert.equal(synced, 0);
  });
});

describe("syncAttachmentsDir", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-attach-test-"));
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("copies new attachment files to vault", () => {
    const localDir = path.join(tempDir, "attachments");
    const vaultDir = path.join(tempDir, "vault");
    fs.mkdirSync(localDir);
    fs.mkdirSync(vaultDir);
    fs.writeFileSync(path.join(localDir, "image.jpg"), "fake-image-data");

    const synced = syncAttachmentsDir(localDir, vaultDir);
    assert.equal(synced, 1);
    assert.ok(fs.existsSync(path.join(vaultDir, "attachments", "image.jpg")));
  });

  it("skips files already in vault", () => {
    const localDir = path.join(tempDir, "attachments");
    const vaultDir = path.join(tempDir, "vault");
    const vaultAttach = path.join(vaultDir, "attachments");
    fs.mkdirSync(localDir);
    fs.mkdirSync(vaultAttach, { recursive: true });
    fs.writeFileSync(path.join(localDir, "image.jpg"), "data");
    fs.writeFileSync(path.join(vaultAttach, "image.jpg"), "data");

    const synced = syncAttachmentsDir(localDir, vaultDir);
    assert.equal(synced, 0);
  });

  it("returns 0 for nonexistent dir", () => {
    const vaultDir = path.join(tempDir, "vault");
    fs.mkdirSync(vaultDir);
    const synced = syncAttachmentsDir("/nonexistent/dir", vaultDir);
    assert.equal(synced, 0);
  });

  it("creates vault attachments directory if missing", () => {
    const localDir = path.join(tempDir, "attachments");
    const vaultDir = path.join(tempDir, "vault");
    fs.mkdirSync(localDir);
    fs.mkdirSync(vaultDir);
    fs.writeFileSync(path.join(localDir, "img.png"), "png-data");

    syncAttachmentsDir(localDir, vaultDir);
    assert.ok(fs.existsSync(path.join(vaultDir, "attachments", "img.png")));
  });
});

describe("resolveImageProvider", () => {
  it("selects Cloudflare when CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are set", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token-123",
      CLOUDFLARE_ACCOUNT_ID: "cf-account-456",
    };
    const provider = resolveImageProvider(env);
    assert.equal(provider.apiKey, "cf-token-123");
    assert.equal(provider.model, "@cf/black-forest-labs/flux-1-schnell");
    assert.equal(typeof provider.generator, "function");
  });

  it("uses custom Cloudflare model when CLOUDFLARE_IMAGE_MODEL is set", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
      CLOUDFLARE_IMAGE_MODEL: "@cf/stabilityai/stable-diffusion-xl-base-1.0",
    };
    const provider = resolveImageProvider(env);
    assert.equal(provider.model, "@cf/stabilityai/stable-diffusion-xl-base-1.0");
  });

  it("falls back to Gemini when only GEMINI_API_KEY is set", () => {
    const env = {
      GEMINI_API_KEY: "gemini-key-abc",
    };
    const provider = resolveImageProvider(env);
    assert.equal(provider.apiKey, "gemini-key-abc");
    assert.equal(provider.model, "gemini-3.1-flash-image-preview");
  });

  it("uses custom Gemini model when IMAGE_GEMINI_MODEL is set", () => {
    const env = {
      GEMINI_API_KEY: "gemini-key",
      IMAGE_GEMINI_MODEL: "imagen-4.0-generate-001",
    };
    const provider = resolveImageProvider(env);
    assert.equal(provider.model, "imagen-4.0-generate-001");
  });

  it("prefers Cloudflare over Gemini when both are available", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
      GEMINI_API_KEY: "gemini-key",
    };
    const provider = resolveImageProvider(env);
    assert.equal(provider.apiKey, "cf-token");
    assert.ok(provider.model.includes("flux"));
  });

  it("throws when no credentials are available", () => {
    assert.throws(
      () => resolveImageProvider({}),
      /No image generation credentials found/,
    );
  });

  it("throws when only CLOUDFLARE_API_TOKEN is set without account ID", () => {
    const env = { CLOUDFLARE_API_TOKEN: "cf-token" };
    assert.throws(
      () => resolveImageProvider(env),
      /No image generation credentials found/,
    );
  });
});

describe("makeCloudflareGenerator", () => {
  it("returns an ImageGenerator function", () => {
    const generator = makeCloudflareGenerator("account-123");
    assert.equal(typeof generator, "function");
  });

  it("uses default model when none specified", () => {
    const generator = makeCloudflareGenerator("account-123");
    assert.equal(typeof generator, "function");
  });
});
