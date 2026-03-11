/**
 * Tests for scripts/lib/prompts.ts — Versioned prompt variants.
 *
 * Verifies that prompt builders produce well-formed prompts for both
 * control (A) and treatment (B) variants, and that the registry
 * covers all variant IDs.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  PROMPT_VARIANTS,
  getPromptBuilder,
  buildPromptForVariant,
} from "./prompts.ts";
import type { PromptPair } from "./prompts.ts";
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

// --- Helper: validate common prompt properties ---

const assertValidPrompt = (prompt: PromptPair, reflection: ReflectionData): void => {
  assert.ok(prompt.system.length > 0, "system prompt should not be empty");
  assert.ok(prompt.user.length > 0, "user prompt should not be empty");
  assert.ok(prompt.system.includes(reflection.title), "system prompt should include title");
  assert.ok(prompt.system.includes(reflection.url), "system prompt should include URL");
  assert.ok(prompt.user.includes(reflection.title), "user prompt should include title");
  assert.ok(prompt.user.includes(reflection.url), "user prompt should include URL");
  assert.ok(prompt.user.includes(reflection.date), "user prompt should include date");
};

// --- PROMPT_VARIANTS registry ---

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

// --- getPromptBuilder ---

describe("getPromptBuilder", () => {
  it("returns a function for variant A", () => {
    assert.equal(typeof getPromptBuilder("A"), "function");
  });

  it("returns a function for variant B", () => {
    assert.equal(typeof getPromptBuilder("B"), "function");
  });
});

// --- buildPromptForVariant ---

describe("buildPromptForVariant", () => {
  it("builds a valid prompt for variant A", () => {
    const prompt = buildPromptForVariant("A", testReflection);
    assertValidPrompt(prompt, testReflection);
  });

  it("builds a valid prompt for variant B", () => {
    const prompt = buildPromptForVariant("B", testReflection);
    assertValidPrompt(prompt, testReflection);
  });

  it("variant A system prompt mentions social media writer", () => {
    const prompt = buildPromptForVariant("A", testReflection);
    assert.ok(prompt.system.includes("social media writer"), "variant A should mention social media writer");
  });

  it("variant B system prompt mentions conversation or thoughtful", () => {
    const prompt = buildPromptForVariant("B", testReflection);
    assert.ok(
      prompt.system.includes("conversation") || prompt.system.includes("thoughtful"),
      "variant B should mention conversational style",
    );
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

  it("truncates long body content to 1500 characters", () => {
    const longReflection: ReflectionData = {
      ...testReflection,
      body: "x".repeat(3000),
    };
    const prompt = buildPromptForVariant("A", longReflection);
    // The body in the user prompt should be truncated
    const bodyInPrompt = prompt.user.split("Content:\n")[1] ?? "";
    assert.ok(bodyInPrompt.length <= 1500, "body should be truncated to 1500 chars");
  });

  it("variant B mentions conversational hook in system prompt", () => {
    const prompt = buildPromptForVariant("B", testReflection);
    assert.ok(
      prompt.system.includes("hook") || prompt.system.includes("question") || prompt.system.includes("insight"),
      "variant B should guide toward conversational hook",
    );
  });

  it("is a pure function — same input produces same output", () => {
    const prompt1 = buildPromptForVariant("A", testReflection);
    const prompt2 = buildPromptForVariant("A", testReflection);
    assert.deepEqual(prompt1, prompt2);
  });
});
