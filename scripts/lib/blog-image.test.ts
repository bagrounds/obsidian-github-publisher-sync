import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  hasEmbeddedImage,
  titleToKebabCase,
  notePathToImageBaseName,
  resolveUniqueImageName,
  extractTitle,
  insertImageEmbed,
  buildImagePrompt,
  cleanContentForPrompt,
  DEFAULT_DESCRIBER_MODEL,
  DEFAULT_HUGGINGFACE_IMAGE_MODEL,
  mimeTypeToExtension,
  isQuotaError,
  isDailyQuotaError,
  isProviderUnavailableError,
  parseRetryDelay,
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
  resolveImageProviders,
  makeCloudflareGenerator,
  makeHuggingFaceGenerator,
  extractFrontmatterValue,
  shouldRegenerateImage,
  removeImageEmbed,
  sanitizeForYaml,
  updateFrontmatterFields,
  makeGeminiDescriber,
  type ImageGenerator,
  type ImageProviderConfig,
  type PromptDescriber,
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

describe("notePathToImageBaseName", () => {
  it("combines parent directory and file stem", () => {
    assert.equal(
      notePathToImageBaseName("/repo/chickie-loo/2026-03-22-weekly-recap.md"),
      "chickie-loo-2026-03-22-weekly-recap",
    );
  });

  it("combines parent directory from auto-blog-zero", () => {
    assert.equal(
      notePathToImageBaseName("/repo/auto-blog-zero/2026-03-22-weekly-recap.md"),
      "auto-blog-zero-2026-03-22-weekly-recap",
    );
  });

  it("lowercases the result", () => {
    assert.equal(
      notePathToImageBaseName("/repo/MyBlog/SomePost.md"),
      "myblog-somepost",
    );
  });

  it("replaces non-alphanumeric characters with hyphens", () => {
    assert.equal(
      notePathToImageBaseName("/repo/ai-blog/my post (draft).md"),
      "ai-blog-my-post-draft",
    );
  });

  it("collapses multiple hyphens", () => {
    assert.equal(
      notePathToImageBaseName("/repo/my--blog/a---b.md"),
      "my-blog-a-b",
    );
  });

  it("trims leading and trailing hyphens", () => {
    assert.equal(
      notePathToImageBaseName("/repo/blog/--hello--.md"),
      "blog-hello",
    );
  });

  it("handles deeply nested paths using only immediate parent", () => {
    assert.equal(
      notePathToImageBaseName("/a/b/c/reflections/2026-01-01.md"),
      "reflections-2026-01-01",
    );
  });

  it("differentiates posts with same filename in different directories", () => {
    const chickie = notePathToImageBaseName("/repo/chickie-loo/2026-03-22-weekly-recap.md");
    const auto = notePathToImageBaseName("/repo/auto-blog-zero/2026-03-22-weekly-recap.md");
    assert.notEqual(chickie, auto);
    assert.equal(chickie, "chickie-loo-2026-03-22-weekly-recap");
    assert.equal(auto, "auto-blog-zero-2026-03-22-weekly-recap");
  });
});

describe("resolveUniqueImageName", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "unique-name-test-"));
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("returns base name when no conflict exists", () => {
    assert.equal(
      resolveUniqueImageName("my-image", ".jpg", tempDir),
      "my-image.jpg",
    );
  });

  it("appends -2 when base name already exists", () => {
    fs.writeFileSync(path.join(tempDir, "my-image.jpg"), "");
    assert.equal(
      resolveUniqueImageName("my-image", ".jpg", tempDir),
      "my-image-2.jpg",
    );
  });

  it("appends -3 when -2 also exists", () => {
    fs.writeFileSync(path.join(tempDir, "my-image.jpg"), "");
    fs.writeFileSync(path.join(tempDir, "my-image-2.jpg"), "");
    assert.equal(
      resolveUniqueImageName("my-image", ".jpg", tempDir),
      "my-image-3.jpg",
    );
  });

  it("handles different extensions independently", () => {
    fs.writeFileSync(path.join(tempDir, "my-image.jpg"), "");
    assert.equal(
      resolveUniqueImageName("my-image", ".png", tempDir),
      "my-image.png",
    );
  });

  it("works when attachments directory does not exist yet", () => {
    const nonExistent = path.join(tempDir, "missing");
    assert.equal(
      resolveUniqueImageName("my-image", ".jpg", nonExistent),
      "my-image.jpg",
    );
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

describe("cleanContentForPrompt", () => {
  it("strips frontmatter from content", () => {
    const content = "---\ntitle: Test Post\nshare: true\n---\n# Title\nBody text";
    const result = cleanContentForPrompt(content);
    assert.ok(!result.includes("title:"));
    assert.ok(!result.includes("---"));
    assert.ok(result.includes("Body text"));
  });

  it("strips social media embed sections", () => {
    const content = "# Title\nBody text\n## 🐦 Tweet\nSome tweet\n## 🦋 Bluesky\nSome post";
    const result = cleanContentForPrompt(content);
    assert.ok(result.includes("Body text"));
    assert.ok(!result.includes("Tweet"));
    assert.ok(!result.includes("Bluesky"));
  });

  it("strips markdown heading syntax", () => {
    const content = "## Heading Two\n### Heading Three\nBody";
    const result = cleanContentForPrompt(content);
    assert.ok(result.includes("Heading Two"));
    assert.ok(!result.startsWith("##"));
  });

  it("strips code blocks", () => {
    const content = "Body\n```typescript\nconst x = 1;\n```\nMore text";
    const result = cleanContentForPrompt(content);
    assert.ok(!result.includes("const x = 1"));
    assert.ok(result.includes("More text"));
  });

  it("strips image embeds", () => {
    const content = "Body\n![[attachments/img.jpg]]\nMore text";
    const result = cleanContentForPrompt(content);
    assert.ok(!result.includes("![["));
    assert.ok(result.includes("More text"));
  });

  it("strips inline markdown formatting", () => {
    const content = "**bold** and *italic* and ~~strike~~";
    const result = cleanContentForPrompt(content);
    assert.ok(result.includes("bold"));
    assert.ok(!result.includes("**"));
    assert.ok(!result.includes("~~"));
  });
});

describe("buildImagePrompt", () => {
  it("wraps cleaned content in image generation prompt", () => {
    const result = buildImagePrompt("Hello world post");
    assert.ok(result.startsWith("generate an image to illustrate the following blog post: "));
    assert.ok(result.includes("Hello world post"));
  });

  it("strips frontmatter from prompt", () => {
    const content = "---\ntitle: Test\nshare: true\n---\n# Title\nBody text";
    const result = buildImagePrompt(content);
    assert.ok(!result.includes("title: Test"));
    assert.ok(result.includes("Body text"));
  });

  it("truncates to fit within prompt limit", () => {
    const longContent = "A".repeat(3000);
    const result = buildImagePrompt(longContent);
    assert.ok(result.length <= 2048);
    assert.ok(result.endsWith("…"));
  });

  it("does not truncate short content", () => {
    const result = buildImagePrompt("Short post about coding");
    assert.ok(!result.endsWith("…"));
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
  let blogDir: string;
  let attachmentsDir: string;

  const mockGenerate: ImageGenerator = async () => ({
    data: Buffer.from("fake-image-data"),
    mimeType: "image/jpeg",
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "blog-image-test-"));
    blogDir = path.join(tempDir, "chickie-loo");
    fs.mkdirSync(blogDir, { recursive: true });
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("generates image and embeds it for note without image", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test-post.md");
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
    assert.equal(result.imageName, "chickie-loo-2026-03-22-test-post.jpg");
    assert.ok(fs.existsSync(path.join(attachmentsDir, "chickie-loo-2026-03-22-test-post.jpg")));

    const updated = fs.readFileSync(notePath, "utf-8");
    assert.ok(updated.includes("![[attachments/chickie-loo-2026-03-22-test-post.jpg]]"));
  });

  it("skips note that already has an image", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test.md");
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
    const notePath = path.join(blogDir, "2026-03-22-test.md");
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
    const notePath = path.join(blogDir, "2026-03-22-test.md");
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

  it("derives image name from file path not title", async () => {
    const notePath = path.join(blogDir, "2026-03-18-my-amazing-post.md");
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

    assert.equal(result.imageName, "chickie-loo-2026-03-18-my-amazing-post.jpg");
  });

  it("avoids name conflicts across different blog directories", async () => {
    const autoDir = path.join(tempDir, "auto-blog-zero");
    fs.mkdirSync(autoDir, { recursive: true });

    const chickiePath = path.join(blogDir, "2026-03-22-weekly-recap.md");
    const autoPath = path.join(autoDir, "2026-03-22-weekly-recap.md");
    fs.writeFileSync(chickiePath, "---\ntitle: Weekly Recap\n---\n# Weekly Recap\nBody\n");
    fs.writeFileSync(autoPath, "---\ntitle: Weekly Recap\n---\n# Weekly Recap\nBody\n");

    const result1 = await processNote(chickiePath, attachmentsDir, "k", "m", mockGenerate);
    const result2 = await processNote(autoPath, attachmentsDir, "k", "m", mockGenerate);

    assert.equal(result1.imageName, "chickie-loo-2026-03-22-weekly-recap.jpg");
    assert.equal(result2.imageName, "auto-blog-zero-2026-03-22-weekly-recap.jpg");
    assert.notEqual(result1.imageName, result2.imageName);
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
      minDelayMs: 0,
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
      minDelayMs: 0,
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
      minDelayMs: 0,
      sleep: async () => {},
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
      minDelayMs: 0,
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
    assert.ok(needsImageContent.includes("![[attachments/series-2026-03-10-needs-image.jpg]]"));
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
      minDelayMs: 0,
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

  it("updates empty updated field without creating duplicate", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, "---\ntitle: Test\nupdated:\n---\nBody\n");

    updateFrontmatterTimestamp(filePath, "2026-03-19T12:00:00Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("updated: 2026-03-19T12:00:00Z"));
    const updatedCount = (content.match(/^updated:/gm) ?? []).length;
    assert.equal(updatedCount, 1, "should have exactly one updated field");
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

describe("extractFrontmatterValue", () => {
  it("extracts a string value from frontmatter", () => {
    const content = "---\ntitle: My Post\nshare: true\n---\n# My Post\n";
    assert.equal(extractFrontmatterValue(content, "title"), "My Post");
  });

  it("extracts a quoted value", () => {
    const content = '---\ntitle: "Quoted Title"\n---\nBody';
    assert.equal(extractFrontmatterValue(content, "title"), "Quoted Title");
  });

  it("returns undefined for missing key", () => {
    const content = "---\ntitle: Test\n---\nBody";
    assert.equal(extractFrontmatterValue(content, "missing"), undefined);
  });

  it("returns undefined when no frontmatter", () => {
    const content = "# Title\nBody text";
    assert.equal(extractFrontmatterValue(content, "title"), undefined);
  });

  it("extracts boolean-like values as strings", () => {
    const content = "---\nregenerate_image: true\n---\nBody";
    assert.equal(extractFrontmatterValue(content, "regenerate_image"), "true");
  });
});

describe("shouldRegenerateImage", () => {
  it("returns true when regenerate_image is true", () => {
    const content = "---\ntitle: Test\nregenerate_image: true\n---\n# Test\n";
    assert.equal(shouldRegenerateImage(content), true);
  });

  it("returns false when regenerate_image is false", () => {
    const content = "---\ntitle: Test\nregenerate_image: false\n---\n# Test\n";
    assert.equal(shouldRegenerateImage(content), false);
  });

  it("returns false when regenerate_image is absent", () => {
    const content = "---\ntitle: Test\n---\n# Test\n";
    assert.equal(shouldRegenerateImage(content), false);
  });

  it("returns false when no frontmatter", () => {
    const content = "# Test\nBody text";
    assert.equal(shouldRegenerateImage(content), false);
  });
});

describe("removeImageEmbed", () => {
  it("removes Obsidian wiki image embed", () => {
    const content = "# Title\n![[attachments/hero.jpg]]\nBody text";
    const result = removeImageEmbed(content);
    assert.equal(result.imageName, "hero.jpg");
    assert.ok(!result.content.includes("![["));
    assert.ok(result.content.includes("Body text"));
  });

  it("removes wiki embed without attachments prefix", () => {
    const content = "# Title\n![[photo.png]]\nBody";
    const result = removeImageEmbed(content);
    assert.equal(result.imageName, "photo.png");
    assert.ok(!result.content.includes("![["));
  });

  it("returns unchanged content when no image embed", () => {
    const content = "# Title\nBody text";
    const result = removeImageEmbed(content);
    assert.equal(result.content, content);
    assert.equal(result.imageName, undefined);
  });

  it("collapses triple newlines after removal", () => {
    const content = "# Title\n\n![[attachments/img.jpg]]\n\nBody";
    const result = removeImageEmbed(content);
    assert.ok(!result.content.includes("\n\n\n"));
  });
});

describe("sanitizeForYaml", () => {
  it("removes double quotes", () => {
    assert.equal(sanitizeForYaml('A "magical" sunset'), "A magical sunset");
  });

  it("removes single quotes", () => {
    assert.equal(sanitizeForYaml("A 'golden' sunset"), "A golden sunset");
  });

  it("removes backslashes", () => {
    assert.equal(sanitizeForYaml("bright\\colors"), "brightcolors");
  });

  it("removes backticks", () => {
    assert.equal(sanitizeForYaml("a `code` block"), "a code block");
  });

  it("collapses newlines into spaces", () => {
    assert.equal(sanitizeForYaml("line one\nline two"), "line one line two");
  });

  it("collapses multiple spaces", () => {
    assert.equal(sanitizeForYaml("too   many   spaces"), "too many spaces");
  });

  it("trims leading and trailing whitespace", () => {
    assert.equal(sanitizeForYaml("  hello world  "), "hello world");
  });

  it("leaves clean text unchanged", () => {
    assert.equal(sanitizeForYaml("A vibrant sunset over mountains"), "A vibrant sunset over mountains");
  });
});

describe("updateFrontmatterFields", () => {
  it("adds fields to existing frontmatter", () => {
    const content = "---\ntitle: Test\n---\nBody";
    const result = updateFrontmatterFields(content, {
      image_date: "2026-03-21",
      image_model: "test-model",
    });
    assert.ok(result.includes("image_date: 2026-03-21"));
    assert.ok(result.includes("image_model: test-model"));
    assert.ok(result.includes("title: Test"));
  });

  it("updates existing fields", () => {
    const content = "---\ntitle: Test\nimage_date: old\n---\nBody";
    const result = updateFrontmatterFields(content, {
      image_date: "new",
    });
    assert.ok(result.includes("image_date: new"));
    assert.ok(!result.includes("image_date: old"));
  });

  it("creates frontmatter when none exists", () => {
    const content = "# Title\nBody";
    const result = updateFrontmatterFields(content, {
      image_model: "test-model",
    });
    assert.ok(result.startsWith("---\nimage_model: test-model\n---"));
  });

  it("quotes values with special YAML characters via js-yaml", () => {
    const content = "---\ntitle: Test\n---\nBody";
    const result = updateFrontmatterFields(content, {
      image_model: "@cf/black-forest-labs/flux-1-schnell",
    });
    assert.ok(result.includes('"@cf/black-forest-labs/flux-1-schnell"'));
  });

  it("sets regenerate_image to false", () => {
    const content = "---\ntitle: Test\nregenerate_image: true\n---\nBody";
    const result = updateFrontmatterFields(content, {
      regenerate_image: "false",
    });
    assert.ok(result.includes('regenerate_image: "false"'));
    assert.ok(!result.includes("regenerate_image: true"));
  });

  it("updates field that has no value (key with no space after colon)", () => {
    const content = "---\ntitle: Test\nimage_prompt:\n---\nBody";
    const result = updateFrontmatterFields(content, {
      image_prompt: "new value",
    });
    assert.ok(result.includes("image_prompt: new value"));
    const promptCount = (result.match(/^image_prompt:/gm) ?? []).length;
    assert.equal(promptCount, 1, "should have exactly one image_prompt field");
  });

  it("preserves arrays in frontmatter", () => {
    const content = "---\ntitle: Test\naliases:\n  - alias1\n  - alias2\n---\nBody";
    const result = updateFrontmatterFields(content, {
      image_model: "test-model",
    });
    assert.ok(result.includes("alias1"));
    assert.ok(result.includes("alias2"));
    assert.ok(result.includes("image_model: test-model"));
  });

  it("preserves empty tags field", () => {
    const content = "---\ntitle: Test\ntags:\n---\nBody";
    const result = updateFrontmatterFields(content, {
      updated: "2026-03-22",
    });
    assert.ok(result.includes("tags:"));
    assert.ok(result.includes("updated:"));
    assert.ok(result.includes("2026-03-22"));
    const tagsCount = (result.match(/^tags:/gm) ?? []).length;
    assert.equal(tagsCount, 1, "should have exactly one tags field");
  });

  it("handles colons in values via proper YAML serialization", () => {
    const content = "---\ntitle: Test\n---\nBody";
    const result = updateFrontmatterFields(content, {
      image_prompt: "A sunset: golden light over mountains",
    });
    assert.ok(result.includes("image_prompt:"));
    assert.ok(result.includes("A sunset: golden light over mountains"));
  });
});

describe("processNote with regeneration", () => {
  let tempDir: string;
  let blogDir: string;
  let attachmentsDir: string;

  const mockGenerate: ImageGenerator = async () => ({
    data: Buffer.from("fake-image-data"),
    mimeType: "image/jpeg",
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regen-test-"));
    blogDir = path.join(tempDir, "chickie-loo");
    fs.mkdirSync(blogDir, { recursive: true });
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("regenerates image when regenerate_image is true", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test-post.md");
    fs.mkdirSync(attachmentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(attachmentsDir, "old-image.jpg"),
      "old-image-data",
    );
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\nregenerate_image: true\n---\n# Test Post\n![[attachments/old-image.jpg]]\nBody\n",
    );

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
    );

    assert.equal(result.skipped, false);
    assert.equal(result.imageName, "chickie-loo-2026-03-22-test-post.jpg");

    const updated = fs.readFileSync(notePath, "utf-8");
    assert.ok(updated.includes("![[attachments/chickie-loo-2026-03-22-test-post.jpg]]"));
    assert.equal(shouldRegenerateImage(updated), false);
    assert.ok(!fs.existsSync(path.join(attachmentsDir, "old-image.jpg")));
  });

  it("skips note with image when regenerate_image is not set", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\n---\n# Test Post\n![[attachments/existing.jpg]]\nBody\n",
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

  it("writes image metadata to frontmatter", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\n---\n# Test Post\nBody text\n",
    );

    await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
    );

    const updated = fs.readFileSync(notePath, "utf-8");
    assert.ok(updated.includes("image_date:"));
    assert.ok(updated.includes("image_model: fake-model"));
    assert.ok(updated.includes("image_prompt:"));
  });

  it("uses prompt describer when provided", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\n---\n# Test Post\nBody text\n",
    );

    const mockDescriber: PromptDescriber = async () =>
      "A colorful abstract painting of technology";

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
      mockDescriber,
    );

    assert.equal(result.skipped, false);
    assert.equal(result.imagePrompt, "A colorful abstract painting of technology");

    const updated = fs.readFileSync(notePath, "utf-8");
    assert.ok(updated.includes("A colorful abstract painting of technology"));
  });
});

describe("backfillImages with regeneration", () => {
  let tempDir: string;
  let attachmentsDir: string;

  const mockGenerate: ImageGenerator = async () => ({
    data: Buffer.from("fake-image-data"),
    mimeType: "image/jpeg",
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "backfill-regen-"));
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("regenerates images for notes with regenerate_image flag", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.mkdirSync(attachmentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(attachmentsDir, "old.jpg"),
      "old-data",
    );
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\nregenerate_image: true\n---\n# Post\n![[attachments/old.jpg]]\nBody\n",
    );

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
    });

    assert.equal(result.imagesGenerated, 1);
    assert.ok(events.some((e) => e["event"] === "regenerating_image"));
  });

  it("passes describePrompt through to processNote", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    let describerCalled = false;
    const mockDescriber: PromptDescriber = async () => {
      describerCalled = true;
      return "described image prompt";
    };

    await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
      describePrompt: mockDescriber,
      minDelayMs: 0,
    });

    assert.ok(describerCalled);
  });
});

describe("resolveImageProvider with describer", () => {
  it("creates describePrompt when GEMINI_API_KEY is set with Cloudflare", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
      GEMINI_API_KEY: "gemini-key",
    };
    const provider = resolveImageProvider(env);
    assert.ok(provider.describePrompt !== undefined);
    assert.equal(typeof provider.describePrompt, "function");
  });

  it("creates describePrompt when only GEMINI_API_KEY is set", () => {
    const env = { GEMINI_API_KEY: "gemini-key" };
    const provider = resolveImageProvider(env);
    assert.ok(provider.describePrompt !== undefined);
  });

  it("has no describePrompt when GEMINI_API_KEY is missing", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
    };
    const provider = resolveImageProvider(env);
    assert.equal(provider.describePrompt, undefined);
  });
});

describe("makeGeminiDescriber", () => {
  it("returns a PromptDescriber function", () => {
    const describer = makeGeminiDescriber("fake-key", DEFAULT_DESCRIBER_MODEL);
    assert.equal(typeof describer, "function");
  });
});

describe("DEFAULT_DESCRIBER_MODEL", () => {
  it("uses gemini-3.1-flash-lite-preview", () => {
    assert.equal(DEFAULT_DESCRIBER_MODEL, "gemini-3.1-flash-lite-preview");
  });
});

describe("isDailyQuotaError", () => {
  it("detects daily quota messages", () => {
    assert.ok(isDailyQuotaError({ message: "quota exceeded, daily limit reached" }));
  });

  it("detects PerDay quota messages", () => {
    assert.ok(isDailyQuotaError({ message: "quota: RequestsPerDay limit" }));
  });

  it("detects per day messages", () => {
    assert.ok(isDailyQuotaError({ message: "quota limit per day exceeded" }));
  });

  it("returns false for per-minute rate limits", () => {
    assert.ok(!isDailyQuotaError({ message: "429: too many requests per minute" }));
  });

  it("returns false for non-quota errors", () => {
    assert.ok(!isDailyQuotaError({ message: "Invalid API key" }));
  });

  it("returns false for null", () => {
    assert.ok(!isDailyQuotaError(null));
  });

  it("returns false for non-object", () => {
    assert.ok(!isDailyQuotaError("string error"));
  });
});

describe("parseRetryDelay", () => {
  it("parses retry in seconds with decimal", () => {
    assert.equal(parseRetryDelay({ message: "Please retry in 14.473150856s." }), 14474);
  });

  it("parses retryDelay format", () => {
    assert.equal(parseRetryDelay({ message: 'retryDelay: "30s"' }), 30000);
  });

  it("returns null for unrecognized messages", () => {
    assert.equal(parseRetryDelay({ message: "Some other error" }), null);
  });

  it("returns null for null input", () => {
    assert.equal(parseRetryDelay(null), null);
  });

  it("returns null for non-object input", () => {
    assert.equal(parseRetryDelay("string"), null);
  });
});

describe("processNote with cached image_prompt", () => {
  let tempDir: string;
  let blogDir: string;
  let attachmentsDir: string;

  const mockGenerate: ImageGenerator = async () => ({
    data: Buffer.from("fake-image-data"),
    mimeType: "image/jpeg",
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "desc-cache-test-"));
    blogDir = path.join(tempDir, "chickie-loo");
    fs.mkdirSync(blogDir, { recursive: true });
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("uses cached image_prompt instead of calling describer", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\nimage_prompt: A beautiful sunset over mountains\n---\n# Test Post\nBody text\n",
    );

    let describerCalled = false;
    const mockDescriber: PromptDescriber = async () => {
      describerCalled = true;
      return "should not be used";
    };

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
      mockDescriber,
    );

    assert.equal(result.skipped, false);
    assert.equal(describerCalled, false);
    assert.equal(result.imagePrompt, "A beautiful sunset over mountains");
  });

  it("calls describer when no cached prompt exists", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\n---\n# Test Post\nBody text\n",
    );

    const mockDescriber: PromptDescriber = async () => "A freshly generated description";

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
      mockDescriber,
    );

    assert.equal(result.skipped, false);
    assert.equal(result.imagePrompt, "A freshly generated description");

    const updated = fs.readFileSync(notePath, "utf-8");
    assert.ok(updated.includes("image_prompt:"));
    assert.ok(!updated.includes("image_description:"));
  });

  it("uses cached prompt even during image regeneration", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test.md");
    fs.mkdirSync(attachmentsDir, { recursive: true });
    fs.writeFileSync(path.join(attachmentsDir, "old.jpg"), "old");
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\nregenerate_image: true\nimage_prompt: Cached description from before\n---\n# Test Post\n![[attachments/old.jpg]]\nBody\n",
    );

    let describerCalled = false;
    const mockDescriber: PromptDescriber = async () => {
      describerCalled = true;
      return "should not be called";
    };

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
      mockDescriber,
    );

    assert.equal(result.skipped, false);
    assert.equal(describerCalled, false);
    assert.equal(result.imagePrompt, "Cached description from before");
  });

  it("sanitizes describer output to remove quotes and special chars", async () => {
    const notePath = path.join(blogDir, "2026-03-22-test.md");
    fs.writeFileSync(
      notePath,
      "---\ntitle: Test Post\n---\n# Test Post\nBody text\n",
    );

    const mockDescriber: PromptDescriber = async () =>
      'A "magical" sunset with \'golden\' rays and \\bright\\ colors';

    const result = await processNote(
      notePath,
      attachmentsDir,
      "fake-key",
      "fake-model",
      mockGenerate,
      mockDescriber,
    );

    assert.equal(result.skipped, false);
    assert.ok(!result.imagePrompt?.includes('"'));
    assert.ok(!result.imagePrompt?.includes("'"));
    assert.ok(!result.imagePrompt?.includes("\\"));
    assert.equal(result.imagePrompt, "A magical sunset with golden rays and bright colors");
  });
});

describe("backfillImages cross-directory prioritization", () => {
  let tempDir: string;
  let attachmentsDir: string;

  const mockGenerate: ImageGenerator = async () => ({
    data: Buffer.from("fake-image-data"),
    mimeType: "image/jpeg",
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "backfill-priority-"));
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("processes newer posts from later directories before older posts from earlier directories", async () => {
    const reflDir = path.join(tempDir, "reflections");
    const chickieDir = path.join(tempDir, "chickie-loo");
    fs.mkdirSync(reflDir);
    fs.mkdirSync(chickieDir);

    fs.writeFileSync(
      path.join(reflDir, "2026-03-15.md"),
      "---\ntitle: Old Reflection\n---\n# Old Reflection\nBody\n",
    );
    fs.writeFileSync(
      path.join(chickieDir, "2026-03-21-recent-post.md"),
      "---\ntitle: Recent Chickie\n---\n# Recent Chickie\nBody\n",
    );

    const generated: string[] = [];
    const trackingGenerate: ImageGenerator = async (_k, _m, _p) => {
      return { data: Buffer.from("img"), mimeType: "image/jpeg" };
    };

    const events: Record<string, unknown>[] = [];
    await backfillImages({
      directories: [
        { path: reflDir, id: "reflections" },
        { path: chickieDir, id: "chickie-loo" },
      ],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: trackingGenerate,
      onProgress: (e) => {
        if (e["event"] === "generating_image") {
          generated.push(e["filename"] as string);
        }
        events.push(e);
      },
      minDelayMs: 0,
    });

    assert.equal(generated[0], "2026-03-21-recent-post.md");
    assert.equal(generated[1], "2026-03-15.md");
  });

  it("interleaves files from multiple directories by date", async () => {
    const dirA = path.join(tempDir, "series-a");
    const dirB = path.join(tempDir, "series-b");
    fs.mkdirSync(dirA);
    fs.mkdirSync(dirB);

    fs.writeFileSync(
      path.join(dirA, "2026-03-20-a-old.md"),
      "---\ntitle: A Old\n---\n# A Old\nBody\n",
    );
    fs.writeFileSync(
      path.join(dirA, "2026-03-22-a-new.md"),
      "---\ntitle: A New\n---\n# A New\nBody\n",
    );
    fs.writeFileSync(
      path.join(dirB, "2026-03-21-b-mid.md"),
      "---\ntitle: B Mid\n---\n# B Mid\nBody\n",
    );

    const generated: string[] = [];
    await backfillImages({
      directories: [
        { path: dirA, id: "series-a" },
        { path: dirB, id: "series-b" },
      ],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
      onProgress: (e) => {
        if (e["event"] === "generating_image") {
          generated.push(e["filename"] as string);
        }
      },
      minDelayMs: 0,
    });

    assert.deepEqual(generated, [
      "2026-03-22-a-new.md",
      "2026-03-21-b-mid.md",
      "2026-03-20-a-old.md",
    ]);
  });
});

describe("backfillImages rate limit handling", () => {
  let tempDir: string;
  let attachmentsDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "backfill-rate-"));
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("retries on per-minute rate limit instead of stopping", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    let callCount = 0;
    const rateLimitOnce: ImageGenerator = async () => {
      callCount++;
      if (callCount === 1) throw new Error("429 Too Many Requests per minute");
      return { data: Buffer.from("img"), mimeType: "image/jpeg" };
    };

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: rateLimitOnce,
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, false);
    assert.equal(result.imagesGenerated, 1);
    assert.ok(events.some((e) => e["event"] === "rate_limit_retry"));
  });

  it("stops on daily quota error", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const dailyQuotaGenerate: ImageGenerator = async () => {
      throw new Error("quota exceeded, daily limit reached");
    };

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: dailyQuotaGenerate,
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, true);
    assert.ok(events.some((e) => e["event"] === "daily_quota_exhausted"));
  });

  it("stops after exhausting retries on persistent rate limit", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-11-post2.md"),
      "---\ntitle: Post 2\n---\n# Post 2\nBody\n",
    );
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post1.md"),
      "---\ntitle: Post 1\n---\n# Post 1\nBody\n",
    );

    const alwaysRateLimit: ImageGenerator = async () => {
      throw new Error("429 Too Many Requests");
    };

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: alwaysRateLimit,
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, true);
    const retryEvents = events.filter((e) => e["event"] === "rate_limit_retry");
    assert.ok(retryEvents.length > 0);
  });

  it("respects proactive minDelayMs between generations", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-11-post2.md"),
      "---\ntitle: Post 2\n---\n# Post 2\nBody\n",
    );
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post1.md"),
      "---\ntitle: Post 1\n---\n# Post 1\nBody\n",
    );

    const mockGenerate: ImageGenerator = async () => ({
      data: Buffer.from("img"),
      mimeType: "image/jpeg",
    });

    let sleepCalls = 0;
    const trackingSleep = async (_ms: number): Promise<void> => {
      sleepCalls++;
    };

    await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
      minDelayMs: 5000,
      sleep: trackingSleep,
    });

    assert.ok(sleepCalls >= 2, `Expected at least 2 sleep calls, got ${sleepCalls}`);
  });

  it("uses parsed retry delay from error message", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    let callCount = 0;
    const rateLimitWithDelay: ImageGenerator = async () => {
      callCount++;
      if (callCount === 1) throw new Error("429: Please retry in 15s.");
      return { data: Buffer.from("img"), mimeType: "image/jpeg" };
    };

    const sleepDelays: number[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: rateLimitWithDelay,
      minDelayMs: 0,
      sleep: async (ms) => { sleepDelays.push(ms); },
    });

    assert.equal(result.imagesGenerated, 1);
    assert.ok(sleepDelays.includes(15000));
  });
});

describe("DEFAULT_HUGGINGFACE_IMAGE_MODEL", () => {
  it("uses black-forest-labs/FLUX.1-schnell", () => {
    assert.equal(DEFAULT_HUGGINGFACE_IMAGE_MODEL, "black-forest-labs/FLUX.1-schnell");
  });
});

describe("makeHuggingFaceGenerator", () => {
  it("returns an ImageGenerator function", () => {
    const generator = makeHuggingFaceGenerator();
    assert.equal(typeof generator, "function");
  });

  it("uses default model when none specified", () => {
    const generator = makeHuggingFaceGenerator();
    assert.equal(typeof generator, "function");
  });

  it("accepts custom model", () => {
    const generator = makeHuggingFaceGenerator("stabilityai/stable-diffusion-xl-base-1.0");
    assert.equal(typeof generator, "function");
  });
});

describe("resolveImageProviders", () => {
  it("returns Cloudflare as first provider when configured", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
    };
    const providers = resolveImageProviders(env);
    assert.equal(providers.length, 1);
    assert.equal(providers[0]!.name, "cloudflare");
    assert.equal(providers[0]!.apiKey, "cf-token");
  });

  it("returns HuggingFace as provider when configured", () => {
    const env = {
      HUGGINGFACE_API_TOKEN: "hf-token",
    };
    const providers = resolveImageProviders(env);
    assert.equal(providers.length, 1);
    assert.equal(providers[0]!.name, "huggingface");
    assert.equal(providers[0]!.apiKey, "hf-token");
    assert.equal(providers[0]!.model, DEFAULT_HUGGINGFACE_IMAGE_MODEL);
  });

  it("returns all configured providers in priority order", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
      HUGGINGFACE_API_TOKEN: "hf-token",
      GEMINI_API_KEY: "gemini-key",
    };
    const providers = resolveImageProviders(env);
    assert.equal(providers.length, 3);
    assert.equal(providers[0]!.name, "cloudflare");
    assert.equal(providers[1]!.name, "huggingface");
    assert.equal(providers[2]!.name, "gemini");
  });

  it("uses custom HuggingFace model from HUGGINGFACE_IMAGE_MODEL", () => {
    const env = {
      HUGGINGFACE_API_TOKEN: "hf-token",
      HUGGINGFACE_IMAGE_MODEL: "stabilityai/stable-diffusion-xl-base-1.0",
    };
    const providers = resolveImageProviders(env);
    assert.equal(providers[0]!.model, "stabilityai/stable-diffusion-xl-base-1.0");
  });

  it("throws when no credentials are available", () => {
    assert.throws(
      () => resolveImageProviders({}),
      /No image generation credentials found/,
    );
  });

  it("attaches describePrompt to all providers when GEMINI_API_KEY is set", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
      HUGGINGFACE_API_TOKEN: "hf-token",
      GEMINI_API_KEY: "gemini-key",
    };
    const providers = resolveImageProviders(env);
    assert.ok(providers.every((p) => typeof p.describePrompt === "function"));
  });

  it("has no describePrompt when GEMINI_API_KEY is missing", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
    };
    const providers = resolveImageProviders(env);
    assert.ok(providers.every((p) => p.describePrompt === undefined));
  });

  it("resolveImageProvider returns first from resolveImageProviders", () => {
    const env = {
      CLOUDFLARE_API_TOKEN: "cf-token",
      CLOUDFLARE_ACCOUNT_ID: "cf-account",
      HUGGINGFACE_API_TOKEN: "hf-token",
    };
    const single = resolveImageProvider(env);
    const all = resolveImageProviders(env);
    assert.equal(single.name, all[0]!.name);
    assert.equal(single.apiKey, all[0]!.apiKey);
  });
});

describe("backfillImages provider chain fallback", () => {
  let tempDir: string;
  let attachmentsDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "backfill-chain-"));
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("switches to fallback provider on quota exhaustion", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const quotaGenerator: ImageGenerator = async () => {
      throw new Error("429 Too Many Requests");
    };

    const fallbackGenerator: ImageGenerator = async () => ({
      data: Buffer.from("fallback-img"),
      mimeType: "image/jpeg",
    });

    const events: Record<string, unknown>[] = [];
    const fallback: ImageProviderConfig = {
      name: "fallback",
      apiKey: "fallback-key",
      model: "fallback-model",
      generator: fallbackGenerator,
    };

    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "primary-key",
      model: "primary-model",
      generate: quotaGenerator,
      fallbackProviders: [fallback],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, false);
    assert.equal(result.imagesGenerated, 1);
    assert.ok(events.some((e) => e["event"] === "provider_switch"));
    const switchEvent = events.find((e) => e["event"] === "provider_switch");
    assert.equal(switchEvent!["from"], "primary");
    assert.equal(switchEvent!["to"], "fallback");
  });

  it("stops when all providers are exhausted", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const quotaGenerator: ImageGenerator = async () => {
      throw new Error("429 Too Many Requests");
    };

    const events: Record<string, unknown>[] = [];
    const fallback: ImageProviderConfig = {
      name: "fallback",
      apiKey: "fallback-key",
      model: "fallback-model",
      generator: quotaGenerator,
    };

    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "primary-key",
      model: "primary-model",
      generate: quotaGenerator,
      fallbackProviders: [fallback],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, true);
    assert.equal(result.imagesGenerated, 0);
    assert.ok(events.some((e) => e["event"] === "provider_switch"));
  });

  it("continues with fallback provider for remaining candidates after switch", async () => {
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

    let primaryCalls = 0;
    const primaryGenerator: ImageGenerator = async () => {
      primaryCalls++;
      if (primaryCalls === 1) return { data: Buffer.from("primary-img"), mimeType: "image/jpeg" };
      throw new Error("429 Too Many Requests");
    };

    const fallbackGenerator: ImageGenerator = async () => ({
      data: Buffer.from("fallback-img"),
      mimeType: "image/jpeg",
    });

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "primary-key",
      model: "primary-model",
      generate: primaryGenerator,
      fallbackProviders: [{
        name: "fallback",
        apiKey: "fallback-key",
        model: "fallback-model",
        generator: fallbackGenerator,
      }],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, false);
    assert.equal(result.imagesGenerated, 2);
    assert.ok(events.some((e) => e["event"] === "provider_switch"));
  });

  it("switches on daily quota error too", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const dailyQuotaGenerator: ImageGenerator = async () => {
      throw new Error("quota exceeded, daily limit reached");
    };

    const fallbackGenerator: ImageGenerator = async () => ({
      data: Buffer.from("fallback-img"),
      mimeType: "image/jpeg",
    });

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "primary-key",
      model: "primary-model",
      generate: dailyQuotaGenerator,
      fallbackProviders: [{
        name: "fallback",
        apiKey: "fb-key",
        model: "fb-model",
        generator: fallbackGenerator,
      }],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, false);
    assert.equal(result.imagesGenerated, 1);
    assert.ok(events.some((e) => e["event"] === "provider_switch"));
  });

  it("works with no fallback providers (backward compatible)", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const quotaGenerator: ImageGenerator = async () => {
      throw new Error("429 Too Many Requests");
    };

    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: quotaGenerator,
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, true);
  });

  it("chains through multiple fallback providers", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const quotaGenerator: ImageGenerator = async () => {
      throw new Error("429 Too Many Requests");
    };

    const thirdGenerator: ImageGenerator = async () => ({
      data: Buffer.from("third-img"),
      mimeType: "image/jpeg",
    });

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "p-key",
      model: "p-model",
      generate: quotaGenerator,
      fallbackProviders: [
        { name: "second", apiKey: "s-key", model: "s-model", generator: quotaGenerator },
        { name: "third", apiKey: "t-key", model: "t-model", generator: thirdGenerator },
      ],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, false);
    assert.equal(result.imagesGenerated, 1);
    const switches = events.filter((e) => e["event"] === "provider_switch");
    assert.equal(switches.length, 2);
    assert.equal(switches[0]!["from"], "primary");
    assert.equal(switches[0]!["to"], "second");
    assert.equal(switches[1]!["from"], "second");
    assert.equal(switches[1]!["to"], "third");
  });

  it("includes provider name in progress events", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const mockGenerate: ImageGenerator = async () => ({
      data: Buffer.from("img"),
      mimeType: "image/jpeg",
    });

    const events: Record<string, unknown>[] = [];
    await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: mockGenerate,
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
    });

    const genEvent = events.find((e) => e["event"] === "image_generated");
    assert.ok(genEvent);
    assert.equal(genEvent!["provider"], "primary");
  });
});

describe("isProviderUnavailableError", () => {
  it("detects 410 Gone errors", () => {
    assert.equal(isProviderUnavailableError(new Error("HuggingFace API error 410: no longer supported")), true);
  });

  it("detects 401 Unauthorized errors", () => {
    assert.equal(isProviderUnavailableError(new Error("API error 401: Unauthorized")), true);
  });

  it("detects 403 Forbidden errors", () => {
    assert.equal(isProviderUnavailableError(new Error("API error 403: Forbidden")), true);
  });

  it("detects 'no longer supported' messages", () => {
    assert.equal(isProviderUnavailableError(new Error("This endpoint is no longer supported")), true);
  });

  it("detects 'deprecated' messages", () => {
    assert.equal(isProviderUnavailableError(new Error("This API has been deprecated")), true);
  });

  it("does not match quota errors", () => {
    assert.equal(isProviderUnavailableError(new Error("429 Too Many Requests")), false);
  });

  it("does not match generic errors", () => {
    assert.equal(isProviderUnavailableError(new Error("Network timeout")), false);
  });

  it("returns false for non-object values", () => {
    assert.equal(isProviderUnavailableError(null), false);
    assert.equal(isProviderUnavailableError(undefined), false);
    assert.equal(isProviderUnavailableError("string"), false);
  });
});

describe("backfillImages provider unavailable handling", () => {
  let tempDir: string;
  let attachmentsDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "backfill-unavail-"));
    attachmentsDir = path.join(tempDir, "attachments");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("switches provider on 410 Gone error", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const unavailableGenerator: ImageGenerator = async () => {
      throw new Error("HuggingFace API error 410: no longer supported");
    };

    const fallbackGenerator: ImageGenerator = async () => ({
      data: Buffer.from("fallback-img"),
      mimeType: "image/jpeg",
    });

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "primary-key",
      model: "primary-model",
      generate: unavailableGenerator,
      fallbackProviders: [{
        name: "fallback",
        apiKey: "fb-key",
        model: "fb-model",
        generator: fallbackGenerator,
      }],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, false);
    assert.equal(result.imagesGenerated, 1);
    const switchEvent = events.find((e) => e["event"] === "provider_switch");
    assert.ok(switchEvent);
    assert.equal(switchEvent!["reason"], "provider_unavailable");
  });

  it("switches provider on 401 Unauthorized error", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const unauthorizedGenerator: ImageGenerator = async () => {
      throw new Error("API error 401: Unauthorized");
    };

    const fallbackGenerator: ImageGenerator = async () => ({
      data: Buffer.from("fallback-img"),
      mimeType: "image/jpeg",
    });

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "bad-key",
      model: "model",
      generate: unauthorizedGenerator,
      fallbackProviders: [{
        name: "fallback",
        apiKey: "fb-key",
        model: "fb-model",
        generator: fallbackGenerator,
      }],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, false);
    assert.equal(result.imagesGenerated, 1);
    assert.ok(events.some((e) => e["event"] === "provider_unavailable"));
  });

  it("does not retry with same provider on unavailable error", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-11-post2.md"),
      "---\ntitle: Post 2\n---\n# Post 2\nBody\n",
    );
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post1.md"),
      "---\ntitle: Post 1\n---\n# Post 1\nBody\n",
    );

    let primaryCalls = 0;
    const unavailableGenerator: ImageGenerator = async () => {
      primaryCalls++;
      throw new Error("HuggingFace API error 410: this endpoint is no longer supported");
    };

    const fallbackGenerator: ImageGenerator = async () => ({
      data: Buffer.from("fallback-img"),
      mimeType: "image/jpeg",
    });

    const events: Record<string, unknown>[] = [];
    await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "primary-key",
      model: "primary-model",
      generate: unavailableGenerator,
      fallbackProviders: [{
        name: "fallback",
        apiKey: "fb-key",
        model: "fb-model",
        generator: fallbackGenerator,
      }],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(primaryCalls, 1, "Should only call unavailable provider once, not retry");
    const retryEvents = events.filter((e) => e["event"] === "rate_limit_retry");
    assert.equal(retryEvents.length, 0, "Should not retry on unavailable error");
  });

  it("stops when all providers are unavailable", async () => {
    const dir = path.join(tempDir, "series");
    fs.mkdirSync(dir);
    fs.writeFileSync(
      path.join(dir, "2026-03-10-post.md"),
      "---\ntitle: Post\n---\n# Post\nBody\n",
    );

    const unavailableGenerator: ImageGenerator = async () => {
      throw new Error("API error 410: deprecated endpoint");
    };

    const events: Record<string, unknown>[] = [];
    const result = await backfillImages({
      directories: [{ path: dir, id: "series" }],
      attachmentsDir,
      apiKey: "key",
      model: "model",
      generate: unavailableGenerator,
      fallbackProviders: [{
        name: "fallback",
        apiKey: "fb-key",
        model: "fb-model",
        generator: unavailableGenerator,
      }],
      onProgress: (e) => events.push(e),
      minDelayMs: 0,
      sleep: async () => {},
    });

    assert.equal(result.stoppedByQuota, true);
    assert.equal(result.imagesGenerated, 0);
  });
});
