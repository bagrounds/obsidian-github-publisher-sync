import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  reflectionNeedsTitle,
  buildReflectionTitlePrompt,
  parseReflectionTitle,
  applyReflectionTitle,
} from "./reflection-title.ts";

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const SAMPLE_REFLECTION = `---
share: true
aliases:
  - 2026-03-24
title: 2026-03-24
URL: https://bagrounds.org/reflections/2026-03-24
Author: "[[bryan-grounds]]"
tags:
---
[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/2026-03-23|⏮️]]
# 2026-03-24
![reflections-2026-03-24](../reflections-2026-03-24.jpg)

## [[chickie-loo/index|🐔 Chickie Loo]]
- [[chickie-loo/2026-03-24-finding-peace|🌌 Finding Peace in the Practical Rhythms of the Ranch]]

## [[auto-blog-zero/index|🤖 Auto Blog Zero]]
- [[auto-blog-zero/2026-03-24-the-eleventh-hour|🤖 The Eleventh Hour: Witnessing the Architecture of Survival]]

## [[books/index|📚 Books]]
- ⏯️ Continuing [[books/fugitive-telemetry|🕵️ Fugitive Telemetry]]
`;

const TITLED_REFLECTION = `---
share: true
aliases:
  - 2026-03-23 | 🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺
title: 2026-03-23 | 🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺
URL: https://bagrounds.org/reflections/2026-03-23
Author: "[[bryan-grounds]]"
tags:
---
[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/2026-03-22|⏮️]]
# 2026-03-23 | 🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺
`;

const RECENT_TITLES = [
  "🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺",
  "🕷️⏳ Children 🧠 Memory 🐔 Heavy 💔 Stewardship 📚🐔🤖📄📰",
  "🤖 Synthetic 🧠 Intelligence 💭 Thinks 🔍 about 🧬 Meaning 📚🐔🤖📺",
  "🧖🏼‍♀️ Sauna 🎣 Bass 🤖 Autonomy 📖 Book 📚🐔🤖📺",
  "🧠 Evolution, 🏰 Empire, and the 🎷 Symphony of 🐔 Chickie 🎵 Loo 📚🐔🤖📺",
] as const;

// ---------------------------------------------------------------------------
// reflectionNeedsTitle
// ---------------------------------------------------------------------------

describe("reflectionNeedsTitle", () => {
  it("returns true when title is just the date", () => {
    assert.equal(reflectionNeedsTitle(SAMPLE_REFLECTION, "2026-03-24"), true);
  });

  it("returns false when title already has creative text", () => {
    assert.equal(reflectionNeedsTitle(TITLED_REFLECTION, "2026-03-23"), false);
  });

  it("returns true when there is no title field", () => {
    const noTitle = "---\nshare: true\n---\n# 2026-01-01\n";
    assert.equal(reflectionNeedsTitle(noTitle, "2026-01-01"), true);
  });

  it("returns true when title matches date with extra spaces", () => {
    const spacedTitle = "---\ntitle:  2026-01-01  \n---\n# 2026-01-01\n";
    assert.equal(reflectionNeedsTitle(spacedTitle, "2026-01-01"), true);
  });

  it("returns false for a different date that happens to match the title", () => {
    assert.equal(reflectionNeedsTitle(SAMPLE_REFLECTION, "2026-03-25"), false);
  });

  // Property: any content with `title: DATE | ...` is considered titled
  ["A", "🎉 Party", "test title 📚"].forEach((suffix) => {
    it(`returns false for title '2026-01-01 | ${suffix}'`, () => {
      const content = `---\ntitle: 2026-01-01 | ${suffix}\n---\n`;
      assert.equal(reflectionNeedsTitle(content, "2026-01-01"), false);
    });
  });
});

// ---------------------------------------------------------------------------
// buildReflectionTitlePrompt
// ---------------------------------------------------------------------------

describe("buildReflectionTitlePrompt", () => {
  it("returns system and user prompts", () => {
    const prompt = buildReflectionTitlePrompt(SAMPLE_REFLECTION, RECENT_TITLES);
    assert.ok(prompt.system.length > 0);
    assert.ok(prompt.user.length > 0);
  });

  it("includes recent titles in the system prompt", () => {
    const prompt = buildReflectionTitlePrompt(SAMPLE_REFLECTION, RECENT_TITLES);
    RECENT_TITLES.forEach((title) => {
      assert.ok(
        prompt.system.includes(title),
        `System prompt should include example: ${title}`,
      );
    });
  });

  it("includes note content in the user prompt", () => {
    const prompt = buildReflectionTitlePrompt(SAMPLE_REFLECTION, RECENT_TITLES);
    assert.ok(prompt.user.includes("Chickie Loo"));
    assert.ok(prompt.user.includes("Fugitive Telemetry"));
  });

  it("mentions category emojis in the system prompt", () => {
    const prompt = buildReflectionTitlePrompt(SAMPLE_REFLECTION, RECENT_TITLES);
    assert.ok(prompt.system.includes("📚"));
    assert.ok(prompt.system.includes("🐔"));
    assert.ok(prompt.system.includes("🤖"));
  });

  it("instructs single-line output", () => {
    const prompt = buildReflectionTitlePrompt(SAMPLE_REFLECTION, RECENT_TITLES);
    assert.ok(prompt.system.includes("single line"));
  });

  it("works with empty recent titles", () => {
    const prompt = buildReflectionTitlePrompt(SAMPLE_REFLECTION, []);
    assert.ok(prompt.system.length > 0);
    assert.ok(prompt.user.length > 0);
  });
});

// ---------------------------------------------------------------------------
// parseReflectionTitle
// ---------------------------------------------------------------------------

describe("parseReflectionTitle", () => {
  it("returns clean text from simple response", () => {
    assert.equal(
      parseReflectionTitle("🌌 Peace 🏗️ Survival 📚🐔🤖"),
      "🌌 Peace 🏗️ Survival 📚🐔🤖",
    );
  });

  it("strips code fences", () => {
    assert.equal(
      parseReflectionTitle("```markdown\n🌌 Peace 📚\n```"),
      "🌌 Peace 📚",
    );
  });

  it("strips surrounding quotes", () => {
    assert.equal(
      parseReflectionTitle('"🌌 Peace 📚"'),
      "🌌 Peace 📚",
    );
    assert.equal(
      parseReflectionTitle("'🌌 Peace 📚'"),
      "🌌 Peace 📚",
    );
  });

  it("strips date prefix if model includes it", () => {
    assert.equal(
      parseReflectionTitle("2026-03-24 | 🌌 Peace 📚"),
      "🌌 Peace 📚",
    );
  });

  it("takes only first line of multi-line response", () => {
    assert.equal(
      parseReflectionTitle("🌌 Peace 📚\nThis is an explanation"),
      "🌌 Peace 📚",
    );
  });

  it("trims whitespace", () => {
    assert.equal(
      parseReflectionTitle("  🌌 Peace 📚  "),
      "🌌 Peace 📚",
    );
  });

  // Property: parseReflectionTitle never returns empty for non-empty emoji input
  ["🎉", "🤖 AI", "📚🐔🤖"].forEach((input) => {
    it(`returns non-empty for emoji input '${input}'`, () => {
      assert.ok(parseReflectionTitle(input).length > 0);
    });
  });
});

// ---------------------------------------------------------------------------
// applyReflectionTitle
// ---------------------------------------------------------------------------

describe("applyReflectionTitle", () => {
  const creativeTitle = "🌌 Peace 🏗️ Survival 🕵️ Fugitive 📚🐔🤖";

  it("updates frontmatter title field", () => {
    const result = applyReflectionTitle(SAMPLE_REFLECTION, "2026-03-24", creativeTitle);
    assert.ok(result.includes("title: 2026-03-24 | 🌌 Peace"));
  });

  it("updates frontmatter aliases to match new title", () => {
    const result = applyReflectionTitle(SAMPLE_REFLECTION, "2026-03-24", creativeTitle);
    assert.ok(result.includes("2026-03-24 | 🌌 Peace"));
    // Verify it appears in the aliases section (YAML array)
    const aliasLine = result.split("\n").find((l) => l.includes("- 2026-03-24 |"));
    assert.ok(aliasLine, "Should have alias with creative title");
  });

  it("updates H1 heading", () => {
    const result = applyReflectionTitle(SAMPLE_REFLECTION, "2026-03-24", creativeTitle);
    assert.ok(result.includes("# 2026-03-24 | 🌌 Peace"));
  });

  it("preserves other content unchanged", () => {
    const result = applyReflectionTitle(SAMPLE_REFLECTION, "2026-03-24", creativeTitle);
    assert.ok(result.includes("Chickie Loo"));
    assert.ok(result.includes("Fugitive Telemetry"));
    assert.ok(result.includes("reflections-2026-03-24"));
  });

  it("preserves navigation links", () => {
    const result = applyReflectionTitle(SAMPLE_REFLECTION, "2026-03-24", creativeTitle);
    assert.ok(result.includes("[[index|Home]]"));
    assert.ok(result.includes("[[reflections/2026-03-23|⏮️]]"));
  });

  it("handles H1 with existing emoji prefix (🤖)", () => {
    const withEmoji = SAMPLE_REFLECTION.replace(
      "# 2026-03-24",
      "# 🤖 2026-03-24",
    );
    const result = applyReflectionTitle(withEmoji, "2026-03-24", creativeTitle);
    assert.ok(result.includes("# 2026-03-24 | 🌌 Peace"));
    // Should not contain the old 🤖 prefix
    assert.ok(!result.includes("# 🤖 2026-03-24"));
  });

  it("handles H1 that already has a title (replaces it)", () => {
    const withTitle = SAMPLE_REFLECTION.replace(
      "# 2026-03-24",
      "# 2026-03-24 | Old Title",
    );
    const result = applyReflectionTitle(withTitle, "2026-03-24", creativeTitle);
    assert.ok(result.includes("# 2026-03-24 | 🌌 Peace"));
    assert.ok(!result.includes("Old Title"));
  });

  // Property: applyReflectionTitle is idempotent on the title
  it("produces same result when applied twice", () => {
    const first = applyReflectionTitle(SAMPLE_REFLECTION, "2026-03-24", creativeTitle);
    const second = applyReflectionTitle(first, "2026-03-24", creativeTitle);
    assert.equal(first, second);
  });

  // Property: share, URL, Author fields preserved
  it("preserves share, URL, and Author frontmatter fields", () => {
    const result = applyReflectionTitle(SAMPLE_REFLECTION, "2026-03-24", creativeTitle);
    assert.ok(result.includes("share: true"));
    assert.ok(result.includes("https://bagrounds.org/reflections/2026-03-24"));
    assert.ok(result.includes("bryan-grounds"));
  });

  it("returns content unchanged when no frontmatter exists", () => {
    const noFrontmatter = "# 2026-03-24\nSome content\n";
    const result = applyReflectionTitle(noFrontmatter, "2026-03-24", creativeTitle);
    assert.ok(result.includes("# 2026-03-24 | 🌌 Peace"));
  });
});

// ---------------------------------------------------------------------------
// Integration: reflectionNeedsTitle + applyReflectionTitle
// ---------------------------------------------------------------------------

describe("integration: needsTitle → applyTitle → no longer needsTitle", () => {
  it("marks reflection as titled after applying a title", () => {
    assert.equal(reflectionNeedsTitle(SAMPLE_REFLECTION, "2026-03-24"), true);

    const titled = applyReflectionTitle(
      SAMPLE_REFLECTION,
      "2026-03-24",
      "🌌 Peace 📚🐔🤖",
    );

    assert.equal(reflectionNeedsTitle(titled, "2026-03-24"), false);
  });

  // Property: for any creative title, applying it makes needsTitle return false
  ["🎉 Fun", "🤖 AI 📚", "test 📺🐔"].forEach((title) => {
    it(`needsTitle returns false after applying '${title}'`, () => {
      const result = applyReflectionTitle(SAMPLE_REFLECTION, "2026-03-24", title);
      assert.equal(reflectionNeedsTitle(result, "2026-03-24"), false);
    });
  });
});
