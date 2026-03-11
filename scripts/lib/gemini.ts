/**
 * AI text generation via Google Gemini.
 *
 * Encapsulates the prompt construction and API interaction
 * for generating social media post text.
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
import { buildPromptForVariant, type PromptPair } from "./prompts.ts";

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

/** Result of generating post text, including which variant was used. */
export interface GenerateResult {
  readonly text: string;
  readonly variant: VariantId;
}

/**
 * Generate post text using Google Gemini API.
 * Returns validated text within Twitter's character limit.
 *
 * When a variant is specified, uses the corresponding prompt from the
 * versioned prompt registry. Defaults to variant "A" (the control).
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

  const text = result.response.text().trim();

  const { valid, length } = validateTweetLength(text);
  if (!valid) {
    throw new Error(
      `Generated tweet exceeds 280 characters (${length} effective chars). Tweet: ${text}`,
    );
  }

  return text;
}
