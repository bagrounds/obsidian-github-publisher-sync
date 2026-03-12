/**
 * Tests for scripts/lib/prompts.ts — Versioned prompt variants.
 *
 * Verifies that prompt builders produce well-formed prompts for both
 * control (A) and treatment (B) variants, that post assemblers
 * deterministically construct the final post, and that the registry
 * covers all variant IDs.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  PROMPT_VARIANTS,
  VARIANT_CONFIGS,
  getPromptBuilder,
  getPostAssembler,
  buildPromptForVariant,
  assemblePostForVariant,
  parseVariantBOutput,
  AI_QUESTION_PREFIX,
  calculateQuestionBudget,
  stripSubtitle,
  buildShortenQuestionPrompt,
} from "./prompts.ts";
import type { PromptPair, PostAssembler } from "./prompts.ts";
import { VARIANT_IDS } from "./experiment.ts";
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

// --- VARIANT_CONFIGS registry ---

describe("VARIANT_CONFIGS", () => {
  it("has an entry for every VARIANT_ID", () => {
    for (const id of VARIANT_IDS) {
      assert.ok(VARIANT_CONFIGS[id], `Missing config for variant ${id}`);
    }
  });

  it("each entry has buildPrompt and assemblePost", () => {
    for (const id of VARIANT_IDS) {
      assert.equal(typeof VARIANT_CONFIGS[id].buildPrompt, "function");
      assert.equal(typeof VARIANT_CONFIGS[id].assemblePost, "function");
    }
  });
});

// --- PROMPT_VARIANTS legacy registry ---

describe("PROMPT_VARIANTS", () => {
  it("has an entry for every VARIANT_ID", () => {
    for (const id of VARIANT_IDS) {
      assert.ok(PROMPT_VARIANTS[id], `Missing prompt for variant ${id}`);
    }
  });

  it("maps to functions", () => {
    for (const id of VARIANT_IDS) {
      assert.equal(typeof PROMPT_VARIANTS[id], "function");
    }
  });
});

// --- getPromptBuilder / getPostAssembler ---

describe("getPromptBuilder", () => {
  it("returns a function for variant A", () => {
    assert.equal(typeof getPromptBuilder("A"), "function");
  });

  it("returns a function for variant B", () => {
    assert.equal(typeof getPromptBuilder("B"), "function");
  });
});

describe("getPostAssembler", () => {
  it("returns a function for variant A", () => {
    assert.equal(typeof getPostAssembler("A"), "function");
  });

  it("returns a function for variant B", () => {
    assert.equal(typeof getPostAssembler("B"), "function");
  });
});

// --- buildPromptForVariant ---

describe("buildPromptForVariant", () => {
  it("builds a valid prompt for variant A", () => {
    const prompt = buildPromptForVariant("A", testReflection);
    assert.ok(prompt.system.length > 0, "system prompt should not be empty");
    assert.ok(prompt.user.length > 0, "user prompt should not be empty");
  });

  it("builds a valid prompt for variant B", () => {
    const prompt = buildPromptForVariant("B", testReflection);
    assert.ok(prompt.system.length > 0, "system prompt should not be empty");
    assert.ok(prompt.user.length > 0, "user prompt should not be empty");
  });

  it("variant A prompt asks for ONLY topic tags (not full post)", () => {
    const prompt = buildPromptForVariant("A", testReflection);
    assert.ok(
      prompt.system.includes("Return ONLY"),
      "variant A should ask for only creative parts",
    );
    assert.ok(
      prompt.system.includes("emoji topic tags"),
      "variant A should ask for topic tags",
    );
  });

  it("variant B prompt asks for question ONLY (no tags)", () => {
    const prompt = buildPromptForVariant("B", testReflection);
    assert.ok(
      prompt.system.includes("Return ONLY a single line"),
      "variant B should ask for only the question",
    );
    assert.ok(
      !prompt.system.includes("EMOJI TOPIC TAGS"),
      "variant B should NOT ask for topic tags",
    );
  });

  it("neither prompt asks the model to generate the title", () => {
    const promptA = buildPromptForVariant("A", testReflection);
    const promptB = buildPromptForVariant("B", testReflection);
    // Neither system prompt should tell the model to include the title in output
    assert.ok(!promptA.system.includes("first line MUST be"), "A should not ask model for title");
    assert.ok(!promptB.system.includes("first line MUST be"), "B should not ask model for title");
  });

  it("neither prompt asks the model to generate the URL", () => {
    const promptA = buildPromptForVariant("A", testReflection);
    const promptB = buildPromptForVariant("B", testReflection);
    assert.ok(!promptA.system.includes("last line should be the URL"), "A should not ask model for URL");
    assert.ok(!promptB.system.includes("last line must be the URL"), "B should not ask model for URL");
  });

  it("variant A and B produce different system prompts", () => {
    const promptA = buildPromptForVariant("A", testReflection);
    const promptB = buildPromptForVariant("B", testReflection);
    assert.notEqual(promptA.system, promptB.system, "variants should have different system prompts");
  });

  it("both variants include content body in user prompt", () => {
    const promptA = buildPromptForVariant("A", testReflection);
    const promptB = buildPromptForVariant("B", testReflection);
    assert.ok(promptA.user.includes("A/B testing"), "variant A user should include body content");
    assert.ok(promptB.user.includes("A/B testing"), "variant B user should include body content");
  });

  it("variant A passes full body content without truncation", () => {
    const longReflection: ReflectionData = {
      ...testReflection,
      body: "x".repeat(3000),
    };
    const prompt = buildPromptForVariant("A", longReflection);
    const bodyInPrompt = prompt.user.split("Content:\n")[1] ?? "";
    assert.equal(bodyInPrompt.length, 3000, "body should be passed in full");
  });

  it("variant B passes full body content without truncation", () => {
    const longReflection: ReflectionData = {
      ...testReflection,
      body: "y".repeat(3000),
    };
    const prompt = buildPromptForVariant("B", longReflection);
    const bodyInPrompt = prompt.user.split("Content:\n")[1] ?? "";
    assert.equal(bodyInPrompt.length, 3000, "body should be passed in full");
  });

  it("variant B instructs 2nd person and concision", () => {
    const prompt = buildPromptForVariant("B", testReflection);
    assert.ok(prompt.system.includes("2nd person"), "should instruct 2nd person");
    assert.ok(
      prompt.system.includes("concis") || prompt.system.includes("Minimize word count"),
      "should instruct concision",
    );
  });

  it("variant A includes topic tag formatting instructions but B does not", () => {
    const promptA = buildPromptForVariant("A", testReflection);
    const promptB = buildPromptForVariant("B", testReflection);
    assert.ok(
      promptA.system.includes("emoji followed by a space and a short topic label"),
      "variant A should include topic tag formatting",
    );
    assert.ok(
      !promptB.system.includes("emoji followed by a space and a short topic label"),
      "variant B should NOT include topic tag formatting (tags reuse prompt A)",
    );
  });

  it("topic tag instructions warn against bare emojis", () => {
    const promptA = buildPromptForVariant("A", testReflection);
    assert.ok(
      promptA.system.includes("Do NOT output bare emojis"),
      "should warn against bare emoji output",
    );
  });

  it("is a pure function — same input produces same output", () => {
    const prompt1 = buildPromptForVariant("A", testReflection);
    const prompt2 = buildPromptForVariant("A", testReflection);
    assert.deepEqual(prompt1, prompt2);
  });

  it("variant B generates question only — tags come from prompt A (reused)", () => {
    const promptB = buildPromptForVariant("B", testReflection);
    // Prompt B should ask for question only
    assert.ok(promptB.system.includes("question"), "should mention question");
    assert.ok(!promptB.system.includes("topic tags"), "should NOT mention topic tags");
    assert.ok(!promptB.system.includes("TOPIC TAGS"), "should NOT mention TOPIC TAGS");
    // Tags are generated by a separate call to prompt A — verified in gemini.ts
  });
});

// --- assemblePostForVariant (deterministic assembly) ---

describe("assemblePostForVariant", () => {
  it("variant A: assembles title + tags + URL", () => {
    const post = assemblePostForVariant(
      "A",
      "📚 Books | 🤖 AI | 🧠 Learning",
      testReflection,
    );
    assert.ok(post.startsWith(testReflection.title), "should start with title");
    assert.ok(post.includes("📚 Books | 🤖 AI | 🧠 Learning"), "should include tags");
    assert.ok(post.endsWith(testReflection.url), "should end with URL");
  });

  it("variant A: has blank line between title and tags", () => {
    const post = assemblePostForVariant("A", "📚 Books", testReflection);
    const lines = post.split("\n");
    assert.equal(lines[0], testReflection.title, "line 0 = title");
    assert.equal(lines[1], "", "line 1 = blank");
    assert.equal(lines[2], "📚 Books", "line 2 = tags");
    assert.equal(lines[3], testReflection.url, "line 3 = URL");
  });

  it("variant B: assembles title + question + tags + URL", () => {
    const modelOutput = "🤔 Ever trusted a machine more than your gut?\n📚 Sci-Fi | 🤖 AGI";
    const post = assemblePostForVariant("B", modelOutput, testReflection);
    assert.ok(post.startsWith(testReflection.title), "should start with title");
    assert.ok(post.includes("#AI Q:"), "should include AI question prefix");
    assert.ok(post.includes("Ever trusted a machine"), "should include question");
    assert.ok(post.includes("📚 Sci-Fi | 🤖 AGI"), "should include tags");
    assert.ok(post.endsWith(testReflection.url), "should end with URL");
  });

  it("variant B: has correct line structure", () => {
    const modelOutput = "🤔 Question here?\n📚 Books | 🤖 AI";
    const post = assemblePostForVariant("B", modelOutput, testReflection);
    const lines = post.split("\n");
    assert.equal(lines[0], testReflection.title, "line 0 = title");
    assert.equal(lines[1], "", "line 1 = blank");
    assert.equal(lines[2], `${AI_QUESTION_PREFIX}🤔 Question here?`, "line 2 = question with prefix");
    assert.equal(lines[3], "", "line 3 = blank");
    assert.equal(lines[4], "📚 Books | 🤖 AI", "line 4 = tags");
    assert.equal(lines[5], testReflection.url, "line 5 = URL");
  });

  it("variant A: title and URL are NEVER from model output", () => {
    // Even if model returns a URL or title, the assembler ignores them
    const post = assemblePostForVariant("A", "📚 Books", testReflection);
    assert.ok(post.includes(testReflection.title), "title comes from reflection, not model");
    assert.ok(post.includes(testReflection.url), "URL comes from reflection, not model");
  });

  it("variant B: title and URL are NEVER from model output", () => {
    const post = assemblePostForVariant("B", "🤔 Question?\n📚 Tags", testReflection);
    assert.ok(post.includes(testReflection.title), "title comes from reflection, not model");
    assert.ok(post.includes(testReflection.url), "URL comes from reflection, not model");
  });

  it("assemblers are pure functions", () => {
    const a1 = assemblePostForVariant("A", "📚 Books", testReflection);
    const a2 = assemblePostForVariant("A", "📚 Books", testReflection);
    assert.equal(a1, a2, "same input should produce same output");
  });

  it("variant A: trims whitespace from model output", () => {
    const post = assemblePostForVariant("A", "  📚 Books | 🤖 AI  \n", testReflection);
    assert.ok(post.includes("📚 Books | 🤖 AI"), "should trim model output");
  });

  it("variant B: handles model output with extra blank lines", () => {
    const modelOutput = "\n🤔 Question here?\n\n📚 Books | 🤖 AI\n\n";
    const post = assemblePostForVariant("B", modelOutput, testReflection);
    assert.ok(post.includes(`${AI_QUESTION_PREFIX}🤔 Question here?`), "should parse question");
    assert.ok(post.includes("📚 Books | 🤖 AI"), "should parse tags");
  });
});

// --- parseVariantBOutput ---

describe("parseVariantBOutput", () => {
  it("parses two-line output", () => {
    const { question, tags } = parseVariantBOutput("🤔 Question?\n📚 Books | 🤖 AI");
    assert.equal(question, "🤔 Question?");
    assert.equal(tags, "📚 Books | 🤖 AI");
  });

  it("handles extra blank lines", () => {
    const { question, tags } = parseVariantBOutput("\n🤔 Question?\n\n📚 Books\n");
    assert.equal(question, "🤔 Question?");
    assert.equal(tags, "📚 Books");
  });

  it("handles single line (question only)", () => {
    const { question, tags } = parseVariantBOutput("🤔 Question?");
    assert.equal(question, "🤔 Question?");
    assert.equal(tags, "");
  });

  it("handles empty output", () => {
    const { question, tags } = parseVariantBOutput("");
    assert.equal(question, "");
    assert.equal(tags, "");
  });

  it("trims whitespace from both parts", () => {
    const { question, tags } = parseVariantBOutput("  🤔 Question?  \n  📚 Books  ");
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

  it("variant B prompt includes max character count", () => {
    const prompt = buildPromptForVariant("B", testReflection);
    assert.ok(prompt.system.includes("at most"), "should include character limit");
    assert.ok(prompt.system.includes("characters"), "should mention characters");
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
  it("is shorter than the old prefix for character savings", () => {
    assert.ok(AI_QUESTION_PREFIX.length < 25, `prefix should be short, got ${AI_QUESTION_PREFIX.length}`);
  });

  it("starts with #AI", () => {
    assert.ok(AI_QUESTION_PREFIX.startsWith("#AI"), "should start with #AI");
  });
});
