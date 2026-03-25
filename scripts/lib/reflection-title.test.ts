import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  reflectionNeedsTitle,
  buildReflectionTitlePrompt,
  parseReflectionTitle,
  applyReflectionTitle,
  extractLinkedTitles,
  extractTrailingEmojis,
  extractHeadingEmojis,
  stripTitlePrefixes,
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
  "🫂 Tight 🏗️ Functional 🤖 Agentic 🗣️ Breathe 📚",
  "🧠 Evolution, 🏰 Empire, and the 🎷 Symphony of 🐔 Chickie 🎵 Loo 📚🐔🤖📺",
] as const;

// ---------------------------------------------------------------------------
// extractHeadingEmojis
// ---------------------------------------------------------------------------

describe("extractHeadingEmojis", () => {
  it("extracts emojis from wiki link heading", () => {
    assert.equal(extractHeadingEmojis("## [[chickie-loo/index|🐔 Chickie Loo]]"), "🐔");
  });

  it("extracts emojis from markdown link heading", () => {
    assert.equal(extractHeadingEmojis("## [📚 Books](../books/index.md)"), "📚");
  });

  it("extracts emojis from plain heading", () => {
    assert.equal(extractHeadingEmojis("## 🤖🐲 AI Fiction"), "🤖🐲");
  });

  it("returns empty for heading without emojis", () => {
    assert.equal(extractHeadingEmojis("## Plain Heading"), "");
  });
});

// ---------------------------------------------------------------------------
// extractTrailingEmojis
// ---------------------------------------------------------------------------

describe("extractTrailingEmojis", () => {
  it("extracts emojis from all section headings", () => {
    const result = extractTrailingEmojis(SAMPLE_REFLECTION);
    assert.ok(result.includes("🐔"));
    assert.ok(result.includes("🤖"));
    assert.ok(result.includes("📚"));
  });

  it("deduplicates section emojis", () => {
    const note = "## [[a|📚 Books]]\n## [[b|📚 More Books]]\n";
    const result = extractTrailingEmojis(note);
    assert.equal(result, "📚");
  });
});

// ---------------------------------------------------------------------------
// stripTitlePrefixes
// ---------------------------------------------------------------------------

describe("stripTitlePrefixes", () => {
  it("strips emoji prefix", () => {
    assert.equal(stripTitlePrefixes("🕵️ Fugitive Telemetry"), "Fugitive Telemetry");
  });

  it("strips date prefix", () => {
    assert.equal(
      stripTitlePrefixes("2026-03-23 | 🐔 A Gentle Afternoon"),
      "A Gentle Afternoon",
    );
  });

  it("strips date and emoji prefix", () => {
    assert.equal(
      stripTitlePrefixes("2026-03-23 | 🤖 The Eleventh Hour"),
      "The Eleventh Hour",
    );
  });

  it("returns plain text unchanged", () => {
    assert.equal(stripTitlePrefixes("Hold Me Tight"), "Hold Me Tight");
  });
});

// ---------------------------------------------------------------------------
// extractLinkedTitles
// ---------------------------------------------------------------------------

describe("extractLinkedTitles", () => {
  it("extracts wiki link titles from list items", () => {
    const titles = extractLinkedTitles(SAMPLE_REFLECTION);
    assert.ok(titles.some((t) => t.includes("Finding Peace")));
    assert.ok(titles.some((t) => t.includes("Eleventh Hour")));
    assert.ok(titles.some((t) => t.includes("Fugitive Telemetry")));
  });

  it("strips emoji prefixes from titles", () => {
    const titles = extractLinkedTitles(SAMPLE_REFLECTION);
    titles.forEach((t) => {
      assert.ok(!t.match(/^[\p{Emoji_Presentation}]/u), `Title should not start with emoji: ${t}`);
    });
  });

  it("extracts markdown link titles from list items", () => {
    const note = `---
title: test
---
## [📚 Books](../books/index.md)
- [⚡🔮🤖 Power and Prediction](../books/power-and-prediction.md)
- [🕵️ Fugitive Telemetry](../books/fugitive-telemetry.md)
`;
    const titles = extractLinkedTitles(note);
    assert.ok(titles.some((t) => t.includes("Power and Prediction")));
    assert.ok(titles.some((t) => t.includes("Fugitive Telemetry")));
  });

  it("does not extract from headings", () => {
    const note = `---
title: test
---
## [[books/index|📚 Books]]
No list items here
`;
    const titles = extractLinkedTitles(note);
    assert.equal(titles.length, 0);
  });

  it("strips date prefixes from blog post titles", () => {
    const note = `---
title: test
---
- [[chickie-loo/2026-03-23-test|2026-03-23 | 🐔 A Gentle Afternoon]]
`;
    const titles = extractLinkedTitles(note);
    assert.ok(titles.some((t) => t === "A Gentle Afternoon"));
  });
});

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
  const linkedTitles = [
    "Finding Peace in the Practical Rhythms of the Ranch",
    "The Eleventh Hour: Witnessing the Architecture of Survival",
    "Fugitive Telemetry",
  ];

  it("returns system and user prompts", () => {
    const prompt = buildReflectionTitlePrompt(linkedTitles, RECENT_TITLES);
    assert.ok(prompt.system.length > 0);
    assert.ok(prompt.user.length > 0);
  });

  it("includes recent titles in the system prompt", () => {
    const prompt = buildReflectionTitlePrompt(linkedTitles, RECENT_TITLES);
    RECENT_TITLES.forEach((title) => {
      assert.ok(
        prompt.system.includes(title),
        `System prompt should include example: ${title}`,
      );
    });
  });

  it("includes linked content titles in the user prompt", () => {
    const prompt = buildReflectionTitlePrompt(linkedTitles, RECENT_TITLES);
    assert.ok(prompt.user.includes("Finding Peace"));
    assert.ok(prompt.user.includes("Fugitive Telemetry"));
  });

  it("instructs single-line output", () => {
    const prompt = buildReflectionTitlePrompt(linkedTitles, RECENT_TITLES);
    assert.ok(prompt.system.includes("single line"));
  });

  it("instructs one word from each title", () => {
    const prompt = buildReflectionTitlePrompt(linkedTitles, RECENT_TITLES);
    assert.ok(prompt.system.includes("ONE interesting"));
    assert.ok(prompt.system.includes("one word from EACH"));
  });

  it("instructs NOT to include trailing emojis", () => {
    const prompt = buildReflectionTitlePrompt(linkedTitles, RECENT_TITLES);
    assert.ok(prompt.system.includes("Do NOT include any trailing category emojis"));
  });

  it("works with empty recent titles", () => {
    const prompt = buildReflectionTitlePrompt(linkedTitles, []);
    assert.ok(prompt.system.length > 0);
    assert.ok(prompt.user.length > 0);
  });

  it("numbers titles in user prompt", () => {
    const prompt = buildReflectionTitlePrompt(linkedTitles, RECENT_TITLES);
    assert.ok(prompt.user.includes("1. Finding Peace"));
    assert.ok(prompt.user.includes("3. Fugitive Telemetry"));
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
// Integration: needsTitle → applyTitle → no longer needsTitle
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
