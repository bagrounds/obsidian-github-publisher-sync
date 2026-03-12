/**
 * AI text generation via Google Gemini.
 *
 * The model generates ONLY creative content (topic tags, discussion questions).
 * Deterministic parts (title, URL, formatting) are assembled in code via
 * the variant's PostAssembler from prompts.ts.
 *
 * For variant B, two model calls are made:
 * 1. Tags via prompt A (reused — ensures same tags for both variants)
 * 2. Question via prompt B (question-only)
 * This guarantees the only difference between A and B is the added question.
 *
 * Supports A/B testing via variant-aware prompt selection:
 * the prompt is determined by a VariantId, looked up from
 * the versioned prompt registry in prompts.ts.
 *
 * @module gemini
 */

import type { ReflectionData } from "./types.ts";
import type { VariantId } from "./experiment.ts";
import { DEFAULT_GEMINI_MODEL } from "./types.ts";
import { buildPromptForVariant, assemblePostForVariant, type PromptPair } from "./prompts.ts";

/**
 * Build the prompt for Gemini to generate a social media post.
 * Pure function — constructs the prompt from reflection data.
 *
 * @deprecated Use buildPromptForVariant from prompts.ts for A/B testing.
 * Retained for backward compatibility.
 */
export function buildGeminiPrompt(reflection: ReflectionData): PromptPair {
  return buildPromptForVariant("A", reflection);
}

/**
 * Call the Gemini model with a prompt and return the trimmed text output.
 * Pure helper — no assembly or validation.
 */
async function callGemini(
  model: { generateContent: (req: unknown) => Promise<{ response: { text: () => string } }> },
  prompt: PromptPair,
): Promise<string> {
  const result = await model.generateContent({
    contents: [
      {
        role: "user",
        parts: [{ text: `${prompt.system}\n\n${prompt.user}` }],
      },
    ],
  });
  return result.response.text().trim();
}

/**
 * Generate post text using Google Gemini API.
 *
 * The model generates ONLY creative parts (topic tags, question).
 * The assembler deterministically injects them into the final post
 * alongside the title and URL.
 *
 * For variant B, two calls are made:
 * 1. Tags via prompt A (same tags as an A post would get)
 * 2. Question via prompt B (question-only)
 * The outputs are combined for the assembler.
 *
 * Platform-specific length limits are enforced by each platform's
 * posting task via fitPostToLimit(), not here.
 */
export async function generateTweetWithGemini(
  reflection: ReflectionData,
  apiKey: string,
  modelName: string = DEFAULT_GEMINI_MODEL,
  variant: VariantId = "A",
): Promise<string> {
  const { GoogleGenerativeAI } = await import("@google/generative-ai");
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: modelName });

  let modelOutput: string;

  if (variant === "B") {
    // Variant B: two calls — reuse prompt A for tags, prompt B for question only
    const tagsPrompt = buildPromptForVariant("A", reflection);
    const questionPrompt = buildPromptForVariant("B", reflection);

    const [tags, question] = await Promise.all([
      callGemini(model, tagsPrompt),
      callGemini(model, questionPrompt),
    ]);

    // Combine as "question\ntags" for the assembler's parseVariantBOutput
    modelOutput = `${question}\n${tags}`;
  } else {
    // Variant A: single call for tags
    const prompt = buildPromptForVariant(variant, reflection);
    modelOutput = await callGemini(model, prompt);
  }

  // Assemble the final post deterministically from creative parts + title/URL
  const text = assemblePostForVariant(variant, modelOutput, reflection);

  return text;
}
