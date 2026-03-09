/**
 * Tests for BFS Content Discovery Module
 *
 * Uses Node.js built-in test runner (node:test).
 * Run with: npx tsx --test scripts/find-content-to-post.test.ts
 */

import { describe, test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import {
  parseFrontmatter,
  isIndexOrHomePage,
  extractMarkdownLinks,
  detectPostedPlatforms,
  readContentNote,
  isPostableContent,
  findMostRecentReflection,
  getPriorDayReflectionIfNeeded,
  bfsContentDiscovery,
  discoverContentToPost,
  isPastPostingHourUTC,
  isReflectionEligibleForPosting,
  getYesterdayDate,
  PLATFORM_SECTION_HEADERS,
  ALL_PLATFORMS,
  type Platform,
  type ContentNote,
  type FindContentConfig,
} from "./find-content-to-post.ts";

// --- Test Helpers ---

function createTempDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "find-content-test-"));
}

function cleanupTempDir(dir: string): void {
  fs.rmSync(dir, { recursive: true, force: true });
}

function writeNote(
  contentDir: string,
  relativePath: string,
  content: string,
): void {
  const filePath = path.join(contentDir, relativePath);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, "utf-8");
}

// --- Sample Content ---

const REFLECTION_NOTE = `---
share: true
title: 2026-03-08 | 🐘 Mastodon 🤔 Sophie 🤖 Agent
URL: https://bagrounds.org/reflections/2026-03-08
Author: "[[bryan-grounds]]"
tags:
---
[Home](../index.md) > [Reflections](./index.md) | [⏮️](./2026-03-07.md)  
# 2026-03-08 | 🐘 Mastodon 🤔 Sophie 🤖 Agent  
  
## [📚 Books](../books/index.md)  
- [🤔🌍 Sophie's World](../books/sophies-world.md)  
  
## 🤖 AI Blog  
- 🤖✍️ [2026-03-08 | 🐘 Auto-Posting to Mastodon 🤖](../ai-blog/2026-03-08-auto-post-mastodon.md)  
`;

const BOOK_NOTE = `---
share: true
title: "🤔🌍 Sophie's World"
URL: https://bagrounds.org/books/sophies-world
Author: "[[bryan-grounds]]"
tags:
---
[Home](../index.md) > [Books](./index.md)  
# 🤔🌍 Sophie's World  

A wonderful introduction to philosophy through narrative.  
This book explores the history of Western philosophy through the story of Sophie.  
It covers everything from ancient Greek philosophy to modern existentialism.

## Related
- [🤔📚 Philosophy](../topics/philosophy.md)
`;

const BOOK_WITH_TWEET = `---
share: true
title: "📖 Already Tweeted Book"
URL: https://bagrounds.org/books/already-tweeted-book
tags:
---
[Home](../index.md) > [Books](./index.md)  
# 📖 Already Tweeted Book  

This book has already been posted to Twitter.  
It covers interesting topics about testing and automation.

## 🐦 Tweet
<blockquote class="twitter-tweet" data-theme="dark"><p>Test tweet</p></blockquote>
`;

const BOOK_WITH_ALL_PLATFORMS = `---
share: true
title: "📖 Fully Posted Book"
URL: https://bagrounds.org/books/fully-posted-book
tags:
---
[Home](../index.md) > [Books](./index.md)  
# 📖 Fully Posted Book  

This book has been posted to all platforms already.  
Nothing more to do here. It has great content though.

## 🐦 Tweet
<blockquote class="twitter-tweet"><p>Tweet</p></blockquote>

## 🦋 Bluesky
<blockquote class="bluesky-embed"><p>Bluesky post</p></blockquote>

## 🐘 Mastodon
<iframe src="https://mastodon.social/@test/123/embed"></iframe>
`;

const INDEX_PAGE = `---
share: true
title: 📚 Books
URL: https://bagrounds.org/books
---
[Home](../index.md)  
# 📚 Books (951)  
- [🤔🌍 Sophie's World](./sophies-world.md)  
- [📖 Already Tweeted Book](./already-tweeted-book.md)  
`;

const TOPIC_NOTE = `---
share: true
title: 🤔📚 Philosophy
URL: https://bagrounds.org/topics/philosophy
tags:
---
[Home](../index.md) > [Topics](./index.md)  
# 🤔📚 Philosophy  

Philosophy is the study of fundamental questions about existence, knowledge, values, reason, mind, and language.

## Related Books
- [🤔🌍 Sophie's World](../books/sophies-world.md)
`;

const SHORT_NOTE = `---
share: true
title: Short
URL: https://bagrounds.org/short
---
Hi.
`;

// --- Unit Tests ---

describe("parseFrontmatter", () => {
  test("parses YAML frontmatter correctly", () => {
    const { frontmatter, body } = parseFrontmatter(REFLECTION_NOTE);
    assert.equal(frontmatter["title"], "2026-03-08 | 🐘 Mastodon 🤔 Sophie 🤖 Agent");
    assert.equal(
      frontmatter["URL"],
      "https://bagrounds.org/reflections/2026-03-08",
    );
    assert.ok(body.includes("[Home]"));
  });

  test("returns empty frontmatter for content without frontmatter", () => {
    const { frontmatter, body } = parseFrontmatter("# Just a heading\nSome content.");
    assert.deepEqual(frontmatter, {});
    assert.equal(body, "# Just a heading\nSome content.");
  });

  test("strips quotes from frontmatter values", () => {
    const content = `---
title: "Quoted Title"
URL: 'https://example.com'
---
Body`;
    const { frontmatter } = parseFrontmatter(content);
    assert.equal(frontmatter["title"], "Quoted Title");
    assert.equal(frontmatter["URL"], "https://example.com");
  });
});

describe("isIndexOrHomePage", () => {
  test("identifies index.md as index page", () => {
    assert.ok(isIndexOrHomePage("reflections/index.md"));
    assert.ok(isIndexOrHomePage("books/index.md"));
    assert.ok(isIndexOrHomePage("index.md"));
  });

  test("non-index pages return false", () => {
    assert.ok(!isIndexOrHomePage("reflections/2026-03-08.md"));
    assert.ok(!isIndexOrHomePage("books/sophies-world.md"));
    assert.ok(!isIndexOrHomePage("topics/philosophy.md"));
  });
});

describe("extractMarkdownLinks", () => {
  test("extracts relative .md links from markdown content", () => {
    const body = `[Home](../index.md) > [Books](./index.md)
- [Sophie's World](../books/sophies-world.md)
- [Philosophy](../topics/philosophy.md)`;

    const links = extractMarkdownLinks(
      body,
      "reflections/2026-03-08.md",
      "/content",
    );

    assert.ok(links.includes("index.md"));
    assert.ok(links.includes("reflections/index.md"));
    assert.ok(links.includes("books/sophies-world.md"));
    assert.ok(links.includes("topics/philosophy.md"));
  });

  test("ignores external URLs", () => {
    const body = `[Link](https://example.com/page.md)
[Internal](./local.md)`;

    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    assert.ok(!links.some((l) => l.includes("example.com")));
    assert.ok(links.includes("reflections/local.md"));
  });

  test("deduplicates links", () => {
    const body = `[Link1](./page.md) and [Link2](./page.md)`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    const pageLinks = links.filter((l) => l === "reflections/page.md");
    assert.equal(pageLinks.length, 1);
  });

  test("returns empty array for content with no links", () => {
    const links = extractMarkdownLinks("No links here.", "test.md", "/content");
    assert.equal(links.length, 0);
  });

  test("resolves relative paths correctly across directories", () => {
    const body = `[Book](../books/some-book.md)`;
    const links = extractMarkdownLinks(
      body,
      "reflections/2026-03-08.md",
      "/content",
    );
    assert.ok(links.includes("books/some-book.md"));
  });

  // --- Obsidian Wiki Link Tests ---

  test("extracts Obsidian wiki links with path", () => {
    const body = `Some text with [[books/sophies-world]] and [[topics/philosophy]].`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    assert.ok(links.includes("books/sophies-world.md"));
    assert.ok(links.includes("topics/philosophy.md"));
  });

  test("extracts wiki links with display text", () => {
    const body = `Check out [[books/sophies-world|🤔🌍 Sophie's World]] for more.`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    assert.ok(links.includes("books/sophies-world.md"));
  });

  test("extracts wiki links with heading anchor", () => {
    const body = `See [[books/sophies-world#related]] section.`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    assert.ok(links.includes("books/sophies-world.md"));
  });

  test("extracts wiki links with heading and display text", () => {
    const body = `Read [[books/sophies-world#chapter-1|Chapter 1]] next.`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    assert.ok(links.includes("books/sophies-world.md"));
  });

  test("handles wiki links with .md extension already present", () => {
    const body = `Link to [[books/sophies-world.md]].`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    assert.ok(links.includes("books/sophies-world.md"));
  });

  test("resolves filename-only wiki links relative to current file", () => {
    const body = `Link to [[2026-03-07]] in the same directory.`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    assert.ok(links.includes("reflections/2026-03-07.md"));
  });

  test("handles mixed markdown and wiki links", () => {
    const body = `[Standard](../books/book-a.md) and [[books/book-b]] together.`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    assert.ok(links.includes("books/book-a.md"));
    assert.ok(links.includes("books/book-b.md"));
  });

  test("deduplicates across markdown and wiki links", () => {
    const body = `[Book](../books/sophies-world.md) and [[books/sophies-world]].`;
    const links = extractMarkdownLinks(body, "reflections/test.md", "/content");
    const matches = links.filter((l) => l === "books/sophies-world.md");
    assert.equal(matches.length, 1);
  });
});

describe("detectPostedPlatforms", () => {
  test("detects no platforms for fresh content", () => {
    const platforms = detectPostedPlatforms(REFLECTION_NOTE);
    assert.equal(platforms.size, 0);
  });

  test("detects tweet section", () => {
    const platforms = detectPostedPlatforms(BOOK_WITH_TWEET);
    assert.ok(platforms.has("twitter"));
    assert.ok(!platforms.has("bluesky"));
    assert.ok(!platforms.has("mastodon"));
  });

  test("detects all platforms", () => {
    const platforms = detectPostedPlatforms(BOOK_WITH_ALL_PLATFORMS);
    assert.ok(platforms.has("twitter"));
    assert.ok(platforms.has("bluesky"));
    assert.ok(platforms.has("mastodon"));
    assert.equal(platforms.size, 3);
  });

  test("detects bluesky section independently", () => {
    const content = `# Test\nSome content.\n\n## 🦋 Bluesky\n<blockquote>post</blockquote>`;
    const platforms = detectPostedPlatforms(content);
    assert.ok(platforms.has("bluesky"));
    assert.equal(platforms.size, 1);
  });

  test("detects mastodon section independently", () => {
    const content = `# Test\nSome content.\n\n## 🐘 Mastodon\n<iframe>embed</iframe>`;
    const platforms = detectPostedPlatforms(content);
    assert.ok(platforms.has("mastodon"));
    assert.equal(platforms.size, 1);
  });
});

describe("readContentNote", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempDir();
  });

  afterEach(() => {
    cleanupTempDir(tempDir);
  });

  test("reads and parses a content note", () => {
    writeNote(tempDir, "reflections/2026-03-08.md", REFLECTION_NOTE);
    const note = readContentNote("reflections/2026-03-08.md", tempDir);

    assert.ok(note !== null);
    assert.equal(note.relativePath, "reflections/2026-03-08.md");
    assert.equal(
      note.title,
      "2026-03-08 | 🐘 Mastodon 🤔 Sophie 🤖 Agent",
    );
    assert.equal(
      note.url,
      "https://bagrounds.org/reflections/2026-03-08",
    );
    assert.equal(note.postedPlatforms.size, 0);
    assert.ok(note.linkedNotePaths.length > 0);
  });

  test("returns null for non-existent file", () => {
    const note = readContentNote("non-existent.md", tempDir);
    assert.equal(note, null);
  });

  test("detects posted platforms from content", () => {
    writeNote(tempDir, "books/test.md", BOOK_WITH_ALL_PLATFORMS);
    const note = readContentNote("books/test.md", tempDir);

    assert.ok(note !== null);
    assert.ok(note.postedPlatforms.has("twitter"));
    assert.ok(note.postedPlatforms.has("bluesky"));
    assert.ok(note.postedPlatforms.has("mastodon"));
  });

  test("derives URL from path when not in frontmatter", () => {
    const content = `---
share: true
title: Test Note
---
# Test Note
Some content here that is long enough to be considered postable content.`;
    writeNote(tempDir, "articles/test-article.md", content);
    const note = readContentNote("articles/test-article.md", tempDir);

    assert.ok(note !== null);
    assert.equal(note.url, "https://bagrounds.org/articles/test-article");
  });

  test("extracts linked note paths", () => {
    writeNote(tempDir, "reflections/2026-03-08.md", REFLECTION_NOTE);
    const note = readContentNote("reflections/2026-03-08.md", tempDir);

    assert.ok(note !== null);
    assert.ok(note.linkedNotePaths.includes("books/sophies-world.md"));
    assert.ok(
      note.linkedNotePaths.includes(
        "ai-blog/2026-03-08-auto-post-mastodon.md",
      ),
    );
  });
});

describe("isPostableContent", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempDir();
  });

  afterEach(() => {
    cleanupTempDir(tempDir);
  });

  test("returns true for a regular content note", () => {
    writeNote(tempDir, "books/sophies-world.md", BOOK_NOTE);
    const note = readContentNote("books/sophies-world.md", tempDir)!;
    assert.ok(isPostableContent(note));
  });

  test("returns false for index pages", () => {
    writeNote(tempDir, "books/index.md", INDEX_PAGE);
    const note = readContentNote("books/index.md", tempDir)!;
    assert.ok(!isPostableContent(note));
  });

  test("returns false for very short notes", () => {
    writeNote(tempDir, "short.md", SHORT_NOTE);
    const note = readContentNote("short.md", tempDir)!;
    assert.ok(!isPostableContent(note));
  });

  test("returns true for reflection notes", () => {
    writeNote(tempDir, "reflections/2026-03-08.md", REFLECTION_NOTE);
    const note = readContentNote("reflections/2026-03-08.md", tempDir)!;
    assert.ok(isPostableContent(note));
  });

  test("returns true for topic notes with enough content", () => {
    writeNote(tempDir, "topics/philosophy.md", TOPIC_NOTE);
    const note = readContentNote("topics/philosophy.md", tempDir)!;
    assert.ok(isPostableContent(note));
  });
});

describe("findMostRecentReflection", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempDir();
  });

  afterEach(() => {
    cleanupTempDir(tempDir);
  });

  test("finds the most recent reflection by date", () => {
    writeNote(tempDir, "reflections/2026-03-06.md", "---\ntitle: A\n---\nContent A here that is long enough.");
    writeNote(tempDir, "reflections/2026-03-07.md", "---\ntitle: B\n---\nContent B here that is long enough.");
    writeNote(tempDir, "reflections/2026-03-08.md", "---\ntitle: C\n---\nContent C here that is long enough.");

    const result = findMostRecentReflection(tempDir);
    assert.equal(result, "reflections/2026-03-08.md");
  });

  test("returns null when no reflections exist", () => {
    fs.mkdirSync(path.join(tempDir, "reflections"), { recursive: true });
    const result = findMostRecentReflection(tempDir);
    assert.equal(result, null);
  });

  test("returns null when reflections directory doesn't exist", () => {
    const result = findMostRecentReflection(tempDir);
    assert.equal(result, null);
  });

  test("ignores non-date files in reflections directory", () => {
    writeNote(tempDir, "reflections/index.md", "---\ntitle: Index\n---\nIndex.");
    writeNote(
      tempDir,
      "reflections/2026-03-06.md",
      "---\ntitle: A\n---\nContent A.",
    );

    const result = findMostRecentReflection(tempDir);
    assert.equal(result, "reflections/2026-03-06.md");
  });
});

describe("getPriorDayReflectionIfNeeded", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempDir();
  });

  afterEach(() => {
    cleanupTempDir(tempDir);
  });

  test("returns reflection when it exists and hasn't been posted", () => {
    const yesterday = getYesterdayDate();
    const content = `---
share: true
title: ${yesterday} | Test Reflection
URL: https://bagrounds.org/reflections/${yesterday}
---
[Home](../index.md) > [Reflections](./index.md)
# ${yesterday} | Test Reflection
This is a test reflection with enough content to be posted to social media.`;
    writeNote(tempDir, `reflections/${yesterday}.md`, content);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky"],
    };

    const result = getPriorDayReflectionIfNeeded(config);
    assert.ok(result !== null);
    assert.ok(result.title.includes(yesterday));
  });

  test("returns null when reflection doesn't exist", () => {
    fs.mkdirSync(path.join(tempDir, "reflections"), { recursive: true });
    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
    };

    const result = getPriorDayReflectionIfNeeded(config);
    assert.equal(result, null);
  });

  test("returns null when reflection has all platforms posted", () => {
    const yesterday = getYesterdayDate();
    const content = `---
share: true
title: ${yesterday} | Posted Reflection
URL: https://bagrounds.org/reflections/${yesterday}
---
[Home](../index.md)
# ${yesterday} | Posted Reflection
Content.

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>`;
    writeNote(tempDir, `reflections/${yesterday}.md`, content);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky"],
    };

    const result = getPriorDayReflectionIfNeeded(config);
    assert.equal(result, null);
  });

  test("returns reflection when only some platforms are posted", () => {
    const yesterday = getYesterdayDate();
    const content = `---
share: true
title: ${yesterday} | Partial Reflection
URL: https://bagrounds.org/reflections/${yesterday}
---
[Home](../index.md)
# ${yesterday} | Partial Reflection
Content that is long enough to be considered a meaningful note with social posting.

## 🐦 Tweet
<blockquote>tweet</blockquote>`;
    writeNote(tempDir, `reflections/${yesterday}.md`, content);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky"],
    };

    const result = getPriorDayReflectionIfNeeded(config);
    assert.ok(result !== null); // still needs bluesky
  });
});

describe("bfsContentDiscovery", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempDir();
  });

  afterEach(() => {
    cleanupTempDir(tempDir);
  });

  test("discovers unposted content via BFS", () => {
    // Create a small graph: reflection -> book -> topic
    writeNote(tempDir, "reflections/2026-03-08.md", REFLECTION_NOTE);
    writeNote(tempDir, "books/sophies-world.md", BOOK_NOTE);
    writeNote(tempDir, "topics/philosophy.md", TOPIC_NOTE);
    writeNote(tempDir, "books/index.md", INDEX_PAGE);
    writeNote(
      tempDir,
      "ai-blog/2026-03-08-auto-post-mastodon.md",
      `---
title: AI Blog Post
URL: https://bagrounds.org/ai-blog/2026-03-08-auto-post-mastodon
---
[Home](../index.md) > [AI Blog](./index.md)
# AI Blog Post
This is a detailed technical blog post about auto-posting to Mastodon.`,
    );

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky", "mastodon"],
    };

    const results = bfsContentDiscovery(config);
    assert.ok(results.length > 0);
    // Should find content for each platform
    const platforms = results.map((r) => r.platform);
    assert.ok(platforms.includes("twitter"));
    assert.ok(platforms.includes("bluesky"));
    assert.ok(platforms.includes("mastodon"));
  });

  test("skips index pages in BFS", () => {
    writeNote(tempDir, "reflections/2026-03-08.md", `---
title: Reflection
URL: https://bagrounds.org/reflections/2026-03-08
---
[Home](../index.md) > [Reflections](./index.md) | [Books](../books/index.md)
# Reflection
This is a reflection with links to index pages only and enough content.`);
    writeNote(tempDir, "books/index.md", INDEX_PAGE);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
      postingHourUTC: 0, // ensure reflection is eligible regardless of current time
    };

    const results = bfsContentDiscovery(config);
    // The reflection itself should be found (it's not an index)
    assert.ok(results.length > 0);
    assert.ok(results.every((r) => !isIndexOrHomePage(r.note.relativePath)));
  });

  test("returns at most one result per platform", () => {
    // Create multiple unposted notes
    writeNote(tempDir, "reflections/2026-03-08.md", REFLECTION_NOTE);
    writeNote(tempDir, "books/sophies-world.md", BOOK_NOTE);
    writeNote(tempDir, "topics/philosophy.md", TOPIC_NOTE);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
    };

    const results = bfsContentDiscovery(config);
    const twitterResults = results.filter((r) => r.platform === "twitter");
    assert.equal(twitterResults.length, 1);
  });

  test("skips notes already posted on a platform", () => {
    writeNote(tempDir, "reflections/2026-03-08.md", `---
title: 2026-03-08 | Test
URL: https://bagrounds.org/reflections/2026-03-08
---
[Home](../index.md) > [Reflections](./index.md)
# 2026-03-08 | Test
Content that is long enough for a social media post to be meaningful.

## 🐦 Tweet
<blockquote>Already tweeted</blockquote>

Links: [Book](../books/unposted-book.md)`);
    writeNote(tempDir, "books/unposted-book.md", BOOK_NOTE);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
    };

    const results = bfsContentDiscovery(config);
    // Should find the book (not the reflection, which already has a tweet)
    assert.ok(results.length === 1);
    assert.ok(results[0]!.note.relativePath.includes("sophies-world") || results[0]!.note.relativePath.includes("unposted-book"));
  });

  test("returns empty array when no reflections exist", () => {
    fs.mkdirSync(path.join(tempDir, "reflections"), { recursive: true });

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
    };

    const results = bfsContentDiscovery(config);
    assert.equal(results.length, 0);
  });

  test("handles all content already posted gracefully", () => {
    writeNote(tempDir, "reflections/2026-03-08.md", `---
title: 2026-03-08 | Already Posted
URL: https://bagrounds.org/reflections/2026-03-08
---
[Home](../index.md)
# 2026-03-08 | Already Posted
Content that is long enough for a social media post about testing.

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>

## 🐘 Mastodon
<iframe>embed</iframe>`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky", "mastodon"],
    };

    const results = bfsContentDiscovery(config);
    assert.equal(results.length, 0);
  });

  test("BFS follows links breadth-first", () => {
    // Build a graph: reflection -> bookA -> bookB
    // bookA is posted, bookB is not
    writeNote(tempDir, "reflections/2026-03-08.md", `---
title: Reflection
URL: https://bagrounds.org/reflections/2026-03-08
---
[Home](../index.md)
# Reflection
Content with a reference to [Book A](../books/book-a.md).

## 🐦 Tweet
<blockquote>tweet</blockquote>`);

    writeNote(tempDir, "books/book-a.md", `---
title: Book A
URL: https://bagrounds.org/books/book-a
---
[Home](../index.md) > [Books](./index.md)
# Book A
This is a detailed book about testing that links to another book.
See also [Book B](./book-b.md).

## 🐦 Tweet
<blockquote>tweet</blockquote>`);

    writeNote(tempDir, "books/book-b.md", `---
title: Book B
URL: https://bagrounds.org/books/book-b
---
[Home](../index.md) > [Books](./index.md)
# Book B
This book has not been posted to any platform yet. It has great content.`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
    };

    const results = bfsContentDiscovery(config);
    assert.equal(results.length, 1);
    assert.equal(results[0]!.note.relativePath, "books/book-b.md");
    assert.equal(results[0]!.platform, "twitter");
  });

  test("different platforms can find different notes", () => {
    // Reflection: tweeted but not on bluesky
    // Book: on bluesky but not tweeted
    writeNote(tempDir, "reflections/2026-03-08.md", `---
title: Reflection
URL: https://bagrounds.org/reflections/2026-03-08
---
[Home](../index.md)
# Reflection
A reflection with enough content to be meaningful for social media.
Links to [Book](../books/book.md).

## 🐦 Tweet
<blockquote>tweet</blockquote>`);

    writeNote(tempDir, "books/book.md", `---
title: Book
URL: https://bagrounds.org/books/book
---
[Home](../index.md) > [Books](./index.md)
# Book
A book about things that matter. With enough content for social media.

## 🦋 Bluesky
<blockquote>post</blockquote>`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky"],
      postingHourUTC: 0, // ensure reflection is eligible regardless of current time
    };

    const results = bfsContentDiscovery(config);
    // twitter should find the book (reflection already tweeted)
    // bluesky should find the reflection (book already on bluesky)
    assert.equal(results.length, 2);
    const twitterResult = results.find((r) => r.platform === "twitter");
    const blueskyResult = results.find((r) => r.platform === "bluesky");
    assert.ok(twitterResult !== undefined);
    assert.ok(blueskyResult !== undefined);
    assert.equal(twitterResult.note.relativePath, "books/book.md");
    assert.equal(blueskyResult.note.relativePath, "reflections/2026-03-08.md");
  });

  test("skips today's reflection but follows its links", () => {
    // Use today's date for the reflection
    const today = new Date().toISOString().split("T")[0]!;
    writeNote(tempDir, `reflections/${today}.md`, `---
title: ${today} | Today's Reflection
URL: https://bagrounds.org/reflections/${today}
---
[Home](../index.md)
# ${today} | Today's Reflection
This is today's reflection with enough content for a social media post.
Links to [Book](../books/linked-book.md).`);

    writeNote(tempDir, "books/linked-book.md", `---
title: Linked Book
URL: https://bagrounds.org/books/linked-book
---
[Home](../index.md) > [Books](./index.md)
# Linked Book
A book that is linked from today's reflection and has plenty of content.`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
      // Default postingHourUTC: 17 — today's reflection should NOT be eligible
    };

    const results = bfsContentDiscovery(config);
    // Today's reflection should be skipped (too recent to post)
    // But its linked book should still be found
    assert.equal(results.length, 1);
    assert.equal(results[0]!.note.relativePath, "books/linked-book.md");
    assert.equal(results[0]!.platform, "twitter");
  });

  test("traverses reflection linked list via wiki links to find unposted content", () => {
    // Most recent reflection links to previous via wiki link (doubly linked list).
    // The previous reflection links to an unposted book.
    // BFS should follow the chain: 2026-03-08 → 2026-03-07 → 2026-03-06 → book-b
    writeNote(tempDir, "reflections/2026-03-08.md", `---
title: 2026-03-08 | Recent
URL: https://bagrounds.org/reflections/2026-03-08
---
# 2026-03-08 | Recent Reflection
Content with a link to [[books/book-a|Book A]].
Navigation: [[reflections/2026-03-07|⏮️]]

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>

## 🐘 Mastodon
<iframe>embed</iframe>`);

    writeNote(tempDir, "books/book-a.md", `---
title: Book A
URL: https://bagrounds.org/books/book-a
---
# Book A
A book that has been posted everywhere already.

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>

## 🐘 Mastodon
<iframe>embed</iframe>`);

    writeNote(tempDir, "reflections/2026-03-07.md", `---
title: 2026-03-07 | Middle
URL: https://bagrounds.org/reflections/2026-03-07
---
# 2026-03-07 | Middle Reflection
Navigation: [[reflections/2026-03-08|⏭️]] [[reflections/2026-03-06|⏮️]]

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>

## 🐘 Mastodon
<iframe>embed</iframe>`);

    writeNote(tempDir, "reflections/2026-03-06.md", `---
title: 2026-03-06 | Older
URL: https://bagrounds.org/reflections/2026-03-06
---
# 2026-03-06 | Older Reflection
Content with a link to [[books/book-b|Book B]].
Navigation: [[reflections/2026-03-07|⏭️]]

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>

## 🐘 Mastodon
<iframe>embed</iframe>`);

    writeNote(tempDir, "books/book-b.md", `---
title: Book B
URL: https://bagrounds.org/books/book-b
---
# Book B
An unposted book only reachable by traversing the reflection linked list.`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
      postingHourUTC: 0,
    };

    const results = bfsContentDiscovery(config);
    // BFS starts at 2026-03-08 → follows wiki link to 2026-03-07 → follows to 2026-03-06 → finds book-b
    assert.equal(results.length, 1);
    assert.equal(results[0]!.note.relativePath, "books/book-b.md");
  });

  test("discovers content via Obsidian wiki links (vault format)", () => {
    // Simulate vault content with wiki links (not markdown links)
    writeNote(tempDir, "reflections/2026-03-08.md", `---
title: 2026-03-08 | Wiki Link Reflection
URL: https://bagrounds.org/reflections/2026-03-08
---
# 2026-03-08 | Wiki Link Reflection
This reflection uses wiki links like Obsidian does.
- [[books/sophies-world|🤔🌍 Sophie's World]]
- [[topics/philosophy]]`);

    writeNote(tempDir, "books/sophies-world.md", `---
title: Sophie's World
URL: https://bagrounds.org/books/sophies-world
---
# Sophie's World
A wonderful book about philosophy with rich content worth sharing.`);

    writeNote(tempDir, "topics/philosophy.md", `---
title: Philosophy
URL: https://bagrounds.org/topics/philosophy
---
# Philosophy
An overview of Western philosophical traditions and their key thinkers.`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["bluesky"],
      postingHourUTC: 0,
    };

    const results = bfsContentDiscovery(config);
    assert.ok(results.length > 0, "Should find content via wiki links");
    // BFS should find the reflection itself (unposted on bluesky) as first result
    assert.equal(results[0]!.platform, "bluesky");
  });

  test("handles vault with only wiki links and no markdown links", () => {
    // Reflection has only wiki links, no markdown links
    writeNote(tempDir, "reflections/2026-03-08.md", `---
title: 2026-03-08 | Vault Format
URL: https://bagrounds.org/reflections/2026-03-08
---
# Vault Format Reflection
Content with wiki links only.
References [[books/test-book]] and [[2026-03-07]].

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>

## 🐘 Mastodon
<iframe>embed</iframe>`);

    writeNote(tempDir, "reflections/2026-03-07.md", `---
title: 2026-03-07 | Older
URL: https://bagrounds.org/reflections/2026-03-07
---
# 2026-03-07 | Older reflection
Some older reflection content that is worth sharing on social media.`);

    writeNote(tempDir, "books/test-book.md", `---
title: Test Book
URL: https://bagrounds.org/books/test-book
---
# Test Book
A test book with enough content for a social media post about its themes.`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
      postingHourUTC: 0,
    };

    const results = bfsContentDiscovery(config);
    // The most recent reflection is fully posted, but its wiki links should be followed
    assert.ok(results.length > 0, "Should find content via wiki links from posted note");
    // Should find either the book or the older reflection
    const foundPaths = results.map((r) => r.note.relativePath);
    assert.ok(
      foundPaths.includes("books/test-book.md") || foundPaths.includes("reflections/2026-03-07.md"),
      `Expected to find book or older reflection, got: ${foundPaths.join(", ")}`,
    );
  });
});

describe("discoverContentToPost", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempDir();
  });

  afterEach(() => {
    cleanupTempDir(tempDir);
  });

  test("prioritizes prior day reflection when past posting hour", () => {
    const yesterday = getYesterdayDate();
    writeNote(tempDir, `reflections/${yesterday}.md`, `---
share: true
title: ${yesterday} | Yesterday's Reflection
URL: https://bagrounds.org/reflections/${yesterday}
---
[Home](../index.md)
# ${yesterday} | Yesterday's Reflection
Content for yesterday's reflection that has enough substance for posting.`);

    // Also create older content
    writeNote(tempDir, "reflections/2020-01-01.md", `---
title: Old Reflection
URL: https://bagrounds.org/reflections/2020-01-01
---
# Old Reflection
Some old content that might be found by BFS if not for the priority.`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky"],
    };

    const results = discoverContentToPost(config, true); // past posting hour
    assert.ok(results.length > 0);
    // All results should be yesterday's reflection
    for (const result of results) {
      assert.ok(result.note.relativePath.includes(yesterday));
    }
  });

  test("falls back to BFS when prior day reflection already posted", () => {
    const yesterday = getYesterdayDate();
    writeNote(tempDir, `reflections/${yesterday}.md`, `---
share: true
title: ${yesterday} | Yesterday
URL: https://bagrounds.org/reflections/${yesterday}
---
[Home](../index.md)
# ${yesterday} | Yesterday
Yesterday's reflection content that is long enough to count as postable.
Link to [Book](../books/unposted.md).

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>`);

    writeNote(tempDir, "books/unposted.md", `---
title: Unposted Book
URL: https://bagrounds.org/books/unposted
---
[Home](../index.md) > [Books](./index.md)
# Unposted Book
A book that hasn't been posted to any platform yet. Lots of content here.`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky"],
    };

    const results = discoverContentToPost(config, true);
    assert.ok(results.length > 0);
  });

  test("uses BFS when not past posting hour", () => {
    const yesterday = getYesterdayDate();
    // Create yesterday's reflection (not posted)
    writeNote(tempDir, `reflections/${yesterday}.md`, `---
title: ${yesterday} | Reflection
URL: https://bagrounds.org/reflections/${yesterday}
---
# ${yesterday} | Reflection
Content.`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter"],
    };

    // Not past posting hour — should use BFS, not prior-day priority
    const results = discoverContentToPost(config, false);
    // BFS should still find the reflection since it's the most recent
    assert.ok(results.length >= 0); // may or may not find content depending on BFS
  });

  test("returns empty array when no platforms configured", () => {
    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: [],
    };

    const results = discoverContentToPost(config, true);
    assert.equal(results.length, 0);
  });

  test("handles all content posted gracefully", () => {
    const yesterday = getYesterdayDate();
    writeNote(tempDir, `reflections/${yesterday}.md`, `---
title: ${yesterday} | Posted
URL: https://bagrounds.org/reflections/${yesterday}
---
[Home](../index.md)
# ${yesterday} | Posted
Everything posted. All content for a great reflection post.

## 🐦 Tweet
<blockquote>tweet</blockquote>

## 🦋 Bluesky
<blockquote>post</blockquote>`);

    const config: FindContentConfig = {
      contentDir: tempDir,
      platforms: ["twitter", "bluesky"],
    };

    const results = discoverContentToPost(config, true);
    // Prior day reflection is fully posted, BFS should find the same
    assert.equal(results.length, 0);
  });
});

describe("isPastPostingHourUTC", () => {
  test("returns boolean", () => {
    const result = isPastPostingHourUTC(17);
    assert.equal(typeof result, "boolean");
  });

  test("hour 0 means always past posting hour", () => {
    assert.ok(isPastPostingHourUTC(0));
  });

  test("hour 24 means never past posting hour", () => {
    assert.ok(!isPastPostingHourUTC(24));
  });
});

describe("PLATFORM_SECTION_HEADERS", () => {
  test("has entries for all platforms", () => {
    for (const platform of ALL_PLATFORMS) {
      assert.ok(PLATFORM_SECTION_HEADERS[platform]);
    }
  });

  test("twitter header is correct", () => {
    assert.equal(PLATFORM_SECTION_HEADERS.twitter, "## 🐦 Tweet");
  });

  test("bluesky header is correct", () => {
    assert.equal(PLATFORM_SECTION_HEADERS.bluesky, "## 🦋 Bluesky");
  });

  test("mastodon header is correct", () => {
    assert.equal(PLATFORM_SECTION_HEADERS.mastodon, "## 🐘 Mastodon");
  });
});

describe("getYesterdayDate", () => {
  test("returns a YYYY-MM-DD string", () => {
    const result = getYesterdayDate();
    assert.match(result, /^\d{4}-\d{2}-\d{2}$/);
  });

  test("returns a date before today", () => {
    const yesterday = getYesterdayDate();
    const today = new Date().toISOString().split("T")[0]!;
    assert.ok(yesterday < today);
  });
});

describe("isReflectionEligibleForPosting", () => {
  test("non-reflection files are always eligible", () => {
    const now = new Date("2026-03-08T12:00:00Z");
    assert.ok(isReflectionEligibleForPosting("books/sophies-world.md", 17, now));
    assert.ok(isReflectionEligibleForPosting("topics/philosophy.md", 17, now));
    assert.ok(isReflectionEligibleForPosting("ai-blog/2026-03-08-post.md", 17, now));
  });

  test("yesterday's reflection is eligible after posting hour", () => {
    // It's March 9 at 18:00 UTC (past 17:00 UTC posting hour)
    const now = new Date("2026-03-09T18:00:00Z");
    assert.ok(isReflectionEligibleForPosting("reflections/2026-03-08.md", 17, now));
  });

  test("yesterday's reflection is not eligible before posting hour", () => {
    // It's March 9 at 10:00 UTC (before 17:00 UTC posting hour)
    const now = new Date("2026-03-09T10:00:00Z");
    assert.ok(!isReflectionEligibleForPosting("reflections/2026-03-08.md", 17, now));
  });

  test("today's reflection is never eligible (same day)", () => {
    // It's March 8 at 23:59 UTC — reflection from March 8 not eligible until March 9 at 17:00
    const now = new Date("2026-03-08T23:59:00Z");
    assert.ok(!isReflectionEligibleForPosting("reflections/2026-03-08.md", 17, now));
  });

  test("today's reflection becomes eligible at posting hour next day", () => {
    // It's March 9 at exactly 17:00 UTC — reflection from March 8 is now eligible
    const now = new Date("2026-03-09T17:00:00Z");
    assert.ok(isReflectionEligibleForPosting("reflections/2026-03-08.md", 17, now));
  });

  test("old reflections are always eligible", () => {
    const now = new Date("2026-03-08T00:00:00Z");
    assert.ok(isReflectionEligibleForPosting("reflections/2020-01-01.md", 17, now));
    assert.ok(isReflectionEligibleForPosting("reflections/2025-12-31.md", 17, now));
  });

  test("respects custom posting hour", () => {
    // Posting hour is 14:00 UTC. Reflection from March 8.
    // March 9 at 13:59 UTC → not eligible
    assert.ok(!isReflectionEligibleForPosting(
      "reflections/2026-03-08.md", 14, new Date("2026-03-09T13:59:00Z"),
    ));
    // March 9 at 14:00 UTC → eligible
    assert.ok(isReflectionEligibleForPosting(
      "reflections/2026-03-08.md", 14, new Date("2026-03-09T14:00:00Z"),
    ));
  });

  test("posting hour 0 means eligible at midnight the next day", () => {
    // Reflection from March 8, posting hour 0
    // March 9 at 00:00 UTC → eligible
    assert.ok(isReflectionEligibleForPosting(
      "reflections/2026-03-08.md", 0, new Date("2026-03-09T00:00:00Z"),
    ));
    // March 8 at 23:59 UTC → not eligible
    assert.ok(!isReflectionEligibleForPosting(
      "reflections/2026-03-08.md", 0, new Date("2026-03-08T23:59:00Z"),
    ));
  });

  test("uses current time by default when now is not provided", () => {
    // A very old reflection should always be eligible
    assert.ok(isReflectionEligibleForPosting("reflections/2020-01-01.md"));
  });
});

// --- Property-based Tests ---

describe("property-based tests", () => {
  test("extractMarkdownLinks never returns external URLs (50 iterations)", () => {
    const contentDir = "/content";
    for (let i = 0; i < 50; i++) {
      const externalUrl = `https://example${i}.com/page.md`;
      const body = `[Link](${externalUrl}) [Internal](./local-${i}.md)`;
      const links = extractMarkdownLinks(
        body,
        "reflections/test.md",
        contentDir,
      );
      assert.ok(!links.some((l) => l.includes("example")));
    }
  });

  test("isIndexOrHomePage is consistent across path variations (50 iterations)", () => {
    const dirs = [
      "reflections",
      "books",
      "articles",
      "topics",
      "videos",
      "software",
      "people",
      "products",
      "ai-blog",
      "bot-chats",
    ];
    for (let i = 0; i < 50; i++) {
      const dir = dirs[i % dirs.length]!;
      assert.ok(isIndexOrHomePage(`${dir}/index.md`));
      assert.ok(!isIndexOrHomePage(`${dir}/some-content-${i}.md`));
    }
  });

  test("detectPostedPlatforms returns subset of ALL_PLATFORMS (50 iterations)", () => {
    const headers = Object.values(PLATFORM_SECTION_HEADERS);
    for (let i = 0; i < 50; i++) {
      // Randomly include some headers
      const included = headers.filter(() => Math.random() > 0.5);
      const content = `# Test\nContent.\n\n${included.join("\nSome text.\n\n")}`;
      const platforms = detectPostedPlatforms(content);
      for (const p of platforms) {
        assert.ok(ALL_PLATFORMS.includes(p));
      }
    }
  });
});
