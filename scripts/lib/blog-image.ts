import fs from "node:fs";
import path from "node:path";

const IMAGE_EXTENSIONS = /\.(jpg|jpeg|png|gif|webp)$/i;
const OBSIDIAN_IMAGE_EMBED = /!\[\[(?:attachments\/)?[^\]]+\.(jpg|jpeg|png|gif|webp)\]\]/i;
const MARKDOWN_IMAGE_EMBED = /!\[[^\]]*\]\([^)]+\.(jpg|jpeg|png|gif|webp)\)/i;
const EXCLUDED_FILES = new Set(["index.md", "AGENTS.md", "IDEAS.md"]);
const DATE_FILENAME_PATTERN = /^(\d{4}-\d{2}-\d{2})/;

export interface ImageGenerationResult {
  readonly skipped: boolean;
  readonly imagePath?: string;
  readonly imageName?: string;
}

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

export const buildImagePrompt = (postContent: string): string =>
  `generate an image to illustrate the following blog post: ${postContent}`;

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

export const generateImageWithGemini: ImageGenerator = async (
  apiKey,
  model,
  prompt,
) => {
  const { GoogleGenAI } = await import("@google/genai");
  const ai = new GoogleGenAI({ apiKey });

  const response = await ai.models.generateImages({
    model,
    prompt,
    config: {
      numberOfImages: 1,
      outputMimeType: "image/jpeg",
    },
  });

  const image = response.generatedImages?.[0];
  if (!image?.image?.imageBytes) {
    throw new Error(
      image?.raiFilteredReason
        ? `Image filtered: ${image.raiFilteredReason}`
        : "No image generated",
    );
  }

  return {
    data: Buffer.from(image.image.imageBytes, "base64"),
    mimeType: image.image.mimeType ?? "image/jpeg",
  };
};

export const processNote = async (
  notePath: string,
  attachmentsDir: string,
  apiKey: string,
  model: string,
  generate: ImageGenerator = generateImageWithGemini,
): Promise<ImageGenerationResult> => {
  const content = fs.readFileSync(notePath, "utf-8");

  if (hasEmbeddedImage(content)) {
    return { skipped: true };
  }

  const title = extractTitle(content);
  if (!title) {
    return { skipped: true };
  }

  const kebabTitle = titleToKebabCase(title);
  if (!kebabTitle) {
    return { skipped: true };
  }

  const prompt = buildImagePrompt(content);
  const { data, mimeType } = await generate(apiKey, model, prompt);

  const extension = mimeTypeToExtension(mimeType);
  const imageName = `${kebabTitle}${extension}`;
  const imagePath = path.join(attachmentsDir, imageName);

  fs.mkdirSync(attachmentsDir, { recursive: true });
  fs.writeFileSync(imagePath, data);

  const updatedContent = insertImageEmbed(content, imageName);
  fs.writeFileSync(notePath, updatedContent, "utf-8");

  return { skipped: false, imagePath, imageName };
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
      if (hasEmbeddedImage(content)) {
        onProgress({ event: "already_has_image", directory: id, filename });
        continue;
      }

      onProgress({
        event: "generating_image",
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

export function updateFrontmatterTimestamp(
  filePath: string,
  timestamp: string,
): void {
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
}
