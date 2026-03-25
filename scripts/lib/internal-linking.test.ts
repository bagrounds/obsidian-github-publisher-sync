/**
 * Tests for the internal linking library.
 *
 * Covers: emoji stripping, regex escaping, wikilink formatting,
 * context extraction, frontmatter parsing, content index building,
 * BFS traversal, protected region masking, candidate discovery,
 * link replacement, and prompt building.
 *
 * @module internal-linking.test
 */

import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import {
  stripEmojis,
  escapeRegex,
  formatWikilink,
  extractContext,
  countWords,
  parseFrontmatter,
  buildContentIndex,
  extractLinkedPaths,
  findMostRecentReflection,
  bfsTraversal,
  maskProtectedRegions,
  extractExistingLinkedPaths,
  findLinkCandidates,
  buildIdentificationPrompt,
  applyReplacements,
  generateDiff,
  contentAlreadyLinksTo,
  updateFrontmatterTimestamp,
  updateFrontmatterFields,
  recordLinkAnalysis,
  alreadyAnalyzed,
  extractBody,
  extractJsonArray,
  isRateLimitError,
  isDailyQuotaError,
  parseRetryDelay,
  QuotaExhaustedError,
  LINKABLE_DIRS,
  MIN_TITLE_LENGTH,
  MIN_WORD_COUNT_WITHOUT_AI,
  type ContentEntry,
  type LinkCandidate,
} from "./internal-linking.ts";

// --- Test Fixtures ---

const BOOK_ENTRY: ContentEntry = {
  relativePath: "books/thinking-fast-and-slow.md",
  title: "🤔🐇🐢 Thinking, Fast and Slow",
  plainTitle: "Thinking, Fast and Slow",
};

const SOFTWARE_ENTRY: ContentEntry = {
  relativePath: "software/babylon.md",
  title: "🌐🧱🖥️🎮 Babylon.js",
  plainTitle: "Babylon.js",
};

const LONG_BOOK_ENTRY: ContentEntry = {
  relativePath: "books/domain-driven-design.md",
  title: "🧩🧱⚙️❤️ Domain-Driven Design: Tackling Complexity in the Heart of Software",
  plainTitle: "Domain-Driven Design: Tackling Complexity in the Heart of Software",
};

// --- stripEmojis ---

describe("stripEmojis", () => {
  it("strips leading emojis from a title", () => {
    assert.equal(stripEmojis("🤔🐇🐢 Thinking, Fast and Slow"), "Thinking, Fast and Slow");
  });

  it("strips multiple emoji groups", () => {
    assert.equal(stripEmojis("🧩🧱⚙️❤️ Domain-Driven Design"), "Domain-Driven Design");
  });

  it("strips flag emojis", () => {
    assert.equal(stripEmojis("🇺🇸 American History"), "American History");
  });

  it("returns empty string for all-emoji input", () => {
    assert.equal(stripEmojis("🎮🧬"), "");
  });

  it("preserves text with no emojis", () => {
    assert.equal(stripEmojis("Thinking, Fast and Slow"), "Thinking, Fast and Slow");
  });

  it("handles ZWJ sequences (family emoji)", () => {
    const result = stripEmojis("👨‍👩‍👧‍👦 Family Guide");
    assert.equal(result, "Family Guide");
  });

  it("handles skin tone modifiers", () => {
    assert.equal(stripEmojis("🧘🏼‍♀️ Meditation Guide"), "Meditation Guide");
  });

  it("collapses multiple spaces after stripping", () => {
    assert.equal(stripEmojis("🎮  🧬  Valence"), "Valence");
  });

  it("handles embedded emojis", () => {
    const result = stripEmojis("📈🧘🏼‍♀️ 10% Happier");
    assert.equal(result, "10% Happier");
  });
});

// --- escapeRegex ---

describe("escapeRegex", () => {
  it("escapes special regex characters", () => {
    assert.equal(escapeRegex("Thinking, Fast and Slow"), "Thinking, Fast and Slow");
  });

  it("escapes dots", () => {
    assert.equal(escapeRegex("Babylon.js"), "Babylon\\.js");
  });

  it("escapes parentheses and brackets", () => {
    assert.equal(escapeRegex("foo(bar)[baz]"), "foo\\(bar\\)\\[baz\\]");
  });

  it("escapes question marks and asterisks", () => {
    assert.equal(escapeRegex("what? how*"), "what\\? how\\*");
  });

  it("escapes dollar signs and carets", () => {
    assert.equal(escapeRegex("$100 ^high"), "\\$100 \\^high");
  });
});

// --- formatWikilink ---

describe("formatWikilink", () => {
  it("formats a wikilink with path and title alias", () => {
    assert.equal(
      formatWikilink(BOOK_ENTRY),
      "[[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]]",
    );
  });

  it("strips .md from the path", () => {
    const entry: ContentEntry = {
      relativePath: "software/git.md",
      title: "💾➕🤝 Git",
      plainTitle: "Git",
    };
    assert.equal(formatWikilink(entry), "[[software/git|💾➕🤝 Git]]");
  });
});

// --- extractContext ---

describe("extractContext", () => {
  it("extracts context around a position", () => {
    const text = "a".repeat(200) + "TARGET" + "b".repeat(200);
    const ctx = extractContext(text, 200, 6, 50);
    assert.ok(ctx.startsWith("..."));
    assert.ok(ctx.endsWith("..."));
    assert.ok(ctx.includes("TARGET"));
  });

  it("handles match at start of content", () => {
    const text = "TARGET rest of content";
    const ctx = extractContext(text, 0, 6, 50);
    assert.ok(!ctx.startsWith("..."));
    assert.ok(ctx.includes("TARGET"));
  });

  it("handles match at end of content", () => {
    const text = "start of content TARGET";
    const ctx = extractContext(text, 17, 6, 50);
    assert.ok(!ctx.endsWith("..."));
    assert.ok(ctx.includes("TARGET"));
  });
});

// --- parseFrontmatter ---

describe("parseFrontmatter", () => {
  it("parses simple key-value frontmatter", () => {
    const content = `---\ntitle: My Title\nURL: https://example.com\n---\nBody`;
    const fm = parseFrontmatter(content);
    assert.equal(fm["title"], "My Title");
    assert.equal(fm["URL"], "https://example.com");
  });

  it("strips quotes from values", () => {
    const content = `---\ntitle: "Quoted Title"\n---\nBody`;
    const fm = parseFrontmatter(content);
    assert.equal(fm["title"], "Quoted Title");
  });

  it("returns empty object for no frontmatter", () => {
    const fm = parseFrontmatter("No frontmatter here");
    assert.deepEqual(fm, {});
  });

  it("returns empty object for unclosed frontmatter", () => {
    const fm = parseFrontmatter("---\ntitle: Test\nNo closing");
    assert.deepEqual(fm, {});
  });

  it("handles frontmatter with emojis in title", () => {
    const content = `---\ntitle: 🤔🐇🐢 Thinking, Fast and Slow\n---\nBody`;
    const fm = parseFrontmatter(content);
    assert.equal(fm["title"], "🤔🐇🐢 Thinking, Fast and Slow");
  });
});

// --- buildContentIndex ---

describe("buildContentIndex", () => {
  const tmpDir = { path: "" };

  beforeEach(() => {
    tmpDir.path = fs.mkdtempSync(path.join(os.tmpdir(), "internal-linking-test-"));
    fs.mkdirSync(path.join(tmpDir.path, "books"), { recursive: true });
    fs.mkdirSync(path.join(tmpDir.path, "software"), { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tmpDir.path, { recursive: true, force: true });
  });

  it("indexes files with valid titles", () => {
    fs.writeFileSync(
      path.join(tmpDir.path, "books", "thinking-fast-and-slow.md"),
      "---\ntitle: 🤔🐇🐢 Thinking, Fast and Slow\n---\nContent",
    );

    const index = buildContentIndex(tmpDir.path);
    assert.equal(index.length, 1);
    assert.equal(index[0]?.relativePath, "books/thinking-fast-and-slow.md");
    assert.equal(index[0]?.title, "🤔🐇🐢 Thinking, Fast and Slow");
    assert.equal(index[0]?.plainTitle, "Thinking, Fast and Slow");
  });

  it("skips index.md files", () => {
    fs.writeFileSync(
      path.join(tmpDir.path, "books", "index.md"),
      "---\ntitle: 📚 Books Index Page Title\n---\nIndex",
    );

    const index = buildContentIndex(tmpDir.path);
    assert.equal(index.length, 0);
  });

  it("skips files without titles", () => {
    fs.writeFileSync(
      path.join(tmpDir.path, "books", "no-title.md"),
      "---\nshare: true\n---\nContent without title",
    );

    const index = buildContentIndex(tmpDir.path);
    assert.equal(index.length, 0);
  });

  it("skips files with short plain titles", () => {
    fs.writeFileSync(
      path.join(tmpDir.path, "books", "git.md"),
      "---\ntitle: 💾 Git\n---\nContent",
    );

    const index = buildContentIndex(tmpDir.path);
    assert.equal(index.length, 0);
    // "Git" is only 3 chars, below MIN_TITLE_LENGTH
  });

  it("only indexes books directory (not software, topics, etc.)", () => {
    fs.writeFileSync(
      path.join(tmpDir.path, "books", "atomic-habits.md"),
      "---\ntitle: ⚛️🔄 Atomic Habits Is Great\n---\nContent",
    );
    fs.writeFileSync(
      path.join(tmpDir.path, "software", "babylon.md"),
      "---\ntitle: 🌐🧱🖥️🎮 Babylon.js Running\n---\nContent",
    );

    const index = buildContentIndex(tmpDir.path);
    assert.equal(index.length, 1);
    assert.equal(index[0]?.relativePath, "books/atomic-habits.md");
  });

  it("skips non-existent directories gracefully", () => {
    // "topics" dir doesn't exist in tmpDir
    const index = buildContentIndex(tmpDir.path);
    assert.ok(Array.isArray(index));
  });
});

// --- extractLinkedPaths ---

describe("extractLinkedPaths", () => {
  const tmpDir = { path: "" };

  beforeEach(() => {
    tmpDir.path = fs.mkdtempSync(path.join(os.tmpdir(), "internal-linking-links-"));
    fs.mkdirSync(path.join(tmpDir.path, "reflections"), { recursive: true });
    fs.mkdirSync(path.join(tmpDir.path, "books"), { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tmpDir.path, { recursive: true, force: true });
  });

  it("extracts markdown links", () => {
    const body = "[Book](../books/thinking-fast-and-slow.md)";
    const links = extractLinkedPaths(body, "reflections/2026-03-21.md", tmpDir.path);
    assert.ok(links.includes("books/thinking-fast-and-slow.md"));
  });

  it("extracts wikilinks with directory path", () => {
    const body = "Read [[books/domain-driven-design|DDD]] yesterday";
    const links = extractLinkedPaths(body, "reflections/2026-03-21.md", tmpDir.path);
    assert.ok(links.includes("books/domain-driven-design.md"));
  });

  it("extracts wikilinks with heading anchors", () => {
    const body = "See [[books/thinking-fast-and-slow#chapter-1|Chapter 1]]";
    const links = extractLinkedPaths(body, "reflections/2026-03-21.md", tmpDir.path);
    assert.ok(links.includes("books/thinking-fast-and-slow.md"));
  });

  it("skips external URLs", () => {
    const body = "[Link](https://example.com/page.md)";
    const links = extractLinkedPaths(body, "reflections/2026-03-21.md", tmpDir.path);
    assert.equal(links.length, 0);
  });

  it("deduplicates links", () => {
    const body = "[A](../books/foo.md) and [B](../books/foo.md)";
    const links = extractLinkedPaths(body, "reflections/2026-03-21.md", tmpDir.path);
    assert.equal(links.filter((l) => l === "books/foo.md").length, 1);
  });
});

// --- findMostRecentReflection ---

describe("findMostRecentReflection", () => {
  const tmpDir = { path: "" };

  beforeEach(() => {
    tmpDir.path = fs.mkdtempSync(path.join(os.tmpdir(), "internal-linking-reflect-"));
    fs.mkdirSync(path.join(tmpDir.path, "reflections"), { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tmpDir.path, { recursive: true, force: true });
  });

  it("returns the most recent reflection by date", () => {
    fs.writeFileSync(path.join(tmpDir.path, "reflections", "2026-03-19.md"), "");
    fs.writeFileSync(path.join(tmpDir.path, "reflections", "2026-03-21.md"), "");
    fs.writeFileSync(path.join(tmpDir.path, "reflections", "2026-03-20.md"), "");

    assert.equal(findMostRecentReflection(tmpDir.path), "reflections/2026-03-21.md");
  });

  it("returns null when no reflections exist", () => {
    assert.equal(findMostRecentReflection(tmpDir.path), null);
  });

  it("ignores index.md", () => {
    fs.writeFileSync(path.join(tmpDir.path, "reflections", "index.md"), "");
    fs.writeFileSync(path.join(tmpDir.path, "reflections", "2026-03-20.md"), "");

    assert.equal(findMostRecentReflection(tmpDir.path), "reflections/2026-03-20.md");
  });

  it("returns null when reflections directory does not exist", () => {
    fs.rmSync(path.join(tmpDir.path, "reflections"), { recursive: true });
    assert.equal(findMostRecentReflection(tmpDir.path), null);
  });
});

// --- bfsTraversal ---

describe("bfsTraversal", () => {
  const tmpDir = { path: "" };

  beforeEach(() => {
    tmpDir.path = fs.mkdtempSync(path.join(os.tmpdir(), "internal-linking-bfs-"));
    fs.mkdirSync(path.join(tmpDir.path, "reflections"), { recursive: true });
    fs.mkdirSync(path.join(tmpDir.path, "books"), { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tmpDir.path, { recursive: true, force: true });
  });

  it("traverses from most recent reflection following links", () => {
    fs.writeFileSync(
      path.join(tmpDir.path, "reflections", "2026-03-21.md"),
      "---\ntitle: 2026-03-21\n---\n[Book](../books/test-book.md)",
    );
    fs.writeFileSync(
      path.join(tmpDir.path, "books", "test-book.md"),
      "---\ntitle: Test Book Title Here\n---\nContent here",
    );

    const visited = bfsTraversal(tmpDir.path);
    assert.equal(visited.length, 2);
    assert.equal(visited[0], "reflections/2026-03-21.md");
    assert.equal(visited[1], "books/test-book.md");
  });

  it("returns empty array when no reflections exist", () => {
    assert.deepEqual(bfsTraversal(tmpDir.path), []);
  });

  it("skips index.md files", () => {
    fs.writeFileSync(
      path.join(tmpDir.path, "reflections", "2026-03-21.md"),
      "---\ntitle: test\n---\n[Index](../books/index.md)",
    );
    fs.writeFileSync(path.join(tmpDir.path, "books", "index.md"), "---\ntitle: Index\n---\nContent");

    const visited = bfsTraversal(tmpDir.path);
    assert.equal(visited.length, 1); // Only the reflection
  });

  it("follows wikilinks", () => {
    fs.writeFileSync(
      path.join(tmpDir.path, "reflections", "2026-03-21.md"),
      "---\ntitle: test\n---\n[[books/test-book|Test Book]]",
    );
    fs.writeFileSync(
      path.join(tmpDir.path, "books", "test-book.md"),
      "---\ntitle: Test Book Title Here\n---\nContent",
    );

    const visited = bfsTraversal(tmpDir.path);
    assert.equal(visited.length, 2);
    assert.ok(visited.includes("books/test-book.md"));
  });
});

// --- maskProtectedRegions ---

describe("maskProtectedRegions", () => {
  it("masks frontmatter", () => {
    const content = "---\ntitle: Test\n---\nBody text here";
    const masked = maskProtectedRegions(content);
    assert.ok(masked.includes("Body text here"));
    assert.ok(!masked.includes("title: Test"));
    assert.equal(masked.length, content.length);
  });

  it("masks fenced code blocks", () => {
    const content = "Before\n```\ncode here\n```\nAfter";
    const masked = maskProtectedRegions(content);
    assert.ok(masked.includes("Before"));
    assert.ok(masked.includes("After"));
    assert.ok(!masked.includes("code here"));
    assert.equal(masked.length, content.length);
  });

  it("masks inline code", () => {
    const content = "Use `Thinking, Fast and Slow` as a reference";
    const masked = maskProtectedRegions(content);
    assert.ok(!masked.includes("Thinking, Fast and Slow"));
    assert.ok(masked.includes("Use"));
    assert.ok(masked.includes("as a reference"));
    assert.equal(masked.length, content.length);
  });

  it("masks markdown links", () => {
    const content = "See [Thinking, Fast and Slow](../books/thinking.md) for details";
    const masked = maskProtectedRegions(content);
    assert.ok(!masked.includes("Thinking, Fast and Slow"));
    assert.ok(masked.includes("See"));
    assert.ok(masked.includes("for details"));
    assert.equal(masked.length, content.length);
  });

  it("masks wikilinks", () => {
    const content = "Read [[books/thinking-fast|Thinking, Fast and Slow]] yesterday";
    const masked = maskProtectedRegions(content);
    assert.ok(!masked.includes("Thinking, Fast and Slow"));
    assert.ok(masked.includes("Read"));
    assert.ok(masked.includes("yesterday"));
    assert.equal(masked.length, content.length);
  });

  it("masks headings", () => {
    const content = "## Thinking, Fast and Slow\nBody text";
    const masked = maskProtectedRegions(content);
    assert.ok(!masked.includes("## Thinking, Fast and Slow"));
    assert.ok(masked.includes("Body text"));
    assert.equal(masked.length, content.length);
  });

  it("masks bare URLs", () => {
    const content = "Visit https://example.com/thinking for more";
    const masked = maskProtectedRegions(content);
    assert.ok(!masked.includes("https://example.com/thinking"));
    assert.ok(masked.includes("Visit"));
    assert.ok(masked.includes("for more"));
    assert.equal(masked.length, content.length);
  });

  it("preserves unprotected text", () => {
    const content = "This mentions Thinking, Fast and Slow in plain text";
    const masked = maskProtectedRegions(content);
    assert.ok(masked.includes("Thinking, Fast and Slow"));
    assert.equal(masked.length, content.length);
  });
});

// --- extractExistingLinkedPaths ---

describe("extractExistingLinkedPaths", () => {
  const tmpDir = { path: "" };

  beforeEach(() => {
    tmpDir.path = fs.mkdtempSync(path.join(os.tmpdir(), "internal-linking-existing-"));
    fs.mkdirSync(path.join(tmpDir.path, "reflections"), { recursive: true });
    fs.mkdirSync(path.join(tmpDir.path, "books"), { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tmpDir.path, { recursive: true, force: true });
  });

  it("extracts markdown link paths", () => {
    const content = "[Book](../books/thinking-fast-and-slow.md)";
    const paths = extractExistingLinkedPaths(content, "reflections/2026-03-21.md", tmpDir.path);
    assert.ok(paths.has("books/thinking-fast-and-slow.md"));
  });

  it("extracts wikilink paths", () => {
    const content = "[[books/domain-driven-design|DDD]]";
    const paths = extractExistingLinkedPaths(content, "reflections/2026-03-21.md", tmpDir.path);
    assert.ok(paths.has("books/domain-driven-design.md"));
  });

  it("extracts wikilinks with anchors", () => {
    const content = "[[books/thinking-fast-and-slow#chapter]]";
    const paths = extractExistingLinkedPaths(content, "reflections/2026-03-21.md", tmpDir.path);
    assert.ok(paths.has("books/thinking-fast-and-slow.md"));
  });
});

// --- findLinkCandidates ---

describe("findLinkCandidates", () => {
  it("finds exact title matches in unmasked content", () => {
    const content = "I read Thinking, Fast and Slow yesterday and loved it";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");

    assert.equal(candidates.length, 1);
    assert.equal(candidates[0]?.matchedText, "Thinking, Fast and Slow");
    assert.equal(candidates[0]?.entry.relativePath, "books/thinking-fast-and-slow.md");
  });

  it("skips self-references", () => {
    const content = "This page is about Thinking, Fast and Slow";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(
      content,
      masked,
      [BOOK_ENTRY],
      new Set(),
      "books/thinking-fast-and-slow.md",
    );

    assert.equal(candidates.length, 0);
  });

  it("skips already-linked content", () => {
    const content = "I read Thinking, Fast and Slow yesterday";
    const masked = maskProtectedRegions(content);
    const existingLinks = new Set(["books/thinking-fast-and-slow.md"]);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], existingLinks, "reflections/test.md");

    assert.equal(candidates.length, 0);
  });

  it("prefers longer matches over shorter ones", () => {
    const shortEntry: ContentEntry = {
      relativePath: "books/domain-driven-design-short.md",
      title: "🧩 Domain-Driven Design",
      plainTitle: "Domain-Driven Design",
    };

    const content = "The book Domain-Driven Design: Tackling Complexity in the Heart of Software is great";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(
      content,
      masked,
      [shortEntry, LONG_BOOK_ENTRY],
      new Set(),
      "reflections/test.md",
    );

    assert.equal(candidates.length, 1);
    assert.equal(candidates[0]?.entry.relativePath, "books/domain-driven-design.md");
  });

  it("handles case-insensitive matching", () => {
    const content = "I read thinking, fast and slow yesterday";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");

    assert.equal(candidates.length, 1);
    assert.equal(candidates[0]?.matchedText, "thinking, fast and slow");
  });

  it("only takes first match per entry", () => {
    const content = "Thinking, Fast and Slow is great. Thinking, Fast and Slow again.";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");

    assert.equal(candidates.length, 1);
  });

  it("does not match partial titles at word boundaries", () => {
    const content = "The thinking process is fast and slow today";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");

    // "thinking" doesn't match "Thinking, Fast and Slow" because word boundaries
    assert.equal(candidates.length, 0);
  });

  it("finds multiple different entries in same content", () => {
    const entry2: ContentEntry = {
      relativePath: "books/atomic-habits.md",
      title: "⚛️🔄 Atomic Habits Is Great",
      plainTitle: "Atomic Habits Is Great",
    };
    const content = "I read Thinking, Fast and Slow and also Atomic Habits Is Great";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(
      content,
      masked,
      [BOOK_ENTRY, entry2],
      new Set(),
      "reflections/test.md",
    );

    assert.equal(candidates.length, 2);
  });
});

// --- buildIdentificationPrompt ---

describe("buildIdentificationPrompt", () => {
  it("builds a prompt with book list and file content", () => {
    const bookEntries: readonly ContentEntry[] = [BOOK_ENTRY, LONG_BOOK_ENTRY];
    const fileBody = "I recommend reading Thinking, Fast and Slow for book club";

    const prompt = buildIdentificationPrompt(fileBody, bookEntries, "reflections/test.md");
    assert.ok(prompt.system.includes("identify genuine book references"));
    assert.ok(prompt.user.includes("Thinking, Fast and Slow"));
    assert.ok(prompt.user.includes("books/thinking-fast-and-slow.md"));
    assert.ok(prompt.user.includes("reflections/test.md"));
    assert.ok(prompt.user.includes("I recommend reading"));
  });

  it("lists all available books", () => {
    const bookEntries: readonly ContentEntry[] = [BOOK_ENTRY, LONG_BOOK_ENTRY];
    const prompt = buildIdentificationPrompt("body", bookEntries, "test.md");
    assert.ok(prompt.user.includes("books/thinking-fast-and-slow.md"));
    assert.ok(prompt.user.includes("books/domain-driven-design.md"));
  });

  it("warns about generic word matches in system prompt", () => {
    const prompt = buildIdentificationPrompt("body", [BOOK_ENTRY], "test.md");
    assert.ok(prompt.system.includes("diplomacy"));
    assert.ok(prompt.system.includes("foundation"));
    assert.ok(prompt.system.includes("common sense"));
  });

  it("explains what constitutes a genuine book reference", () => {
    const prompt = buildIdentificationPrompt("body", [BOOK_ENTRY], "test.md");
    assert.ok(prompt.system.includes("literary work"));
    assert.ok(prompt.system.includes("recommend"));
    assert.ok(prompt.system.includes("reading list"));
  });
});

// --- applyReplacements ---

describe("applyReplacements", () => {
  it("replaces validated candidates with wikilinks", () => {
    const content = "I read Thinking, Fast and Slow yesterday";
    const candidates: readonly LinkCandidate[] = [
      {
        entry: BOOK_ENTRY,
        matchedText: "Thinking, Fast and Slow",
        position: 7,
        context: content,
      },
    ];
    const validations = [true];

    const result = applyReplacements(content, candidates, validations);
    assert.equal(
      result,
      "I read [[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]] yesterday",
    );
  });

  it("skips invalidated candidates", () => {
    const content = "I read Thinking, Fast and Slow yesterday";
    const candidates: readonly LinkCandidate[] = [
      {
        entry: BOOK_ENTRY,
        matchedText: "Thinking, Fast and Slow",
        position: 7,
        context: content,
      },
    ];
    const validations = [false];

    const result = applyReplacements(content, candidates, validations);
    assert.equal(result, content);
  });

  it("handles multiple replacements in correct order", () => {
    const content = "Read Thinking, Fast and Slow and also Babylon.js Running today";
    const entry2: ContentEntry = {
      relativePath: "software/babylon.md",
      title: "🌐🧱🖥️🎮 Babylon.js Running",
      plainTitle: "Babylon.js Running",
    };
    const candidates: readonly LinkCandidate[] = [
      {
        entry: BOOK_ENTRY,
        matchedText: "Thinking, Fast and Slow",
        position: 5,
        context: content,
      },
      {
        entry: entry2,
        matchedText: "Babylon.js Running",
        position: 38,
        context: content,
      },
    ];
    const validations = [true, true];

    const result = applyReplacements(content, candidates, validations);
    assert.ok(result.includes("[[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]]"));
    assert.ok(result.includes("[[software/babylon|🌐🧱🖥️🎮 Babylon.js Running]]"));
  });

  it("handles mixed validation results", () => {
    const content = "Read Thinking, Fast and Slow and also Babylon.js Running today";
    const entry2: ContentEntry = {
      relativePath: "software/babylon.md",
      title: "🌐 Babylon.js Running",
      plainTitle: "Babylon.js Running",
    };
    const candidates: readonly LinkCandidate[] = [
      {
        entry: BOOK_ENTRY,
        matchedText: "Thinking, Fast and Slow",
        position: 5,
        context: content,
      },
      {
        entry: entry2,
        matchedText: "Babylon.js Running",
        position: 38,
        context: content,
      },
    ];
    const validations = [true, false];

    const result = applyReplacements(content, candidates, validations);
    assert.ok(result.includes("[[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]]"));
    assert.ok(result.includes("Babylon.js Running today")); // Not linked
    assert.ok(!result.includes("[[software/babylon"));
  });

  it("returns original content when all validations are false", () => {
    const content = "Some content here";
    const candidates: readonly LinkCandidate[] = [
      {
        entry: BOOK_ENTRY,
        matchedText: "content",
        position: 5,
        context: content,
      },
    ];
    const validations = [false];

    assert.equal(applyReplacements(content, candidates, validations), content);
  });
});

// --- Integration: masking + candidate finding ---

describe("masking + candidate finding integration", () => {
  it("does not match titles inside existing markdown links", () => {
    const content = "Already linked [Thinking, Fast and Slow](../books/thinking.md) in text";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 0);
  });

  it("does not match titles inside existing wikilinks", () => {
    const content = "Already linked [[books/thinking|Thinking, Fast and Slow]] in text";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 0);
  });

  it("does not match titles in headings", () => {
    const content = "## Thinking, Fast and Slow\nSome body text";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 0);
  });

  it("does not match titles in code blocks", () => {
    const content = "```\nThinking, Fast and Slow\n```\nBody text";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 0);
  });

  it("does not match titles in inline code", () => {
    const content = "Use `Thinking, Fast and Slow` as a reference in body text";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 0);
  });

  it("does not match titles in frontmatter", () => {
    const content = "---\ntitle: Thinking, Fast and Slow\n---\nBody text";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 0);
  });

  it("matches titles in plain body text after frontmatter", () => {
    const content = "---\ntitle: Some Note\n---\nI loved Thinking, Fast and Slow as a book";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 1);
  });

  it("handles mixed protected and unprotected regions", () => {
    const content = [
      "---",
      "title: Test",
      "---",
      "## My Heading",
      "I read Thinking, Fast and Slow last week.",
      "[Already linked](../books/other.md)",
      "```",
      "Thinking, Fast and Slow in code",
      "```",
    ].join("\n");

    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");

    // Only the one in plain text should match
    assert.equal(candidates.length, 1);
    assert.ok(candidates[0]?.context.includes("I read"));
  });
});

// --- MIN_TITLE_LENGTH constant ---

describe("MIN_TITLE_LENGTH", () => {
  it("is set to a reasonable minimum to avoid false positives", () => {
    assert.ok(MIN_TITLE_LENGTH >= 5);
    assert.ok(MIN_TITLE_LENGTH <= 15);
  });
});

// --- countWords ---

describe("countWords", () => {
  it("counts words separated by spaces", () => {
    assert.equal(countWords("Thinking, Fast and Slow"), 4);
  });

  it("counts hyphenated words as multiple", () => {
    assert.equal(countWords("Domain-Driven Design"), 3);
  });

  it("counts single words", () => {
    assert.equal(countWords("Engineering"), 1);
  });

  it("handles empty strings", () => {
    assert.equal(countWords(""), 0);
  });

  it("handles compound software names", () => {
    assert.equal(countWords("Babylon.js"), 1);
  });
});

// --- MIN_WORD_COUNT_WITHOUT_AI ---

describe("MIN_WORD_COUNT_WITHOUT_AI", () => {
  it("requires at least 2 words without AI", () => {
    assert.equal(MIN_WORD_COUNT_WITHOUT_AI, 2);
  });
});

// --- findLinkCandidates with hasAiValidation ---

describe("findLinkCandidates hasAiValidation filtering", () => {
  const singleWordEntry: ContentEntry = {
    relativePath: "topics/engineering.md",
    title: "🏗️🔧 Engineering",
    plainTitle: "Engineering",
  };

  const multiWordEntry: ContentEntry = {
    relativePath: "books/thinking-fast-and-slow.md",
    title: "🤔🐇🐢 Thinking, Fast and Slow",
    plainTitle: "Thinking, Fast and Slow",
  };

  it("includes single-word titles when hasAiValidation is true", () => {
    const content = "The field of Engineering is fascinating";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(
      content, masked, [singleWordEntry], new Set(), "reflections/test.md", true,
    );
    assert.equal(candidates.length, 1);
  });

  it("excludes single-word titles when hasAiValidation is false", () => {
    const content = "The field of Engineering is fascinating";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(
      content, masked, [singleWordEntry], new Set(), "reflections/test.md", false,
    );
    assert.equal(candidates.length, 0);
  });

  it("keeps multi-word titles regardless of hasAiValidation", () => {
    const content = "I read Thinking, Fast and Slow yesterday";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(
      content, masked, [multiWordEntry], new Set(), "reflections/test.md", false,
    );
    assert.equal(candidates.length, 1);
  });

  it("keeps hyphenated titles without AI (counted as multi-word)", () => {
    const hyphenEntry: ContentEntry = {
      relativePath: "books/catch-22.md",
      title: "📖 Catch-22",
      plainTitle: "Catch-22",
    };
    const content = "The novel Catch-22 is a classic";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(
      content, masked, [hyphenEntry], new Set(), "reflections/test.md", false,
    );
    assert.equal(candidates.length, 1);
  });
});

// --- LINKABLE_DIRS ---

describe("LINKABLE_DIRS", () => {
  it("contains only books", () => {
    assert.deepEqual([...LINKABLE_DIRS], ["books"]);
  });
});

// --- contentAlreadyLinksTo ---

describe("contentAlreadyLinksTo", () => {
  it("returns true when content contains a wikilink to the entry", () => {
    const content = "I recommend [[books/thinking-fast-and-slow|Thinking, Fast and Slow]]";
    assert.equal(contentAlreadyLinksTo(content, BOOK_ENTRY), true);
  });

  it("returns true when content contains a markdown link to the entry", () => {
    const content = "I recommend [the book](../books/thinking-fast-and-slow.md)";
    assert.equal(contentAlreadyLinksTo(content, BOOK_ENTRY), true);
  });

  it("returns false when the entry path is not in the content", () => {
    const content = "I recommend reading more books about psychology";
    assert.equal(contentAlreadyLinksTo(content, BOOK_ENTRY), false);
  });

  it("returns true even when the path appears in a heading anchor", () => {
    const content = "See [[books/thinking-fast-and-slow#chapter-1]]";
    assert.equal(contentAlreadyLinksTo(content, BOOK_ENTRY), true);
  });

  it("does not false-positive on a longer path that shares a prefix", () => {
    const entry: ContentEntry = {
      relativePath: "books/thinking-fast.md",
      title: "📖 Thinking Fast",
      plainTitle: "Thinking Fast",
    };
    const content = "See [[books/thinking-fast-and-slow|TFS]] for more";
    assert.equal(contentAlreadyLinksTo(content, entry), false);
  });
});

// --- findLinkCandidates skips existing links anywhere ---

describe("findLinkCandidates skips existing links anywhere in file", () => {
  it("skips entries whose path already appears in the content", () => {
    const content = "Great book: [[books/thinking-fast-and-slow|TFS]]\nAlso Thinking, Fast and Slow is mentioned in plain text";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 0);
  });

  it("still finds candidates when path is not in the content", () => {
    const content = "I recently read Thinking, Fast and Slow and it was great";
    const masked = maskProtectedRegions(content);
    const candidates = findLinkCandidates(content, masked, [BOOK_ENTRY], new Set(), "reflections/test.md");
    assert.equal(candidates.length, 1);
  });
});

// --- generateDiff ---

describe("generateDiff", () => {
  it("returns empty array for identical content", () => {
    const content = "Line 1\nLine 2\nLine 3";
    assert.deepEqual(generateDiff(content, content), []);
  });

  it("shows changed lines with line numbers", () => {
    const original = "Line 1\nI read Thinking, Fast and Slow\nLine 3";
    const modified = "Line 1\nI read [[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]]\nLine 3";
    const diff = generateDiff(original, modified);
    assert.ok(diff.some((l) => l.includes("@@ line 2 @@")));
    assert.ok(diff.some((l) => l.startsWith("- I read Thinking")));
    assert.ok(diff.some((l) => l.startsWith("+ I read [[books")));
  });

  it("handles additions when modified has more lines", () => {
    const original = "Line 1";
    const modified = "Line 1\nLine 2";
    const diff = generateDiff(original, modified);
    assert.ok(diff.some((l) => l.startsWith("+ Line 2")));
  });

  it("handles removals when original has more lines", () => {
    const original = "Line 1\nLine 2";
    const modified = "Line 1";
    const diff = generateDiff(original, modified);
    assert.ok(diff.some((l) => l.startsWith("- Line 2")));
  });

  it("only includes changed lines, not unchanged ones", () => {
    const original = "Line 1\nLine 2\nLine 3";
    const modified = "Line 1\nModified\nLine 3";
    const diff = generateDiff(original, modified);
    assert.ok(!diff.some((l) => l.includes("Line 1")));
    assert.ok(!diff.some((l) => l.includes("Line 3")));
  });
});

// --- updateFrontmatterTimestamp ---

describe("updateFrontmatterTimestamp", () => {
  const tmpDir = { path: "" };

  beforeEach(() => {
    tmpDir.path = fs.mkdtempSync(path.join(os.tmpdir(), "internal-linking-ts-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir.path, { recursive: true, force: true });
  });

  it("updates existing updated field", () => {
    const filePath = path.join(tmpDir.path, "test.md");
    fs.writeFileSync(filePath, "---\ntitle: Test\nupdated: 2026-01-01T00:00:00.000Z\n---\nBody");

    updateFrontmatterTimestamp(filePath, "2026-03-22T00:00:00.000Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("updated: 2026-03-22T00:00:00.000Z"));
    assert.ok(!content.includes("2026-01-01"));
  });

  it("inserts updated field when missing from frontmatter", () => {
    const filePath = path.join(tmpDir.path, "test.md");
    fs.writeFileSync(filePath, "---\ntitle: Test\n---\nBody");

    updateFrontmatterTimestamp(filePath, "2026-03-22T00:00:00.000Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("updated: 2026-03-22T00:00:00.000Z"));
    assert.ok(content.includes("title: Test"));
  });

  it("creates frontmatter block when none exists", () => {
    const filePath = path.join(tmpDir.path, "test.md");
    fs.writeFileSync(filePath, "Body only");

    updateFrontmatterTimestamp(filePath, "2026-03-22T00:00:00.000Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.startsWith("---\nupdated: 2026-03-22T00:00:00.000Z\n---\n"));
    assert.ok(content.includes("Body only"));
  });

  it("does nothing for non-existent files", () => {
    const filePath = path.join(tmpDir.path, "nonexistent.md");
    updateFrontmatterTimestamp(filePath, "2026-03-22T00:00:00.000Z");
    assert.ok(!fs.existsSync(filePath));
  });
});

// --- extractBody ---

describe("extractBody", () => {
  it("extracts body after frontmatter", () => {
    const content = "---\ntitle: Test\n---\nBody text here";
    assert.equal(extractBody(content), "Body text here");
  });

  it("returns full content when no frontmatter", () => {
    const content = "Just body text";
    assert.equal(extractBody(content), "Just body text");
  });

  it("returns full content when unclosed frontmatter", () => {
    const content = "---\ntitle: Test\nNo closing";
    assert.equal(extractBody(content), "---\ntitle: Test\nNo closing");
  });
});

// --- extractJsonArray ---

describe("extractJsonArray", () => {
  it("parses clean JSON array", () => {
    assert.deepEqual(extractJsonArray('["books/foo.md"]'), ["books/foo.md"]);
  });

  it("parses empty array", () => {
    assert.deepEqual(extractJsonArray("[]"), []);
  });

  it("extracts array from markdown code fence", () => {
    const text = '```json\n["books/foo.md"]\n```';
    assert.deepEqual(extractJsonArray(text), ["books/foo.md"]);
  });

  it("extracts array when trailing text follows", () => {
    const text = '["books/foo.md"]\nThis is some explanation text.';
    assert.deepEqual(extractJsonArray(text), ["books/foo.md"]);
  });

  it("extracts array when preceded by text", () => {
    const text = 'Here are the books:\n["books/foo.md", "books/bar.md"]';
    assert.deepEqual(extractJsonArray(text), ["books/foo.md", "books/bar.md"]);
  });

  it("throws for text with no JSON array", () => {
    assert.throws(() => extractJsonArray("No JSON here at all"), /No JSON array found/);
  });

  it("handles code fence without json tag", () => {
    const text = '```\n["books/foo.md"]\n```';
    assert.deepEqual(extractJsonArray(text), ["books/foo.md"]);
  });
});

// --- isRateLimitError ---

describe("isRateLimitError", () => {
  it("detects 429 in message", () => {
    assert.ok(isRateLimitError({ message: "Error 429: quota exceeded" }));
  });

  it("detects RESOURCE_EXHAUSTED", () => {
    assert.ok(isRateLimitError({ message: "RESOURCE_EXHAUSTED: too many requests" }));
  });

  it("detects quota keyword", () => {
    assert.ok(isRateLimitError({ message: "You exceeded your current quota" }));
  });

  it("returns false for non-rate-limit errors", () => {
    assert.ok(!isRateLimitError({ message: "Invalid API key" }));
  });

  it("returns false for null", () => {
    assert.ok(!isRateLimitError(null));
  });
});

// --- isDailyQuotaError ---

describe("isDailyQuotaError", () => {
  it("detects daily quota messages", () => {
    assert.ok(isDailyQuotaError({ message: "quota exceeded, daily limit reached" }));
  });

  it("detects PerDay quota messages", () => {
    assert.ok(isDailyQuotaError({ message: "quota: RequestsPerDay limit" }));
  });

  it("returns false for per-minute rate limits", () => {
    assert.ok(!isDailyQuotaError({ message: "429: too many requests per minute" }));
  });

  it("returns false for non-quota errors", () => {
    assert.ok(!isDailyQuotaError({ message: "Invalid API key" }));
  });
});

// --- parseRetryDelay ---

describe("parseRetryDelay", () => {
  it("parses 'retry in Ns' from message", () => {
    assert.equal(parseRetryDelay({ message: "Please retry in 14.473150856s." }), 14474);
  });

  it("parses retryDelay from message", () => {
    assert.equal(parseRetryDelay({ message: 'retryDelay: "30s"' }), 30000);
  });

  it("returns null for messages without retry delay", () => {
    assert.equal(parseRetryDelay({ message: "Some other error" }), null);
  });

  it("returns null for null input", () => {
    assert.equal(parseRetryDelay(null), null);
  });
});

// --- QuotaExhaustedError ---

describe("QuotaExhaustedError", () => {
  it("is an Error with correct name", () => {
    const err = new QuotaExhaustedError();
    assert.ok(err instanceof Error);
    assert.equal(err.name, "QuotaExhaustedError");
  });

  it("has default message", () => {
    const err = new QuotaExhaustedError();
    assert.equal(err.message, "Gemini API daily quota exhausted");
  });

  it("accepts custom message", () => {
    const err = new QuotaExhaustedError("custom");
    assert.equal(err.message, "custom");
  });
});

// --- updateFrontmatterFields ---

describe("updateFrontmatterFields", () => {
  const tmpDir = { path: "" };

  beforeEach(() => {
    tmpDir.path = fs.mkdtempSync(path.join(os.tmpdir(), "internal-linking-fields-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir.path, { recursive: true, force: true });
  });

  it("sets multiple fields in existing frontmatter", () => {
    const filePath = path.join(tmpDir.path, "test.md");
    fs.writeFileSync(filePath, "---\ntitle: Test\n---\nBody");

    updateFrontmatterFields(filePath, {
      link_analysis_model: "gemini-3.1-flash-lite-preview",
      link_analysis_time: "2026-03-22T00:00:00.000Z",
    });

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("link_analysis_model: gemini-3.1-flash-lite-preview"));
    assert.ok(content.includes("link_analysis_time: 2026-03-22T00:00:00.000Z"));
    assert.ok(content.includes("title: Test"));
  });

  it("updates existing fields", () => {
    const filePath = path.join(tmpDir.path, "test.md");
    fs.writeFileSync(filePath, "---\ntitle: Test\nlink_analysis_model: old-model\n---\nBody");

    updateFrontmatterFields(filePath, { link_analysis_model: "new-model" });

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("link_analysis_model: new-model"));
    assert.ok(!content.includes("old-model"));
  });

  it("creates frontmatter when none exists", () => {
    const filePath = path.join(tmpDir.path, "test.md");
    fs.writeFileSync(filePath, "Body only");

    updateFrontmatterFields(filePath, { link_analysis_model: "test-model" });

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.startsWith("---\nlink_analysis_model: test-model\n---\n"));
    assert.ok(content.includes("Body only"));
  });

  it("does nothing for non-existent files", () => {
    const filePath = path.join(tmpDir.path, "nonexistent.md");
    updateFrontmatterFields(filePath, { key: "value" });
    assert.ok(!fs.existsSync(filePath));
  });
});

// --- recordLinkAnalysis ---

describe("recordLinkAnalysis", () => {
  const tmpDir = { path: "" };

  beforeEach(() => {
    tmpDir.path = fs.mkdtempSync(path.join(os.tmpdir(), "internal-linking-record-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir.path, { recursive: true, force: true });
  });

  it("writes link_analysis_model and link_analysis_time", () => {
    const filePath = path.join(tmpDir.path, "test.md");
    fs.writeFileSync(filePath, "---\ntitle: Test\n---\nBody");

    recordLinkAnalysis(filePath, "gemini-3.1-flash-lite-preview", "2026-03-22T00:00:00.000Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("link_analysis_model: gemini-3.1-flash-lite-preview"));
    assert.ok(content.includes("link_analysis_time: 2026-03-22T00:00:00.000Z"));
  });

  it("clears force_analyze_links after recording analysis", () => {
    const filePath = path.join(tmpDir.path, "test.md");
    fs.writeFileSync(filePath, "---\ntitle: Test\nforce_analyze_links: true\n---\nBody");

    recordLinkAnalysis(filePath, "gemini-3.1-flash-lite-preview", "2026-03-22T00:00:00.000Z");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("force_analyze_links: false"));
    assert.ok(content.includes("link_analysis_model: gemini-3.1-flash-lite-preview"));
  });
});

// --- alreadyAnalyzed ---

describe("alreadyAnalyzed", () => {
  it("returns true when link_analysis_model is present", () => {
    const content = "---\ntitle: Test\nlink_analysis_model: gemini-3.1-flash-lite-preview\n---\nBody";
    assert.ok(alreadyAnalyzed(content));
  });

  it("returns true even when model differs (model is informational only)", () => {
    const content = "---\ntitle: Test\nlink_analysis_model: old-model\n---\nBody";
    assert.ok(alreadyAnalyzed(content));
  });

  it("returns false when force_analyze_links is true", () => {
    const content = "---\ntitle: Test\nlink_analysis_model: gemini-3.1-flash-lite-preview\nforce_analyze_links: true\n---\nBody";
    assert.ok(!alreadyAnalyzed(content));
  });

  it("returns false when no link_analysis_model field", () => {
    const content = "---\ntitle: Test\n---\nBody";
    assert.ok(!alreadyAnalyzed(content));
  });

  it("returns false for content without frontmatter", () => {
    const content = "Body only";
    assert.ok(!alreadyAnalyzed(content));
  });
});
