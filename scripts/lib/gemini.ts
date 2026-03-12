/**
 * AI text generation via Google Gemini.
 *
 * The model generates ONLY creative content (topic tags, discussion questions).
 * Deterministic parts (title, URL, formatting) are assembled in code via
 * the variant's PostAssembler from prompts.ts.
 *
 * Supports A/B testing via variant-aware prompt selection:
 * the prompt is determined by a VariantId, looked up from
 * the versioned prompt registry in prompts.ts.
 *
 * @module gemini
 */

import type { ReflectionData } from "./types.ts";
import type { VariantId } from "./experiment.ts";
import { validateTweetLength } from "./text.ts";
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
 * Generate post text using Google Gemini API.
 *
 * The model generates ONLY creative parts (topic tags, question).
 * The assembler deterministically injects them into the final post
 * alongside the title and URL.
 *
 * Returns validated text within Twitter's character limit.
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

  const prompt = buildPromptForVariant(variant, reflection);

  const result = await model.generateContent({
    contents: [
      {
        role: "user",
        parts: [{ text: `${prompt.system}\n\n${prompt.user}` }],
      },
    ],
  });

  const modelOutput = result.response.text().trim();

  // Assemble the final post deterministically from creative parts + title/URL
  const text = assemblePostForVariant(variant, modelOutput, reflection);

  const { valid, length } = validateTweetLength(text);
  if (!valid) {
    throw new Error(
      `Generated tweet exceeds 280 characters (${length} effective chars). Tweet: ${text}`,
    );
  }

  return text;
}
