/**
 * Tests for scripts/lib/prompts.ts — Social media post prompts.
 *
 * Verifies that prompt builders produce well-formed prompts for both
 * tags and questions, that the post assembler deterministically
 * constructs the final post, and that supporting utilities work correctly.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  buildTagsPrompt,
  buildQuestionPrompt,
  assemblePost,
  parseQuestionAndTags,
  AI_QUESTION_PREFIX,
  calculateQuestionBudget,
  stripSubtitle,
  buildShortenQuestionPrompt,
} from "./prompts.ts";
import type { PromptPair } from "./prompts.ts";
import type { ReflectionData } from "./types.ts";

// --- Test Fixtures ---

const testReflection: ReflectionData = {
  date: "2026-03-10",
  title: "2026-03-10 | 🧪 Test Reflection 📚",
  url: "https://bagrounds.org/reflections/2026-03-10",
  body: "Today I explored A/B testing for social media posts. Books read: Thinking Fast and Slow. Videos watched: a talk on experimental design.",
  filePath: "/vault/reflections/2026-03-10.md",
  hasTweetSection: false,
  hasBlueskySection: false,
  hasMastodonSection: false,
};

// --- buildTagsPrompt ---

describe("buildTagsPrompt", () => {
  it("returns a valid prompt pair", () => {
    const prompt = buildTagsPrompt(testReflection);
    assert.ok(prompt.system.length > 0, "system prompt should not be empty");
    assert.ok(prompt.user.length > 0, "user prompt should not be empty");
  });

  it("asks for ONLY topic tags (not full post)", () => {
    const prompt = buildTagsPrompt(testReflection);
    assert.ok(
      prompt.system.includes("Return ONLY"),
      "should ask for only creative parts",
    );
    assert.ok(
      prompt.system.includes("emoji topic tags"),
      "should ask for topic tags",
    );
  });

  it("does not ask the model to generate the title", () => {
    const prompt = buildTagsPrompt(testReflection);
    assert.ok(!prompt.system.includes("first line MUST be"), "should not ask model for title");
  });

  it("does not ask the model to generate the URL", () => {
    const prompt = buildTagsPrompt(testReflection);
    assert.ok(!prompt.system.includes("last line should be the URL"), "should not ask model for URL");
  });

  it("includes content body in user prompt", () => {
    const prompt = buildTagsPrompt(testReflection);
    assert.ok(prompt.user.includes("A/B testing"), "user should include body content");
  });

  it("passes full body content without truncation", () => {
    const longReflection: ReflectionData = {
      ...testReflection,
      body: "x".repeat(3000),
    };
    const prompt = buildTagsPrompt(longReflection);
    const bodyInPrompt = prompt.user.split("Content:\n")[1] ?? "";
    assert.equal(bodyInPrompt.length, 3000, "body should be passed in full");
  });

  it("includes topic tag formatting instructions", () => {
    const prompt = buildTagsPrompt(testReflection);
    assert.ok(
      prompt.system.includes("emoji followed by a space and a short topic label"),
      "should include topic tag formatting",
    );
  });

  it("warns against bare emojis", () => {
    const prompt = buildTagsPrompt(testReflection);
    assert.ok(
      prompt.system.includes("Do NOT output bare emojis"),
      "should warn against bare emoji output",
    );
  });

  it("is a pure function — same input produces same output", () => {
    const prompt1 = buildTagsPrompt(testReflection);
    const prompt2 = buildTagsPrompt(testReflection);
    assert.deepEqual(prompt1, prompt2);
  });
});

// --- buildQuestionPrompt ---

describe("buildQuestionPrompt", () => {
  it("returns a valid prompt pair", () => {
    const prompt = buildQuestionPrompt(testReflection);
    assert.ok(prompt.system.length > 0, "system prompt should not be empty");
    assert.ok(prompt.user.length > 0, "user prompt should not be empty");
  });

  it("asks for question ONLY (no tags)", () => {
    const prompt = buildQuestionPrompt(testReflection);
    assert.ok(
      prompt.system.includes("Return ONLY a single line"),
      "should ask for only the question",
    );
    assert.ok(
      !prompt.system.includes("EMOJI TOPIC TAGS"),
      "should NOT ask for topic tags",
    );
  });

  it("does not ask the model to generate the title", () => {
    const prompt = buildQuestionPrompt(testReflection);
    assert.ok(!prompt.system.includes("first line MUST be"), "should not ask model for title");
  });

  it("does not ask the model to generate the URL", () => {
    const prompt = buildQuestionPrompt(testReflection);
    assert.ok(!prompt.system.includes("last line must be the URL"), "should not ask model for URL");
  });

  it("includes content body in user prompt", () => {
    const prompt = buildQuestionPrompt(testReflection);
    assert.ok(prompt.user.includes("A/B testing"), "user should include body content");
  });

  it("passes full body content without truncation", () => {
    const longReflection: ReflectionData = {
      ...testReflection,
      body: "y".repeat(3000),
    };
    const prompt = buildQuestionPrompt(longReflection);
    const bodyInPrompt = prompt.user.split("Content:\n")[1] ?? "";
    assert.equal(bodyInPrompt.length, 3000, "body should be passed in full");
  });

  it("instructs 2nd person and concision", () => {
    const prompt = buildQuestionPrompt(testReflection);
    assert.ok(prompt.system.includes("2nd person"), "should instruct 2nd person");
    assert.ok(
      prompt.system.includes("concis") || prompt.system.includes("Minimize word count"),
      "should instruct concision",
    );
  });

  it("does NOT include topic tag formatting (tags use a separate prompt)", () => {
    const prompt = buildQuestionPrompt(testReflection);
    assert.ok(
      !prompt.system.includes("emoji followed by a space and a short topic label"),
      "should NOT include topic tag formatting",
    );
  });

  it("produces a different system prompt than tags prompt", () => {
    const tagsPrompt = buildTagsPrompt(testReflection);
    const questionPrompt = buildQuestionPrompt(testReflection);
    assert.notEqual(tagsPrompt.system, questionPrompt.system, "prompts should differ");
  });

  it("includes max character count", () => {
    const prompt = buildQuestionPrompt(testReflection);
    assert.ok(prompt.system.includes("at most"), "should include character limit");
    assert.ok(prompt.system.includes("characters"), "should mention characters");
  });
});

// --- assemblePost ---

describe("assemblePost", () => {
  it("assembles title + question + tags + URL", () => {
    const modelOutput = "🤔 Ever trusted a machine more than your gut?\n📚 Sci-Fi | 🤖 AGI";
    const post = assemblePost(modelOutput, testReflection);
    assert.ok(post.startsWith(testReflection.title), "should start with title");
    assert.ok(post.includes("#AI Q:"), "should include AI question prefix");
    assert.ok(post.includes("Ever trusted a machine"), "should include question");
    assert.ok(post.includes("📚 Sci-Fi | 🤖 AGI"), "should include tags");
    assert.ok(post.endsWith(testReflection.url), "should end with URL");
  });

  it("has correct line structure", () => {
    const modelOutput = "🤔 Question here?\n📚 Books | 🤖 AI";
    const post = assemblePost(modelOutput, testReflection);
    const lines = post.split("\n");
    assert.equal(lines[0], testReflection.title, "line 0 = title");
    assert.equal(lines[1], "", "line 1 = blank");
    assert.equal(lines[2], `${AI_QUESTION_PREFIX}🤔 Question here?`, "line 2 = question with prefix");
    assert.equal(lines[3], "", "line 3 = blank");
    assert.equal(lines[4], "📚 Books | 🤖 AI", "line 4 = tags");
    assert.equal(lines[5], testReflection.url, "line 5 = URL");
  });

  it("title and URL are NEVER from model output", () => {
    const post = assemblePost("🤔 Question?\n📚 Tags", testReflection);
    assert.ok(post.includes(testReflection.title), "title comes from reflection, not model");
    assert.ok(post.includes(testReflection.url), "URL comes from reflection, not model");
  });

  it("is a pure function", () => {
    const a1 = assemblePost("🤔 Q?\n📚 Books", testReflection);
    const a2 = assemblePost("🤔 Q?\n📚 Books", testReflection);
    assert.equal(a1, a2, "same input should produce same output");
  });

  it("handles model output with extra blank lines", () => {
    const modelOutput = "\n🤔 Question here?\n\n📚 Books | 🤖 AI\n\n";
    const post = assemblePost(modelOutput, testReflection);
    assert.ok(post.includes(`${AI_QUESTION_PREFIX}🤔 Question here?`), "should parse question");
    assert.ok(post.includes("📚 Books | 🤖 AI"), "should parse tags");
  });
});

// --- parseQuestionAndTags ---

describe("parseQuestionAndTags", () => {
  it("parses two-line output", () => {
    const { question, tags } = parseQuestionAndTags("🤔 Question?\n📚 Books | 🤖 AI");
    assert.equal(question, "🤔 Question?");
    assert.equal(tags, "📚 Books | 🤖 AI");
  });

  it("handles extra blank lines", () => {
    const { question, tags } = parseQuestionAndTags("\n🤔 Question?\n\n📚 Books\n");
    assert.equal(question, "🤔 Question?");
    assert.equal(tags, "📚 Books");
  });

  it("handles single line (question only)", () => {
    const { question, tags } = parseQuestionAndTags("🤔 Question?");
    assert.equal(question, "🤔 Question?");
    assert.equal(tags, "");
  });

  it("handles empty output", () => {
    const { question, tags } = parseQuestionAndTags("");
    assert.equal(question, "");
    assert.equal(tags, "");
  });

  it("trims whitespace from both parts", () => {
    const { question, tags } = parseQuestionAndTags("  🤔 Question?  \n  📚 Books  ");
    assert.equal(question, "🤔 Question?");
    assert.equal(tags, "📚 Books");
  });
});

// --- calculateQuestionBudget ---

describe("calculateQuestionBudget", () => {
  it("returns a positive budget for typical reflection", () => {
    const budget = calculateQuestionBudget(testReflection);
    assert.ok(budget > 0, `budget should be positive, got ${budget}`);
  });

  it("returns at least 30 characters", () => {
    const budget = calculateQuestionBudget(testReflection);
    assert.ok(budget >= 30, `budget should be >= 30, got ${budget}`);
  });

  it("returns smaller budget for longer titles", () => {
    const longTitleReflection: ReflectionData = {
      ...testReflection,
      title: "x".repeat(200),
    };
    const shortBudget = calculateQuestionBudget(longTitleReflection);
    const normalBudget = calculateQuestionBudget(testReflection);
    assert.ok(shortBudget < normalBudget, "longer title should reduce budget");
  });

  it("returns smaller budget for longer URLs", () => {
    const longUrlReflection: ReflectionData = {
      ...testReflection,
      url: "https://bagrounds.org/" + "x".repeat(150),
    };
    const shortBudget = calculateQuestionBudget(longUrlReflection);
    const normalBudget = calculateQuestionBudget(testReflection);
    assert.ok(shortBudget < normalBudget, "longer URL should reduce budget");
  });

  it("never returns less than 30", () => {
    const hugeReflection: ReflectionData = {
      ...testReflection,
      title: "x".repeat(300),
      url: "https://bagrounds.org/" + "y".repeat(300),
    };
    const budget = calculateQuestionBudget(hugeReflection);
    assert.equal(budget, 30, "should clamp to minimum 30");
  });
});

// --- stripSubtitle ---

describe("stripSubtitle", () => {
  it("strips subtitle after colon", () => {
    assert.equal(
      stripSubtitle("Prediction Machines: The Simple Economics of AI"),
      "Prediction Machines",
    );
  });

  it("returns original title if no colon", () => {
    assert.equal(stripSubtitle("Just a Title"), "Just a Title");
  });

  it("strips at first colon only", () => {
    assert.equal(
      stripSubtitle("Part 1: Section A: Detail"),
      "Part 1",
    );
  });

  it("returns original title if colon is at start", () => {
    assert.equal(stripSubtitle(": Empty Before"), ": Empty Before");
  });

  it("trims whitespace from shortened title", () => {
    assert.equal(
      stripSubtitle("Title With Space : Subtitle"),
      "Title With Space",
    );
  });
});

// --- buildShortenQuestionPrompt ---

describe("buildShortenQuestionPrompt", () => {
  it("returns a valid prompt pair", () => {
    const prompt = buildShortenQuestionPrompt("🤔 Some long question?", 10);
    assert.ok(prompt.system.length > 0, "system prompt should not be empty");
    assert.ok(prompt.user.length > 0, "user prompt should not be empty");
  });

  it("includes the overage in the user prompt", () => {
    const prompt = buildShortenQuestionPrompt("🤔 Some long question?", 15);
    assert.ok(prompt.user.includes("15"), "should include the overage");
  });

  it("includes target length in the user prompt", () => {
    const question = "🤔 Some long question?";
    const prompt = buildShortenQuestionPrompt(question, 10);
    assert.ok(
      prompt.user.includes(`${question.length - 10}`),
      "should include target length",
    );
  });

  it("instructs to keep the question mark", () => {
    const prompt = buildShortenQuestionPrompt("🤔 Q?", 2);
    assert.ok(prompt.system.includes("question mark"), "should mention question mark");
  });
});

// --- AI_QUESTION_PREFIX ---

describe("AI_QUESTION_PREFIX", () => {
  it("is shorter than 25 chars for character savings", () => {
    assert.ok(AI_QUESTION_PREFIX.length < 25, `prefix should be short, got ${AI_QUESTION_PREFIX.length}`);
  });

  it("starts with #AI", () => {
    assert.ok(AI_QUESTION_PREFIX.startsWith("#AI"), "should start with #AI");
  });
});
