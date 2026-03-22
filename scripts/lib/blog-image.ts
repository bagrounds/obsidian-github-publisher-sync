import fs from "node:fs";
import path from "node:path";

import { parseFrontmatter } from "./frontmatter.ts";
import { stripEmbedSections } from "./blog-prompt.ts";

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

export const extractFrontmatterValue = (
  content: string,
  key: string,
): string | undefined => {
  const lines = content.split("\n");
  if (lines[0]?.trim() !== "---") return undefined;

  for (let i = 1; i < lines.length; i++) {
    if (lines[i]?.trim() === "---") break;
    const match = lines[i]?.match(new RegExp(`^${key}:\\s*(.+)$`));
    if (match) return (match[1] as string).replace(/^["']|["']$/g, "").trim();
  }
  return undefined;
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

export const quoteYamlValue = (value: string): string => {
  const oneLine = value.replace(/\n/g, " ").replace(/\s+/g, " ").trim();
  return /[:#{}\[\]&*!|>'"@`,]/.test(oneLine)
    ? `"${oneLine.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`
    : oneLine;
};

export const updateFrontmatterFields = (
  content: string,
  fields: Record<string, string>,
): string => {
  const lines = content.split("\n");

  if (lines[0]?.trim() !== "---") {
    const entries = Object.entries(fields)
      .map(([k, v]) => `${k}: ${quoteYamlValue(v)}`)
      .join("\n");
    return `---\n${entries}\n---\n${content}`;
  }

  const endIndex = lines.findIndex((line, i) => i > 0 && line.trim() === "---");
  if (endIndex < 0) return content;

  const frontmatterLines = lines.slice(1, endIndex);
  const beforeFrontmatter = lines.slice(0, 1);
  const afterFrontmatter = lines.slice(endIndex);

  const updatedFrontmatter = Object.entries(fields).reduce(
    (acc, [key, value]) => {
      const existingIndex = acc.findIndex((line) =>
        new RegExp(`^${key}:\\s`).test(line),
      );
      return existingIndex >= 0
        ? acc.map((line, i) =>
            i === existingIndex ? `${key}: ${quoteYamlValue(value)}` : line,
          )
        : [...acc, `${key}: ${quoteYamlValue(value)}`];
    },
    frontmatterLines,
  );

  return [...beforeFrontmatter, ...updatedFrontmatter, ...afterFrontmatter].join(
    "\n",
  );
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

  const response = await ai.models.generateContent({
    model,
    contents: `${IMAGE_DESCRIPTION_SYSTEM_PROMPT}\n\n${content}`,
  });

  const text = response.text ?? "";
  return text.trim();
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

export interface ImageProviderConfig {
  readonly apiKey: string;
  readonly model: string;
  readonly generator: ImageGenerator;
  readonly describePrompt?: PromptDescriber;
}

export const resolveImageProvider = (env: Record<string, string | undefined>): ImageProviderConfig => {
  const cfToken = env.CLOUDFLARE_API_TOKEN;
  const cfAccountId = env.CLOUDFLARE_ACCOUNT_ID;
  const cfModel = env.CLOUDFLARE_IMAGE_MODEL ?? "@cf/black-forest-labs/flux-1-schnell";

  const geminiKey = env.GEMINI_API_KEY;
  const describerModel = env.PROMPT_DESCRIBER_MODEL ?? DEFAULT_DESCRIBER_MODEL;
  const describePrompt = geminiKey
    ? makeGeminiDescriber(geminiKey, describerModel)
    : undefined;

  if (cfToken && cfAccountId) {
    return {
      apiKey: cfToken,
      model: cfModel,
      generator: makeCloudflareGenerator(cfAccountId, cfModel),
      describePrompt,
    };
  }

  const geminiModel = env.IMAGE_GEMINI_MODEL ?? "gemini-3.1-flash-image-preview";

  if (geminiKey) {
    return {
      apiKey: geminiKey,
      model: geminiModel,
      generator: generateImageWithGemini,
      describePrompt,
    };
  }

  throw new Error(
    "No image generation credentials found. Set CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID, or GEMINI_API_KEY.",
  );
};

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

  const prompt = describePrompt
    ? await describePrompt(content)
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

export const todayPacific = (): string => {
  const now = new Date();
  const pacific = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Los_Angeles",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
  return pacific;
};

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
  readonly onProgress?: (event: Record<string, unknown>) => void;
}

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
    onProgress = () => {},
  } = config;

  const today = todayPacific();
  let imagesGenerated = 0;
  let filesUpdated = 0;

  for (const { path: dirPath, id } of directories) {
    if (!fs.existsSync(dirPath)) {
      onProgress({ event: "directory_missing", directory: id });
      continue;
    }

    const files = listNotesNewestFirst(dirPath);
    const chain: string[] = [];

    for (const filename of files) {
      const date = extractDateFromFilename(filename);

      if (id === "reflections" && date > today) {
        onProgress({ event: "skip_future_reflection", filename, date, today });
        continue;
      }

      const filePath = path.join(dirPath, filename);
      chain.push(filePath);

      const content = fs.readFileSync(filePath, "utf-8");
      const needsRegeneration = shouldRegenerateImage(content);
      if (hasEmbeddedImage(content) && !needsRegeneration) {
        onProgress({ event: "already_has_image", directory: id, filename });
        continue;
      }

      onProgress({
        event: needsRegeneration ? "regenerating_image" : "generating_image",
        directory: id,
        filename,
      });

      try {
        const result = await processNote(
          filePath,
          attachmentsDir,
          apiKey,
          model,
          generate,
          describePrompt,
        );

        if (!result.skipped) {
          imagesGenerated++;
          onProgress({
            event: "image_generated",
            directory: id,
            filename,
            imageName: result.imageName,
          });

          const timestamp = new Date().toISOString();
          for (const chainFile of chain) {
            updateFrontmatterTimestamp(chainFile, timestamp);
            filesUpdated++;
          }
          onProgress({
            event: "chain_updated",
            directory: id,
            chainLength: chain.length,
          });
        }
      } catch (error) {
        if (isQuotaError(error)) {
          onProgress({
            event: "quota_exhausted",
            directory: id,
            filename,
            imagesGenerated,
          });
          return { imagesGenerated, filesUpdated, stoppedByQuota: true };
        }
        onProgress({
          event: "image_generation_failed",
          directory: id,
          filename,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
  }

  return { imagesGenerated, filesUpdated, stoppedByQuota: false };
};

export const updateFrontmatterTimestamp = (
  filePath: string,
  timestamp: string,
): void => {
  if (!fs.existsSync(filePath)) return;

  let content = fs.readFileSync(filePath, "utf-8");
  const lines = content.split("\n");

  if (lines[0]?.trim() === "---") {
    let endIndex = -1;
    let updatedLineIndex = -1;

    for (let i = 1; i < lines.length; i++) {
      if (lines[i]?.trim() === "---") {
        endIndex = i;
        break;
      }
      if (lines[i]?.match(/^updated:\s/)) {
        updatedLineIndex = i;
      }
    }

    if (endIndex >= 0) {
      if (updatedLineIndex >= 0) {
        lines[updatedLineIndex] = `updated: ${timestamp}`;
      } else {
        lines.splice(endIndex, 0, `updated: ${timestamp}`);
      }
      content = lines.join("\n");
    }
  } else {
    content = `---\nupdated: ${timestamp}\n---\n${content}`;
  }

  fs.writeFileSync(filePath, content, "utf-8");
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
