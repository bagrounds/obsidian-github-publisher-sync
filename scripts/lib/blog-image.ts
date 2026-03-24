import fs from "node:fs";
import path from "node:path";

import yaml from "js-yaml";

import { parseFrontmatter } from "./frontmatter.ts";
import { stripEmbedSections, todayPacific } from "./blog-prompt.ts";
import { geminiModelFallback } from "./types.ts";

const IMAGE_EXTENSIONS = /\.(jpg|jpeg|png|gif|webp)$/i;
const OBSIDIAN_IMAGE_EMBED = /!\[\[(?:attachments\/)?[^\]]+\.(jpg|jpeg|png|gif|webp)\]\]/i;
const MARKDOWN_IMAGE_EMBED = /!\[[^\]]*\]\([^)]+\.(jpg|jpeg|png|gif|webp)\)/i;
const EXCLUDED_FILES = new Set(["index.md", "AGENTS.md", "IDEAS.md"]);
const DATE_FILENAME_PATTERN = /^(\d{4}-\d{2}-\d{2})/;

export const DEFAULT_DESCRIBER_MODEL = "gemini-3.1-flash-lite-preview";
const CLOUDFLARE_PROMPT_MAX_LENGTH = 2048;

export interface ImageGenerationResult {
  readonly skipped: boolean;
  readonly imagePath?: string;
  readonly imageName?: string;
  readonly imagePrompt?: string;
}

export type PromptDescriber = (content: string) => Promise<string>;

export interface NoteInfo {
  readonly filePath: string;
  readonly relativePath: string;
  readonly date: string;
  readonly title: string;
  readonly content: string;
}

export interface BackfillResult {
  readonly imagesGenerated: number;
  readonly filesUpdated: number;
  readonly stoppedByQuota: boolean;
}

export type ImageGenerator = (
  apiKey: string,
  model: string,
  prompt: string,
) => Promise<{ readonly data: Buffer; readonly mimeType: string }>;

export const hasEmbeddedImage = (content: string): boolean =>
  OBSIDIAN_IMAGE_EMBED.test(content) || MARKDOWN_IMAGE_EMBED.test(content);

export const titleToKebabCase = (title: string): string =>
  title
    .replace(/[\p{Emoji_Presentation}\p{Emoji}\u200d\ufe0f]/gu, "")
    .replace(/\d{4}-\d{2}-\d{2}\s*\|?\s*/g, "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");

export const notePathToImageBaseName = (notePath: string): string => {
  const dir = path.basename(path.dirname(notePath));
  const stem = path.basename(notePath, path.extname(notePath));
  return [dir, stem]
    .join("-")
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
};

export const resolveUniqueImageName = (
  baseName: string,
  extension: string,
  attachmentsDir: string,
): string => {
  const candidate = `${baseName}${extension}`;
  if (!fs.existsSync(path.join(attachmentsDir, candidate))) return candidate;

  // eslint-disable-next-line functional/no-let
  for (let n = 2; ; n++) {
    const name = `${baseName}-${n}${extension}`;
    if (!fs.existsSync(path.join(attachmentsDir, name))) return name;
  }
};

export const extractTitle = (content: string): string => {
  const lines = content.split("\n");
  let inFrontmatter = false;

  for (const line of lines) {
    if (line.trim() === "---") {
      if (inFrontmatter) break;
      inFrontmatter = true;
      continue;
    }
    if (inFrontmatter) {
      const match = line.match(/^title:\s*(.+)$/);
      if (match) return (match[1] as string).replace(/^["']|["']$/g, "");
    }
  }

  const h1Line = lines.find((line) => line.startsWith("# "));
  return h1Line ? h1Line.slice(2).trim() : "";
};

export const insertImageEmbed = (
  content: string,
  imageName: string,
): string => {
  const lines = content.split("\n");
  const h1Index = lines.findIndex((line) => line.startsWith("# "));
  if (h1Index === -1) return content;

  const embed = `![[attachments/${imageName}]]`;
  lines.splice(h1Index + 1, 0, embed);
  return lines.join("\n");
};

const splitFrontmatter = (
  content: string,
): {
  readonly yamlBlock: string;
  readonly body: string;
  readonly hasFrontmatter: boolean;
} => {
  const lines = content.split("\n");
  if (lines[0]?.trim() !== "---") {
    return { yamlBlock: "", body: content, hasFrontmatter: false };
  }

  const endIndex = lines.findIndex((line, i) => i > 0 && line.trim() === "---");
  if (endIndex < 0) {
    return { yamlBlock: "", body: content, hasFrontmatter: false };
  }

  return {
    yamlBlock: lines.slice(1, endIndex).join("\n"),
    body: lines.slice(endIndex + 1).join("\n"),
    hasFrontmatter: true,
  };
};

const YAML_OPTS: yaml.DumpOptions & yaml.LoadOptions = {
  lineWidth: -1,
  quotingType: '"',
  forceQuotes: false,
  schema: yaml.JSON_SCHEMA,
};

const dumpYaml = (doc: Record<string, unknown>): string =>
  yaml
    .dump(doc, YAML_OPTS)
    .trim()
    .replace(/^(\S+): null$/gm, "$1:");

export const extractFrontmatterValue = (
  content: string,
  key: string,
): string | undefined => {
  const { yamlBlock, hasFrontmatter } = splitFrontmatter(content);
  if (!hasFrontmatter) return undefined;

  const doc = yaml.load(yamlBlock, YAML_OPTS) as Record<string, unknown> | null;
  const value = doc?.[key];
  return value != null ? String(value) : undefined;
};

export const shouldRegenerateImage = (content: string): boolean =>
  extractFrontmatterValue(content, "regenerate_image") === "true";

const OBSIDIAN_IMAGE_EMBED_LINE =
  /^!\[\[(?:attachments\/)?([^\]]+\.(jpg|jpeg|png|gif|webp))\]\]$/im;

export const removeImageEmbed = (
  content: string,
): { readonly content: string; readonly imageName: string | undefined } => {
  const match = content.match(OBSIDIAN_IMAGE_EMBED_LINE);
  if (!match) return { content, imageName: undefined };

  const imageName = match[1] as string;
  const cleaned = content
    .replace(match[0], "")
    .replace(/\n{3,}/g, "\n\n");
  return { content: cleaned, imageName: imageName.replace(/^attachments\//, "") };
};

export const sanitizeForYaml = (value: string): string =>
  value
    .replace(/\n/g, " ")
    .replace(/\s+/g, " ")
    .replace(/["'\\`]/g, "")
    .trim();

export const updateFrontmatterFields = (
  content: string,
  fields: Record<string, string>,
): string => {
  const { yamlBlock, body, hasFrontmatter } = splitFrontmatter(content);

  const doc = hasFrontmatter
    ? ((yaml.load(yamlBlock, YAML_OPTS) as Record<string, unknown> | null) ?? {})
    : {};

  const merged = { ...doc, ...fields };
  return `---\n${dumpYaml(merged)}\n---\n${body}`;
};

const stripMarkdownSyntax = (text: string): string =>
  text
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/!\[\[[^\]]*\]\]/g, "")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/```[\s\S]*?```/g, "")
    .replace(/`[^`]*`/g, "")
    .replace(/[*_~]{1,3}/g, "")
    .replace(/^[-*+]\s+/gm, "")
    .replace(/^\d+\.\s+/gm, "")
    .replace(/^>\s+/gm, "")
    .replace(/\|[^|\n]*\|/g, "")
    .replace(/^[-|:\s]+$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

export const cleanContentForPrompt = (rawContent: string): string => {
  const { body } = parseFrontmatter(rawContent);
  const withoutEmbeds = stripEmbedSections(body);
  return stripMarkdownSyntax(withoutEmbeds);
};

export const buildImagePrompt = (postContent: string): string => {
  const cleaned = cleanContentForPrompt(postContent);
  const prefix = "generate an image to illustrate the following blog post: ";
  const maxContentLength = CLOUDFLARE_PROMPT_MAX_LENGTH - prefix.length;
  const truncated =
    cleaned.length > maxContentLength
      ? cleaned.slice(0, maxContentLength - 1) + "…"
      : cleaned;
  return `${prefix}${truncated}`;
};

export const mimeTypeToExtension = (mimeType: string): string => {
  const extensions: Record<string, string> = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/gif": ".gif",
    "image/webp": ".webp",
  };
  return extensions[mimeType] ?? ".jpg";
};

export const isQuotaError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const message = String((error as { message?: string }).message ?? "");
  return (
    message.includes("429") ||
    message.includes("RESOURCE_EXHAUSTED") ||
    message.includes("quota")
  );
};

export const isDailyQuotaError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const message = String((error as { message?: string }).message ?? "");
  return (
    message.includes("quota") &&
    (message.includes("daily") ||
     message.includes("per day") ||
     message.includes("PerDay"))
  );
};

export const isProviderUnavailableError = (error: unknown): boolean => {
  if (!error || typeof error !== "object") return false;
  const message = String((error as { message?: string }).message ?? "");
  return (
    message.includes("410") ||
    message.includes("401") ||
    message.includes("403") ||
    message.includes("no longer supported") ||
    message.includes("deprecated")
  );
};

export const parseRetryDelay = (error: unknown): number | null => {
  if (!error || typeof error !== "object") return null;
  const message = String((error as { message?: string }).message ?? "");

  const retryInMatch = message.match(/retry\s+in\s+(\d+(?:\.\d+)?)\s*s/i);
  if (retryInMatch) return Math.ceil(parseFloat(retryInMatch[1] ?? "0") * 1000);

  const delayMatch = message.match(/retryDelay["\s:]*["']?(\d+(?:\.\d+)?)\s*s/i);
  if (delayMatch) return Math.ceil(parseFloat(delayMatch[1] ?? "0") * 1000);

  return null;
};

const DEFAULT_BACKOFF_MS = 5_000;
const MAX_BACKOFF_MS = 60_000;
const MAX_RETRIES = 3;
const DEFAULT_MIN_DELAY_MS = 4_000;

export const isImagenModel = (model: string): boolean =>
  model.startsWith("imagen-");

interface InlineImageData {
  readonly data?: string;
  readonly mimeType?: string;
}

interface ContentPart {
  readonly inlineData?: InlineImageData;
  readonly text?: string;
}

const generateWithImagen = async (
  apiKey: string,
  model: string,
  prompt: string,
): Promise<{ readonly data: Buffer; readonly mimeType: string }> => {
  const { GoogleGenAI } = await import("@google/genai");
  const ai = new GoogleGenAI({ apiKey });

  const response = await ai.models.generateImages({
    model,
    prompt,
    config: { numberOfImages: 1 },
  });

  const firstImage = response.generatedImages?.[0];
  const imageBytes = firstImage?.image?.imageBytes;

  if (!imageBytes) {
    throw new Error("No image generated from Imagen API");
  }

  return {
    data: Buffer.from(imageBytes, "base64"),
    mimeType: firstImage?.image?.mimeType ?? "image/png",
  };
};

const generateWithGeminiContent = async (
  apiKey: string,
  model: string,
  prompt: string,
): Promise<{ readonly data: Buffer; readonly mimeType: string }> => {
  const { GoogleGenAI } = await import("@google/genai");
  const ai = new GoogleGenAI({ apiKey });

  const response = await ai.models.generateContent({
    model,
    contents: prompt,
  });

  const candidates = response.candidates ?? [];
  if (candidates.length === 0) {
    throw new Error("No candidates returned from image generation");
  }

  const parts: readonly ContentPart[] = candidates[0]?.content?.parts ?? [];
  const imagePart = parts.find((part) => part.inlineData?.data);

  if (!imagePart?.inlineData?.data) {
    throw new Error("No image generated");
  }

  return {
    data: Buffer.from(imagePart.inlineData.data, "base64"),
    mimeType: imagePart.inlineData.mimeType ?? "image/png",
  };
};

export const generateImageWithGemini: ImageGenerator = async (
  apiKey,
  model,
  prompt,
) =>
  isImagenModel(model)
    ? generateWithImagen(apiKey, model, prompt)
    : generateWithGeminiContent(apiKey, model, prompt);

const IMAGE_DESCRIPTION_SYSTEM_PROMPT = [
  "Describe a cover image for the following blog post.",
  "Focus on visual elements that would make an appealing illustration.",
  "Be concise — respond in under 150 words.",
  "Do not include any text or words in the image.",
  "Respond with only the image description, no preamble.",
].join(" ");

export const describeImageWithGemini = async (
  apiKey: string,
  content: string,
  model: string,
): Promise<string> => {
  const { GoogleGenAI } = await import("@google/genai");
  const ai = new GoogleGenAI({ apiKey });

  const attemptGeneration = async (modelName: string): Promise<string> => {
    const response = await ai.models.generateContent({
      model: modelName,
      contents: `${IMAGE_DESCRIPTION_SYSTEM_PROMPT}\n\n${content}`,
    });
    return (response.text ?? "").trim();
  };

  try {
    return await attemptGeneration(model);
  } catch (error) {
    const fallback = geminiModelFallback(model);
    if (fallback) {
      console.warn(`⚠️ ${model} failed for image description, falling back to ${fallback}`);
      return await attemptGeneration(fallback);
    }
    throw error;
  }
};

export const makeGeminiDescriber = (
  apiKey: string,
  model: string,
): PromptDescriber =>
  (content: string) => describeImageWithGemini(apiKey, content, model);

interface CloudflareApiResponse {
  readonly result?: { readonly image?: string };
  readonly success: boolean;
  readonly errors?: readonly { readonly message: string }[];
}

export const generateWithCloudflare = async (
  apiToken: string,
  accountId: string,
  prompt: string,
  model: string = "@cf/black-forest-labs/flux-1-schnell",
  steps: number = 4,
): Promise<{ readonly data: Buffer; readonly mimeType: string }> => {
  const url = `https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/${model}`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ prompt, steps }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(
      `Cloudflare API error ${response.status}: ${text}`,
    );
  }

  const json = (await response.json()) as CloudflareApiResponse;

  if (!json.success || !json.result?.image) {
    const errorMsg = json.errors?.map((e) => e.message).join("; ") ?? "Unknown error";
    throw new Error(`Cloudflare image generation failed: ${errorMsg}`);
  }

  return {
    data: Buffer.from(json.result.image, "base64"),
    mimeType: "image/jpeg",
  };
};

export const makeCloudflareGenerator = (
  accountId: string,
  model: string = "@cf/black-forest-labs/flux-1-schnell",
): ImageGenerator => async (apiToken, _model, prompt) =>
  generateWithCloudflare(apiToken, accountId, prompt, model);

export const DEFAULT_HUGGINGFACE_IMAGE_MODEL = "black-forest-labs/FLUX.1-schnell";

export const generateWithHuggingFace = async (
  apiToken: string,
  model: string,
  prompt: string,
): Promise<{ readonly data: Buffer; readonly mimeType: string }> => {
  const url = `https://router.huggingface.co/hf-inference/models/${model}`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ inputs: prompt }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(
      `HuggingFace API error ${response.status}: ${text}`,
    );
  }

  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.startsWith("image/")) {
    const text = await response.text();
    throw new Error(`HuggingFace returned non-image response: ${text}`);
  }

  const arrayBuffer = await response.arrayBuffer();
  return {
    data: Buffer.from(arrayBuffer),
    mimeType: contentType.split(";")[0] ?? "image/jpeg",
  };
};

export const makeHuggingFaceGenerator = (
  model: string = DEFAULT_HUGGINGFACE_IMAGE_MODEL,
): ImageGenerator => async (apiToken, _model, prompt) =>
  generateWithHuggingFace(apiToken, model, prompt);

export const DEFAULT_TOGETHER_IMAGE_MODEL = "black-forest-labs/FLUX.1-schnell-Free";

interface TogetherApiResponse {
  readonly data?: readonly { readonly b64_json?: string }[];
}

export const generateWithTogether = async (
  apiKey: string,
  model: string,
  prompt: string,
): Promise<{ readonly data: Buffer; readonly mimeType: string }> => {
  const url = "https://api.together.ai/v1/images/generations";

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      prompt,
      steps: 4,
      n: 1,
      response_format: "b64_json",
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(
      `Together API error ${response.status}: ${text}`,
    );
  }

  const json = (await response.json()) as TogetherApiResponse;
  const b64 = json.data?.[0]?.b64_json;

  if (!b64) {
    throw new Error("Together image generation returned no image data");
  }

  return {
    data: Buffer.from(b64, "base64"),
    mimeType: "image/jpeg",
  };
};

export const makeTogetherGenerator = (
  model: string = DEFAULT_TOGETHER_IMAGE_MODEL,
): ImageGenerator => async (apiKey, _model, prompt) =>
  generateWithTogether(apiKey, model, prompt);

export const DEFAULT_POLLINATIONS_IMAGE_MODEL = "flux";

export const generateWithPollinations = async (
  _apiKey: string,
  model: string,
  prompt: string,
): Promise<{ readonly data: Buffer; readonly mimeType: string }> => {
  const encodedPrompt = encodeURIComponent(prompt);
  const url = `https://image.pollinations.ai/prompt/${encodedPrompt}?model=${encodeURIComponent(model)}&width=1024&height=1024&nologo=true`;

  const response = await fetch(url);

  if (!response.ok) {
    const text = await response.text();
    throw new Error(
      `Pollinations API error ${response.status}: ${text}`,
    );
  }

  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.startsWith("image/")) {
    const text = await response.text();
    throw new Error(`Pollinations returned non-image response: ${text}`);
  }

  const arrayBuffer = await response.arrayBuffer();
  return {
    data: Buffer.from(arrayBuffer),
    mimeType: contentType.split(";")[0] ?? "image/jpeg",
  };
};

export const makePollinationsGenerator = (
  model: string = DEFAULT_POLLINATIONS_IMAGE_MODEL,
): ImageGenerator => async (_apiKey, _model, prompt) =>
  generateWithPollinations("", model, prompt);

export interface ImageProviderConfig {
  readonly name: string;
  readonly apiKey: string;
  readonly model: string;
  readonly generator: ImageGenerator;
  readonly describePrompt?: PromptDescriber;
}

export const resolveImageProviders = (env: Record<string, string | undefined>): readonly ImageProviderConfig[] => {
  const geminiKey = env.GEMINI_API_KEY;
  const describerModel = env.PROMPT_DESCRIBER_MODEL ?? DEFAULT_DESCRIBER_MODEL;
  const describePrompt = geminiKey
    ? makeGeminiDescriber(geminiKey, describerModel)
    : undefined;

  const providers: ImageProviderConfig[] = [];

  const cfToken = env.CLOUDFLARE_API_TOKEN;
  const cfAccountId = env.CLOUDFLARE_ACCOUNT_ID;
  const cfModel = env.CLOUDFLARE_IMAGE_MODEL ?? "@cf/black-forest-labs/flux-1-schnell";

  if (cfToken && cfAccountId) {
    providers.push({
      name: "cloudflare",
      apiKey: cfToken,
      model: cfModel,
      generator: makeCloudflareGenerator(cfAccountId, cfModel),
      describePrompt,
    });
  }

  const hfToken = env.HUGGINGFACE_API_TOKEN;
  const hfModel = env.HUGGINGFACE_IMAGE_MODEL ?? DEFAULT_HUGGINGFACE_IMAGE_MODEL;

  if (hfToken) {
    providers.push({
      name: "huggingface",
      apiKey: hfToken,
      model: hfModel,
      generator: makeHuggingFaceGenerator(hfModel),
      describePrompt,
    });
  }

  const togetherKey = env.TOGETHER_API_TOKEN;
  const togetherModel = env.TOGETHER_IMAGE_MODEL ?? DEFAULT_TOGETHER_IMAGE_MODEL;

  if (togetherKey) {
    providers.push({
      name: "together",
      apiKey: togetherKey,
      model: togetherModel,
      generator: makeTogetherGenerator(togetherModel),
      describePrompt,
    });
  }

  const pollinationsModel = env.POLLINATIONS_IMAGE_MODEL ?? DEFAULT_POLLINATIONS_IMAGE_MODEL;

  if (env.POLLINATIONS_ENABLED === "true") {
    providers.push({
      name: "pollinations",
      apiKey: "",
      model: pollinationsModel,
      generator: makePollinationsGenerator(pollinationsModel),
      describePrompt,
    });
  }

  const geminiModel = env.IMAGE_GEMINI_MODEL ?? "gemini-3.1-flash-image-preview";

  if (geminiKey) {
    providers.push({
      name: "gemini",
      apiKey: geminiKey,
      model: geminiModel,
      generator: generateImageWithGemini,
      describePrompt,
    });
  }

  if (providers.length === 0) {
    throw new Error(
      "No image generation credentials found. Set CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID, HUGGINGFACE_API_TOKEN, TOGETHER_API_TOKEN, POLLINATIONS_ENABLED=true, or GEMINI_API_KEY.",
    );
  }

  return providers;
};

export const resolveImageProvider = (env: Record<string, string | undefined>): ImageProviderConfig =>
  resolveImageProviders(env)[0]!;

export const processNote = async (
  notePath: string,
  attachmentsDir: string,
  apiKey: string,
  model: string,
  generate: ImageGenerator = generateImageWithGemini,
  describePrompt?: PromptDescriber,
): Promise<ImageGenerationResult> => {
  let content = fs.readFileSync(notePath, "utf-8");

  if (shouldRegenerateImage(content)) {
    const { content: cleaned, imageName: oldImage } = removeImageEmbed(content);
    content = updateFrontmatterFields(cleaned, { regenerate_image: "false" });

    if (oldImage) {
      const oldPath = path.join(attachmentsDir, oldImage);
      if (fs.existsSync(oldPath)) fs.unlinkSync(oldPath);
    }

    fs.writeFileSync(notePath, content, "utf-8");
  }

  if (hasEmbeddedImage(content)) {
    return { skipped: true };
  }

  const title = extractTitle(content);
  if (!title) {
    return { skipped: true };
  }

  const baseName = notePathToImageBaseName(notePath);
  if (!baseName) {
    return { skipped: true };
  }

  const cachedPrompt = extractFrontmatterValue(content, "image_prompt");
  const prompt = cachedPrompt
    ? cachedPrompt
    : describePrompt
      ? sanitizeForYaml(await describePrompt(content))
      : buildImagePrompt(content);
  const { data, mimeType } = await generate(apiKey, model, prompt);

  const extension = mimeTypeToExtension(mimeType);
  const imageName = resolveUniqueImageName(baseName, extension, attachmentsDir);
  const imagePath = path.join(attachmentsDir, imageName);

  fs.mkdirSync(attachmentsDir, { recursive: true });
  fs.writeFileSync(imagePath, data);

  let updatedContent = insertImageEmbed(content, imageName);
  updatedContent = updateFrontmatterFields(updatedContent, {
    image_date: new Date().toISOString(),
    image_model: model,
    image_prompt: prompt,
  });
  fs.writeFileSync(notePath, updatedContent, "utf-8");

  return { skipped: false, imagePath, imageName, imagePrompt: prompt };
};

export const isPostFile = (filename: string): boolean =>
  filename.endsWith(".md") &&
  !EXCLUDED_FILES.has(filename) &&
  DATE_FILENAME_PATTERN.test(filename);

export const extractDateFromFilename = (filename: string): string =>
  filename.match(DATE_FILENAME_PATTERN)?.[1] ?? "";

export { todayPacific } from "./blog-prompt.ts";

export const readNoteInfo = (
  dir: string,
  filename: string,
): NoteInfo | undefined => {
  const filePath = path.join(dir, filename);
  const content = fs.readFileSync(filePath, "utf-8");
  const date = extractDateFromFilename(filename);
  const title = extractTitle(content);
  if (!date || !title) return undefined;
  return { filePath, relativePath: filename, date, title, content };
};

export const listNotesNewestFirst = (dir: string): readonly string[] =>
  fs.existsSync(dir)
    ? fs.readdirSync(dir).filter(isPostFile).sort().reverse()
    : [];

export interface BackfillConfig {
  readonly directories: readonly { readonly path: string; readonly id: string }[];
  readonly attachmentsDir: string;
  readonly apiKey: string;
  readonly model: string;
  readonly generate?: ImageGenerator;
  readonly describePrompt?: PromptDescriber;
  readonly providerName?: string;
  readonly fallbackProviders?: readonly ImageProviderConfig[];
  readonly onProgress?: (event: Record<string, unknown>) => void;
  readonly minDelayMs?: number;
  readonly sleep?: (ms: number) => Promise<void>;
}

interface BackfillCandidate {
  readonly filePath: string;
  readonly dirPath: string;
  readonly dirId: string;
  readonly filename: string;
  readonly date: string;
  readonly needsRegeneration: boolean;
}

const defaultSleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

const collectCandidates = (
  directories: readonly { readonly path: string; readonly id: string }[],
  today: string,
  onProgress: (event: Record<string, unknown>) => void,
): {
  readonly candidates: readonly BackfillCandidate[];
  readonly dirFiles: ReadonlyMap<string, readonly string[]>;
} => {
  const candidates: BackfillCandidate[] = [];
  const dirFiles = new Map<string, readonly string[]>();

  for (const { path: dirPath, id } of directories) {
    if (!fs.existsSync(dirPath)) {
      onProgress({ event: "directory_missing", directory: id });
      continue;
    }

    const files = listNotesNewestFirst(dirPath);
    dirFiles.set(id, files.map((f) => path.join(dirPath, f)));

    for (const filename of files) {
      const date = extractDateFromFilename(filename);

      if (id === "reflections" && date > today) {
        onProgress({ event: "skip_future_reflection", filename, date, today });
        continue;
      }

      const filePath = path.join(dirPath, filename);
      const content = fs.readFileSync(filePath, "utf-8");
      const needsRegeneration = shouldRegenerateImage(content);

      if (hasEmbeddedImage(content) && !needsRegeneration) {
        onProgress({ event: "already_has_image", directory: id, filename });
        continue;
      }

      candidates.push({ filePath, dirPath, dirId: id, filename, date, needsRegeneration });
    }
  }

  const sorted = candidates.sort((a, b) => b.date.localeCompare(a.date));
  return { candidates: sorted, dirFiles };
};

const buildChain = (
  candidate: BackfillCandidate,
  dirFiles: ReadonlyMap<string, readonly string[]>,
): readonly string[] => {
  const allFiles = dirFiles.get(candidate.dirId) ?? [];
  const candidateIndex = allFiles.indexOf(candidate.filePath);
  return candidateIndex >= 0 ? allFiles.slice(0, candidateIndex + 1) : [candidate.filePath];
};

const retryOnRateLimit = async (
  fn: () => Promise<ImageGenerationResult>,
  sleepFn: (ms: number) => Promise<void>,
  onProgress: (event: Record<string, unknown>) => void,
  context: Record<string, unknown>,
): Promise<ImageGenerationResult> => {
  let backoffMs = DEFAULT_BACKOFF_MS;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (isDailyQuotaError(error) || isProviderUnavailableError(error)) {
        throw error;
      }

      if (isQuotaError(error) && attempt < MAX_RETRIES) {
        const serverDelay = parseRetryDelay(error);
        const waitMs = serverDelay ?? backoffMs;
        onProgress({
          event: "rate_limit_retry",
          attempt: attempt + 1,
          maxRetries: MAX_RETRIES,
          waitMs,
          ...context,
        });
        await sleepFn(waitMs);
        backoffMs = Math.min(backoffMs * 2, MAX_BACKOFF_MS);
        continue;
      }

      throw error;
    }
  }

  throw new Error("Exceeded maximum retries");
};

export const backfillImages = async (
  config: BackfillConfig,
): Promise<BackfillResult> => {
  const {
    directories,
    attachmentsDir,
    apiKey,
    model,
    generate = generateImageWithGemini,
    describePrompt,
    providerName = "primary",
    fallbackProviders = [],
    onProgress = () => {},
    minDelayMs = DEFAULT_MIN_DELAY_MS,
    sleep: sleepFn = defaultSleep,
  } = config;

  const allProviders: readonly ImageProviderConfig[] = [
    { name: providerName, apiKey, model, generator: generate, describePrompt },
    ...fallbackProviders,
  ];

  const today = todayPacific();
  let imagesGenerated = 0;
  let filesUpdated = 0;
  let providerIndex = 0;

  const { candidates, dirFiles } = collectCandidates(directories, today, onProgress);

  for (const candidate of candidates) {
    onProgress({
      event: candidate.needsRegeneration ? "regenerating_image" : "generating_image",
      directory: candidate.dirId,
      filename: candidate.filename,
      provider: (allProviders[providerIndex] as ImageProviderConfig).name,
    });

    let generated = false;
    while (providerIndex < allProviders.length) {
      const provider = allProviders[providerIndex] as ImageProviderConfig;

      try {
        const result = await retryOnRateLimit(
          () => processNote(
            candidate.filePath,
            attachmentsDir,
            provider.apiKey,
            provider.model,
            provider.generator,
            provider.describePrompt,
          ),
          sleepFn,
          onProgress,
          { directory: candidate.dirId, filename: candidate.filename, provider: provider.name },
        );

        if (!result.skipped) {
          imagesGenerated++;
          onProgress({
            event: "image_generated",
            directory: candidate.dirId,
            filename: candidate.filename,
            imageName: result.imageName,
            provider: provider.name,
          });

          const chain = buildChain(candidate, dirFiles);
          const timestamp = new Date().toISOString();
          for (const chainFile of chain) {
            updateFrontmatterTimestamp(chainFile, timestamp);
            filesUpdated++;
          }
          onProgress({
            event: "chain_updated",
            directory: candidate.dirId,
            chainLength: chain.length,
          });

          if (minDelayMs > 0) {
            await sleepFn(minDelayMs);
          }
        }

        generated = true;
        break;
      } catch (error) {
        if (isDailyQuotaError(error) || isQuotaError(error) || isProviderUnavailableError(error)) {
          const eventType = isDailyQuotaError(error)
            ? "daily_quota_exhausted"
            : isProviderUnavailableError(error)
              ? "provider_unavailable"
              : "quota_exhausted";

          onProgress({
            event: eventType,
            directory: candidate.dirId,
            filename: candidate.filename,
            imagesGenerated,
            provider: provider.name,
            error: error instanceof Error ? error.message : String(error),
          });

          providerIndex++;

          if (providerIndex < allProviders.length) {
            const next = allProviders[providerIndex] as ImageProviderConfig;
            onProgress({
              event: "provider_switch",
              from: provider.name,
              to: next.name,
              reason: eventType,
            });
            continue;
          }

          return { imagesGenerated, filesUpdated, stoppedByQuota: true };
        }

        onProgress({
          event: "image_generation_failed",
          directory: candidate.dirId,
          filename: candidate.filename,
          error: error instanceof Error ? error.message : String(error),
          provider: provider.name,
        });
        generated = true;
        break;
      }
    }

    if (!generated) {
      return { imagesGenerated, filesUpdated, stoppedByQuota: true };
    }
  }

  return { imagesGenerated, filesUpdated, stoppedByQuota: false };
};

export const updateFrontmatterTimestamp = (
  filePath: string,
  timestamp: string,
): void => {
  if (!fs.existsSync(filePath)) return;

  const content = fs.readFileSync(filePath, "utf-8");
  const updated = updateFrontmatterFields(content, { updated: timestamp });
  fs.writeFileSync(filePath, updated, "utf-8");
};

export const syncMarkdownDir = (
  localDir: string,
  vaultSubdir: string,
  vaultDir: string,
): number => {
  const localPath = path.resolve(localDir);
  const vaultPath = path.join(vaultDir, vaultSubdir);

  if (!fs.existsSync(localPath)) return 0;

  fs.mkdirSync(vaultPath, { recursive: true });
  const files = fs.readdirSync(localPath).filter((f) => f.endsWith(".md"));

  return files.reduce((synced, f) => {
    const src = path.join(localPath, f);
    const dst = path.join(vaultPath, f);
    const srcContent = fs.readFileSync(src, "utf-8");
    const dstContent = fs.existsSync(dst)
      ? fs.readFileSync(dst, "utf-8")
      : "";

    if (srcContent !== dstContent) {
      fs.copyFileSync(src, dst);
      return synced + 1;
    }
    return synced;
  }, 0);
};

export const syncAttachmentsDir = (
  localAttachmentsDir: string,
  vaultDir: string,
): number => {
  if (!fs.existsSync(localAttachmentsDir)) return 0;

  const vaultAttachments = path.join(vaultDir, "attachments");
  fs.mkdirSync(vaultAttachments, { recursive: true });
  const files = fs.readdirSync(localAttachmentsDir);

  return files.reduce((synced, f) => {
    const src = path.join(localAttachmentsDir, f);
    const dst = path.join(vaultAttachments, f);
    if (!fs.existsSync(dst)) {
      fs.copyFileSync(src, dst);
      return synced + 1;
    }
    return synced;
  }, 0);
};
