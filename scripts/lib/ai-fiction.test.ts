/**
 * Tests for scripts/lib/ai-fiction.ts — AI Fiction generation.
 *
 * Covers pure functions (string manipulation) only.
 * Gemini API calls are not tested here.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  FICTION_SECTION_HEADER,
  stripForPrompt,
  reflectionNeedsFiction,
  buildFictionPrompt,
  parseFictionResponse,
  applyFiction,
  buildFictionSignature,
} from "./ai-fiction.ts";

// --- Test Content ---

const sampleReflection = [
  "---",
  "share: true",
  "title: 2026-03-23",
  "URL: https://bagrounds.org/reflections/2026-03-23",
  "---",
  "[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/2026-03-22|⏮️]]",
  "# 2026-03-23",
  "",
  "## [[books/index|📚 Books]]",
  "- [[books/the-goal|🏭 The Goal]]",
  "- ⏯️ Continuing [[books/thinking-fast-and-slow|🧠 Thinking, Fast and Slow]]",
  "",
  "## [[chickie-loo/index|🐔 Chickie Loo]]",
  "- [[chickie-loo/2026-03-23-post|🐔 A Day in the Coop]]",
  "",
  "## 📺 Videos",
  "- [[videos/some-video|📺 Great Video]]",
  "",
  "## 🦋 Bluesky",
  "> embed content here",
  "",
  "## 🐘 Mastodon",
  "> mastodon embed",
  "",
].join("\n");

const sampleReflectionWithFiction = [
  "---",
  "share: true",
  "title: 2026-03-23",
  "---",
  "# 2026-03-23",
  "",
  "## 📚 Books",
  "- [[books/the-goal|🏭 The Goal]]",
  "",
  "## 🤖🐲 AI Fiction",
  "",
  "🏭 The factory hummed with purpose. 🧠 A mind divided could not see the whole.",
  "",
  "## 🦋 Bluesky",
  "> embed",
  "",
].join("\n");

// --- Pure Function Tests ---

describe("FICTION_SECTION_HEADER", () => {
  it("uses correct emoji heading", () => {
    assert.equal(FICTION_SECTION_HEADER, "## 🤖🐲 AI Fiction");
  });
});

describe("stripForPrompt", () => {
  it("strips frontmatter from content", () => {
    const result = stripForPrompt(sampleReflection);
    assert.ok(!result.includes("share: true"));
    assert.ok(!result.includes("---"));
    assert.ok(!result.includes("URL:"));
  });

  it("strips embed sections", () => {
    const result = stripForPrompt(sampleReflection);
    assert.ok(!result.includes("Bluesky"));
    assert.ok(!result.includes("Mastodon"));
    assert.ok(!result.includes("embed content"));
  });

  it("preserves content sections", () => {
    const result = stripForPrompt(sampleReflection);
    assert.ok(result.includes("Books"));
    assert.ok(result.includes("The Goal"));
    assert.ok(result.includes("Chickie Loo"));
    assert.ok(result.includes("Videos"));
  });

  it("strips existing AI Fiction section", () => {
    const result = stripForPrompt(sampleReflectionWithFiction);
    assert.ok(!result.includes("AI Fiction"));
    assert.ok(!result.includes("factory hummed"));
  });

  it("strips Updates section", () => {
    const content = [
      "# 2026-03-23",
      "",
      "## 📚 Books",
      "- Book",
      "",
      "## 🔄 Updates",
      "",
      "- [[books/updated|Updated Book]]",
      "",
    ].join("\n");
    const result = stripForPrompt(content);
    assert.ok(!result.includes("Updates"));
    assert.ok(!result.includes("Updated Book"));
    assert.ok(result.includes("Books"));
  });

  it("handles content without frontmatter", () => {
    const content = "# Title\n\n## Section\n- Item\n";
    const result = stripForPrompt(content);
    assert.ok(result.includes("Title"));
    assert.ok(result.includes("Section"));
  });

  it("handles content with no embed sections", () => {
    const content = "---\ntitle: Test\n---\n# Title\n## Section\n- Item\n";
    const result = stripForPrompt(content);
    assert.ok(result.includes("Title"));
    assert.ok(result.includes("Item"));
  });

  it("returns trimmed result", () => {
    const content = "---\ntitle: Test\n---\n\n# Title\n\n";
    const result = stripForPrompt(content);
    assert.ok(!result.endsWith("\n\n"));
  });
});

describe("reflectionNeedsFiction", () => {
  it("returns true when no fiction section exists", () => {
    assert.equal(reflectionNeedsFiction(sampleReflection), true);
  });

  it("returns false when fiction section exists", () => {
    assert.equal(reflectionNeedsFiction(sampleReflectionWithFiction), false);
  });

  it("returns true for empty content", () => {
    assert.equal(reflectionNeedsFiction(""), true);
  });

  it("detects exact header match", () => {
    const content = "# 2026-03-23\n\n## 🤖🐲 AI Fiction\n\nSome fiction.\n";
    assert.equal(reflectionNeedsFiction(content), false);
  });
});

describe("buildFictionPrompt", () => {
  it("returns system and user prompts", () => {
    const { system, user } = buildFictionPrompt("## Books\n- The Goal\n");
    assert.ok(system.includes("fiction writer"));
    assert.ok(system.includes("emoji"));
    assert.ok(system.includes("quotation marks"));
    assert.ok(system.includes("100 words"));
    assert.ok(user.includes("The Goal"));
  });

  it("includes the stripped content in user prompt", () => {
    const content = "## Videos\n- Great Documentary\n- Another Video\n";
    const { user } = buildFictionPrompt(content);
    assert.ok(user.includes("Great Documentary"));
    assert.ok(user.includes("Another Video"));
  });

  it("system prompt forbids quotation marks", () => {
    const { system } = buildFictionPrompt("content");
    assert.ok(system.includes("NEVER use quotation marks"));
  });

  it("system prompt requires emoji-started sentences", () => {
    const { system } = buildFictionPrompt("content");
    assert.ok(system.includes("MUST begin with an emoji"));
  });
});

describe("parseFictionResponse", () => {
  it("returns clean text", () => {
    const result = parseFictionResponse("🏭 The factory hummed. 🧠 A mind divided.");
    assert.equal(result, "🏭 The factory hummed. 🧠 A mind divided.");
  });

  it("strips code fences", () => {
    const result = parseFictionResponse("```markdown\n🏭 Fiction text.\n```");
    assert.equal(result, "🏭 Fiction text.");
  });

  it("strips quotation marks", () => {
    const result = parseFictionResponse('🏭 The "factory" hummed with \'purpose\'.');
    assert.equal(result, "🏭 The factory hummed with purpose.");
  });

  it("strips AI Fiction heading if included", () => {
    const result = parseFictionResponse("## 🤖🐲 AI Fiction\n\n🏭 Fiction text.");
    assert.equal(result, "🏭 Fiction text.");
  });

  it("strips curly quotes", () => {
    const result = parseFictionResponse("🏭 The \u201Cfactory\u201D hummed with \u2018purpose\u2019.");
    assert.equal(result, "🏭 The factory hummed with purpose.");
  });

  it("strips backticks", () => {
    const result = parseFictionResponse("🏭 The `factory` hummed.");
    assert.equal(result, "🏭 The factory hummed.");
  });

  it("trims whitespace", () => {
    const result = parseFictionResponse("  🏭 Fiction text.  \n\n  ");
    assert.equal(result, "🏭 Fiction text.");
  });
});

describe("buildFictionSignature", () => {
  it("formats model attribution line", () => {
    const sig = buildFictionSignature("gemini-2.5-flash");
    assert.equal(sig, "\n\n✍️ Written by gemini-2.5-flash");
  });

  it("handles any model name", () => {
    const sig = buildFictionSignature("gemini-3.1-flash-lite-preview");
    assert.ok(sig.includes("gemini-3.1-flash-lite-preview"));
  });
});

describe("applyFiction", () => {
  it("inserts fiction before embed sections", () => {
    const updated = applyFiction(sampleReflection, "🏭 The factory hummed.");
    const fictionIdx = updated.indexOf(FICTION_SECTION_HEADER);
    const embedIdx = updated.indexOf("## 🦋 Bluesky");
    assert.ok(fictionIdx >= 0, "fiction section should be added");
    assert.ok(embedIdx >= 0, "embed section should still exist");
    assert.ok(fictionIdx < embedIdx, "fiction should be before embed sections");
  });

  it("inserts fiction at end when no embed sections", () => {
    const content = "# 2026-03-23\n\n## 📚 Books\n- Book\n";
    const updated = applyFiction(content, "🏭 The factory hummed.");
    assert.ok(updated.includes(FICTION_SECTION_HEADER));
    assert.ok(updated.includes("🏭 The factory hummed."));
    assert.ok(updated.endsWith("\n"));
  });

  it("inserts fiction before Updates section", () => {
    const content = [
      "# 2026-03-23",
      "",
      "## 📚 Books",
      "- Book",
      "",
      "## 🔄 Updates",
      "",
      "- [[books/updated|Updated Book]]",
      "",
    ].join("\n");
    const updated = applyFiction(content, "🏭 The factory hummed.");
    const fictionIdx = updated.indexOf(FICTION_SECTION_HEADER);
    const updatesIdx = updated.indexOf("## 🔄 Updates");
    assert.ok(fictionIdx < updatesIdx, "fiction should be before Updates section");
  });

  it("preserves all existing content", () => {
    const updated = applyFiction(sampleReflection, "🏭 Fiction.");
    assert.ok(updated.includes("The Goal"));
    assert.ok(updated.includes("Chickie Loo"));
    assert.ok(updated.includes("Bluesky"));
    assert.ok(updated.includes("Mastodon"));
  });

  it("includes the fiction text in the section", () => {
    const fiction = "🏭 The factory hummed. 🧠 A mind divided could see the whole.";
    const updated = applyFiction(sampleReflection, fiction);
    assert.ok(updated.includes(fiction));
  });

  it("adds blank line between header and fiction", () => {
    const updated = applyFiction("# Title\n", "🏭 Fiction.");
    const lines = updated.split("\n");
    const headerIdx = lines.indexOf(FICTION_SECTION_HEADER);
    assert.ok(headerIdx >= 0);
    assert.equal(lines[headerIdx + 1], "");
    assert.equal(lines[headerIdx + 2], "🏭 Fiction.");
  });

  it("includes model signature when model is provided", () => {
    const updated = applyFiction("# Title\n", "🏭 Fiction.", "gemini-2.5-flash");
    assert.ok(updated.includes("✍️ Written by gemini-2.5-flash"));
  });

  it("omits model signature when model is not provided", () => {
    const updated = applyFiction("# Title\n", "🏭 Fiction.");
    assert.ok(!updated.includes("✍️ Written by"));
  });

  it("places signature after fiction text", () => {
    const updated = applyFiction("# Title\n", "🏭 Fiction.", "gemini-2.5-flash");
    const fictionIdx = updated.indexOf("🏭 Fiction.");
    const signatureIdx = updated.indexOf("✍️ Written by");
    assert.ok(signatureIdx > fictionIdx, "signature should be after fiction text");
  });
});

// --- Integration Tests ---

describe("AI Fiction integration", () => {
  it("needsFiction → applyFiction → no longer needsFiction", () => {
    assert.equal(reflectionNeedsFiction(sampleReflection), true);
    const updated = applyFiction(sampleReflection, "🏭 Fiction text.");
    assert.equal(reflectionNeedsFiction(updated), false);
  });

  it("stripForPrompt excludes fiction from already-applied content", () => {
    const updated = applyFiction(sampleReflection, "🏭 Fiction text.");
    const stripped = stripForPrompt(updated);
    assert.ok(!stripped.includes("Fiction text"));
    assert.ok(stripped.includes("The Goal"));
  });

  it("full pipeline: strip → build prompt → apply", () => {
    const stripped = stripForPrompt(sampleReflection);
    const { system, user } = buildFictionPrompt(stripped);
    assert.ok(system.length > 0);
    assert.ok(user.includes("The Goal"));

    const fiction = parseFictionResponse("🏭 The gears turned. 🧠 Purpose emerged.");
    const updated = applyFiction(sampleReflection, fiction);
    assert.ok(updated.includes(FICTION_SECTION_HEADER));
    assert.ok(updated.includes("🏭 The gears turned."));
    assert.equal(reflectionNeedsFiction(updated), false);
  });
});
