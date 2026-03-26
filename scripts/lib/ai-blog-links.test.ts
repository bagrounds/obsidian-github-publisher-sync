/**
 * Tests for scripts/lib/ai-blog-links.ts — AI Blog navigation links.
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
  AI_BLOG_NAV_PREFIX,
  buildAiBlogBackLink,
  buildAiBlogForwardLink,
  buildNavLine,
  updateNavLinks,
  navLinksMatch,
  extractPostDate,
  readAiBlogPostFiles,
  ensureAllNavLinks,
  extractAiBlogTitle,
  buildReflectionLinks,
} from "./ai-blog-links.ts";

// --- Test Helpers ---

const makeTmpDir = (): string => fs.mkdtempSync(path.join(os.tmpdir(), "ai-blog-links-test-"));

const cleanTmpDir = (dir: string): void => fs.rmSync(dir, { recursive: true });

const makePost = (title: string, navLine: string = AI_BLOG_NAV_PREFIX): string =>
  `---\nshare: true\ndate: 2026-03-20\ntitle: "${title}"\n---\n${navLine}\n\n# ${title}\n\n🎯 Content here.\n`;

// --- Pure Function Tests ---

describe("AI_BLOG_NAV_PREFIX", () => {
  it("matches the expected breadcrumb format", () => {
    assert.equal(AI_BLOG_NAV_PREFIX, "[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]");
  });
});

describe("buildAiBlogBackLink", () => {
  it("builds back link from filename with .md extension", () => {
    assert.equal(
      buildAiBlogBackLink("2026-03-19-previous-post.md"),
      "[[ai-blog/2026-03-19-previous-post|⏮️]]",
    );
  });

  it("builds back link from filename without .md extension", () => {
    assert.equal(
      buildAiBlogBackLink("2026-03-19-previous-post"),
      "[[ai-blog/2026-03-19-previous-post|⏮️]]",
    );
  });
});

describe("buildAiBlogForwardLink", () => {
  it("builds forward link from filename with .md extension", () => {
    assert.equal(
      buildAiBlogForwardLink("2026-03-21-next-post.md"),
      "[[ai-blog/2026-03-21-next-post|⏭️]]",
    );
  });

  it("builds forward link from filename without .md extension", () => {
    assert.equal(
      buildAiBlogForwardLink("2026-03-21-next-post"),
      "[[ai-blog/2026-03-21-next-post|⏭️]]",
    );
  });
});

describe("buildNavLine", () => {
  it("returns prefix only when no prev/next", () => {
    assert.equal(buildNavLine(), AI_BLOG_NAV_PREFIX);
  });

  it("returns prefix only when both undefined", () => {
    assert.equal(buildNavLine(undefined, undefined), AI_BLOG_NAV_PREFIX);
  });

  it("includes back link only when prev provided", () => {
    const nav = buildNavLine("2026-03-19-prev.md", undefined);
    assert.equal(nav, `${AI_BLOG_NAV_PREFIX} | [[ai-blog/2026-03-19-prev|⏮️]]`);
  });

  it("includes forward link only when next provided", () => {
    const nav = buildNavLine(undefined, "2026-03-21-next.md");
    assert.equal(nav, `${AI_BLOG_NAV_PREFIX} | [[ai-blog/2026-03-21-next|⏭️]]`);
  });

  it("includes both links when both provided", () => {
    const nav = buildNavLine("2026-03-19-prev.md", "2026-03-21-next.md");
    assert.equal(
      nav,
      `${AI_BLOG_NAV_PREFIX} | [[ai-blog/2026-03-19-prev|⏮️]] [[ai-blog/2026-03-21-next|⏭️]]`,
    );
  });
});

describe("updateNavLinks", () => {
  it("adds nav links to a post with only the prefix", () => {
    const content = makePost("My Post");
    const updated = updateNavLinks(content, "2026-03-19-prev.md", "2026-03-21-next.md");
    assert.ok(updated.includes("[[ai-blog/2026-03-19-prev|⏮️]]"));
    assert.ok(updated.includes("[[ai-blog/2026-03-21-next|⏭️]]"));
  });

  it("returns unchanged content when no nav prefix found", () => {
    const content = "---\ntitle: test\n---\n# No nav line\n";
    const updated = updateNavLinks(content, "prev.md", "next.md");
    assert.equal(updated, content);
  });

  it("is idempotent — applying twice yields same result", () => {
    const content = makePost("My Post");
    const first = updateNavLinks(content, "2026-03-19-prev.md", "2026-03-21-next.md");
    const second = updateNavLinks(first, "2026-03-19-prev.md", "2026-03-21-next.md");
    assert.equal(first, second);
  });

  it("replaces existing nav links when neighbors change", () => {
    const withOldLinks = makePost("My Post", `${AI_BLOG_NAV_PREFIX} | [[ai-blog/2026-03-18-old|⏮️]]`);
    const updated = updateNavLinks(withOldLinks, "2026-03-19-new-prev.md", "2026-03-21-next.md");
    assert.ok(updated.includes("[[ai-blog/2026-03-19-new-prev|⏮️]]"));
    assert.ok(updated.includes("[[ai-blog/2026-03-21-next|⏭️]]"));
    assert.ok(!updated.includes("2026-03-18-old"));
  });

  it("handles first post (no prev)", () => {
    const content = makePost("First Post");
    const updated = updateNavLinks(content, undefined, "2026-03-21-next.md");
    assert.ok(!updated.includes("⏮️"));
    assert.ok(updated.includes("[[ai-blog/2026-03-21-next|⏭️]]"));
  });

  it("handles last post (no next)", () => {
    const content = makePost("Last Post");
    const updated = updateNavLinks(content, "2026-03-19-prev.md", undefined);
    assert.ok(updated.includes("[[ai-blog/2026-03-19-prev|⏮️]]"));
    assert.ok(!updated.includes("⏭️"));
  });

  it("removes nav links when transitioning from middle to only post", () => {
    const withLinks = makePost("Only Post", `${AI_BLOG_NAV_PREFIX} | [[ai-blog/prev|⏮️]] [[ai-blog/next|⏭️]]`);
    const updated = updateNavLinks(withLinks, undefined, undefined);
    assert.ok(!updated.includes("⏮️"));
    assert.ok(!updated.includes("⏭️"));
    assert.ok(updated.includes(AI_BLOG_NAV_PREFIX));
  });

  it("preserves all other content lines", () => {
    const content = makePost("My Post");
    const lines = content.split("\n");
    const updated = updateNavLinks(content, "prev.md", "next.md");
    const updatedLines = updated.split("\n");
    assert.equal(lines.length, updatedLines.length);
    lines.forEach((line, i) => {
      if (!line.startsWith(AI_BLOG_NAV_PREFIX)) {
        assert.equal(updatedLines[i], line, `Line ${i} should be preserved`);
      }
    });
  });
});

describe("navLinksMatch", () => {
  it("returns true when nav line matches expected", () => {
    const content = makePost("My Post", buildNavLine("prev.md", "next.md"));
    assert.equal(navLinksMatch(content, "prev.md", "next.md"), true);
  });

  it("returns false when nav line differs", () => {
    const content = makePost("My Post");
    assert.equal(navLinksMatch(content, "prev.md", "next.md"), false);
  });

  it("returns true for prefix-only when no prev/next", () => {
    const content = makePost("My Post");
    assert.equal(navLinksMatch(content, undefined, undefined), true);
  });
});

describe("extractPostDate", () => {
  it("extracts date from standard filename", () => {
    assert.equal(extractPostDate("2026-03-20-my-post.md"), "2026-03-20");
  });

  it("extracts date from filename without slug", () => {
    assert.equal(extractPostDate("2026-03-20.md"), "2026-03-20");
  });

  it("returns undefined for non-dated filename", () => {
    assert.equal(extractPostDate("index.md"), undefined);
  });

  it("returns undefined for empty string", () => {
    assert.equal(extractPostDate(""), undefined);
  });
});

// --- I/O Function Tests ---

describe("readAiBlogPostFiles", () => {
  it("returns empty array for non-existent directory", () => {
    assert.deepEqual(readAiBlogPostFiles("/tmp/nonexistent-ai-blog"), []);
  });

  it("returns sorted post filenames", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-post-b.md"), "content");
      fs.writeFileSync(path.join(tmpDir, "2026-03-19-post-a.md"), "content");
      fs.writeFileSync(path.join(tmpDir, "2026-03-21-post-c.md"), "content");
      const files = readAiBlogPostFiles(tmpDir);
      assert.deepEqual(files, [
        "2026-03-19-post-a.md",
        "2026-03-20-post-b.md",
        "2026-03-21-post-c.md",
      ]);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("excludes index.md and AGENTS.md", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "index.md"), "content");
      fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "content");
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-post.md"), "content");
      const files = readAiBlogPostFiles(tmpDir);
      assert.deepEqual(files, ["2026-03-20-post.md"]);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("excludes non-markdown files", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-post.md"), "content");
      fs.writeFileSync(path.join(tmpDir, "image.png"), "content");
      fs.writeFileSync(path.join(tmpDir, "notes.txt"), "content");
      const files = readAiBlogPostFiles(tmpDir);
      assert.deepEqual(files, ["2026-03-20-post.md"]);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });
});

describe("ensureAllNavLinks", () => {
  it("adds nav links to a single post (no prev/next)", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-only.md"), makePost("Only Post"));
      const results = ensureAllNavLinks(tmpDir);
      assert.equal(results.length, 1);
      assert.equal(results[0]!.modified, false);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("links two posts together", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-19-first.md"), makePost("First"));
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-second.md"), makePost("Second"));
      const results = ensureAllNavLinks(tmpDir);

      const modified = results.filter((r) => r.modified);
      assert.equal(modified.length, 2);

      const first = fs.readFileSync(path.join(tmpDir, "2026-03-19-first.md"), "utf-8");
      assert.ok(first.includes("[[ai-blog/2026-03-20-second|⏭️]]"), "first should link to second");
      assert.ok(!first.includes("⏮️"), "first should have no back link");

      const second = fs.readFileSync(path.join(tmpDir, "2026-03-20-second.md"), "utf-8");
      assert.ok(second.includes("[[ai-blog/2026-03-19-first|⏮️]]"), "second should link back to first");
      assert.ok(!second.includes("⏭️"), "second should have no forward link");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("links three posts in chain", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-18-a.md"), makePost("Post A"));
      fs.writeFileSync(path.join(tmpDir, "2026-03-19-b.md"), makePost("Post B"));
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-c.md"), makePost("Post C"));
      ensureAllNavLinks(tmpDir);

      const a = fs.readFileSync(path.join(tmpDir, "2026-03-18-a.md"), "utf-8");
      assert.ok(!a.includes("⏮️"), "A has no back link");
      assert.ok(a.includes("[[ai-blog/2026-03-19-b|⏭️]]"), "A links forward to B");

      const b = fs.readFileSync(path.join(tmpDir, "2026-03-19-b.md"), "utf-8");
      assert.ok(b.includes("[[ai-blog/2026-03-18-a|⏮️]]"), "B links back to A");
      assert.ok(b.includes("[[ai-blog/2026-03-20-c|⏭️]]"), "B links forward to C");

      const c = fs.readFileSync(path.join(tmpDir, "2026-03-20-c.md"), "utf-8");
      assert.ok(c.includes("[[ai-blog/2026-03-19-b|⏮️]]"), "C links back to B");
      assert.ok(!c.includes("⏭️"), "C has no forward link");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("is idempotent — second call reports no modifications", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-19-first.md"), makePost("First"));
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-second.md"), makePost("Second"));

      const first = ensureAllNavLinks(tmpDir);
      const modified1 = first.filter((r) => r.modified).length;
      assert.equal(modified1, 2);

      const second = ensureAllNavLinks(tmpDir);
      const modified2 = second.filter((r) => r.modified).length;
      assert.equal(modified2, 0, "second call should modify nothing");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("updates links when new post is added between existing", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-18-a.md"), makePost("A"));
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-c.md"), makePost("C"));
      ensureAllNavLinks(tmpDir);

      fs.writeFileSync(path.join(tmpDir, "2026-03-19-b.md"), makePost("B"));
      const results = ensureAllNavLinks(tmpDir);
      const modified = results.filter((r) => r.modified).map((r) => r.filename);
      assert.ok(modified.includes("2026-03-18-a.md"), "A needs new forward link to B");
      assert.ok(modified.includes("2026-03-19-b.md"), "B is new, needs both links");
      assert.ok(modified.includes("2026-03-20-c.md"), "C needs new back link to B");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns empty array for non-existent directory", () => {
    assert.deepEqual(ensureAllNavLinks("/tmp/nonexistent-ai-blog-dir"), []);
  });

  it("handles posts without nav prefix line gracefully", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-no-nav.md"), "---\ntitle: test\n---\n# No Nav\n");
      const results = ensureAllNavLinks(tmpDir);
      assert.equal(results.length, 1);
      assert.equal(results[0]!.modified, false);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });
});

describe("extractAiBlogTitle", () => {
  it("extracts title from frontmatter", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "post.md"), makePost("My Great Title"));
      assert.equal(extractAiBlogTitle(tmpDir, "post.md"), "My Great Title");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("falls back to filename without extension", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-my-post.md"), "# No frontmatter\n");
      assert.equal(extractAiBlogTitle(tmpDir, "2026-03-20-my-post.md"), "2026-03-20-my-post");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns filename for non-existent file", () => {
    assert.equal(extractAiBlogTitle("/tmp/nonexistent", "post.md"), "post");
  });
});

describe("buildReflectionLinks", () => {
  it("builds links for modified results only", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "2026-03-19-a.md"), makePost("Post A"));
      fs.writeFileSync(path.join(tmpDir, "2026-03-20-b.md"), makePost("Post B"));
      const results = [
        { filename: "2026-03-19-a.md", modified: true },
        { filename: "2026-03-20-b.md", modified: false },
      ];
      const links = buildReflectionLinks(tmpDir, results);
      assert.equal(links.length, 1);
      assert.equal(links[0]!.relativePath, "ai-blog/2026-03-19-a.md");
      assert.equal(links[0]!.title, "Post A");
      assert.equal(links[0]!.date, "2026-03-19");
    } finally {
      cleanTmpDir(tmpDir);
    }
  });

  it("returns empty array when nothing modified", () => {
    const links = buildReflectionLinks("/tmp", [
      { filename: "2026-03-20-post.md", modified: false },
    ]);
    assert.deepEqual(links, []);
  });

  it("skips files without parseable dates", () => {
    const tmpDir = makeTmpDir();
    try {
      fs.writeFileSync(path.join(tmpDir, "no-date.md"), makePost("No Date"));
      const links = buildReflectionLinks(tmpDir, [
        { filename: "no-date.md", modified: true },
      ]);
      assert.deepEqual(links, []);
    } finally {
      cleanTmpDir(tmpDir);
    }
  });
});
