/**
 * Vault content transformation.
 *
 * Transforms raw Obsidian vault markdown files into the format expected
 * by this repository's Quartz build. Currently implements a subset of
 * Enveloppe's conversion pipeline:
 *
 * - [[wikilinks]] → [markdown](links)
 * - Hard line breaks (trailing two spaces on every line)
 * - Filter by share: true frontmatter
 *
 * Not yet implemented (see MIGRATION.md for full Enveloppe feature list):
 * - Dataview query rendering
 * - Embed baking (transclusion inlining)
 * - Inline tag → frontmatter promotion
 * - Text replacements
 * - Folder note renaming
 *
 * All exported functions are pure (no I/O side effects).
 *
 * @module vault-transform
 */

import path from "node:path";

// --- Types ---

export interface WikilinkParts {
  readonly isEmbed: boolean;
  readonly filePath: string | null;
  readonly heading: string | null;
  readonly alias: string | null;
}

// --- Constants ---

const ASSET_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".svg",
  ".webp",
  ".bmp",
  ".ico",
  ".tiff",
  ".mp4",
  ".webm",
  ".ogv",
  ".mov",
  ".mp3",
  ".wav",
  ".ogg",
  ".m4a",
  ".flac",
  ".pdf",
  ".excalidraw",
]);

const IMAGE_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".svg",
  ".webp",
  ".bmp",
  ".ico",
  ".tiff",
]);

const WIKILINK_REGEX = /!?\[\[([^\[\]]+)\]\]/g;

// --- Pure Functions: Wikilink Parsing ---

export const parseWikilink = (raw: string): WikilinkParts => {
  const isEmbed = raw.startsWith("!");
  const inner = raw.slice(isEmbed ? 3 : 2, -2);

  const pipeIndex = inner.indexOf("|");
  const pathAndHeading = pipeIndex >= 0 ? inner.slice(0, pipeIndex) : inner;
  const alias = pipeIndex >= 0 ? inner.slice(pipeIndex + 1) : null;

  const hashIndex = pathAndHeading.indexOf("#");
  const filePath =
    hashIndex >= 0
      ? pathAndHeading.slice(0, hashIndex) || null
      : pathAndHeading || null;
  const heading = hashIndex >= 0 ? pathAndHeading.slice(hashIndex + 1) : null;

  return { isEmbed, filePath, heading, alias };
};

// --- Pure Functions: Path Resolution ---

const isAssetPath = (filePath: string): boolean =>
  ASSET_EXTENSIONS.has(path.posix.extname(filePath).toLowerCase());

export const resolveRelativePath = (
  targetPath: string,
  sourceFileDir: string,
): string => {
  const normalized = targetPath.startsWith("/")
    ? targetPath.slice(1)
    : targetPath;
  const relative = path.posix.relative(sourceFileDir || ".", normalized);
  const withPrefix = relative.startsWith("..") ? relative : `./${relative}`;
  const extension = isAssetPath(normalized) ? "" : ".md";
  return `${withPrefix}${extension}`;
};

// --- Pure Functions: Display Text ---

export const buildDisplayText = (parts: WikilinkParts): string => {
  if (parts.alias != null) return parts.alias;

  if (parts.filePath && parts.heading != null)
    return `${parts.filePath} > ${parts.heading}`;

  if (parts.heading != null) return parts.heading;

  if (parts.filePath) return path.posix.basename(parts.filePath);

  return "";
};

// --- Pure Functions: Heading Encoding ---

export const encodeHeading = (heading: string): string =>
  heading.replaceAll(" ", "%20");

// --- Pure Functions: Wikilink Conversion ---

const convertImageEmbed = (
  parts: WikilinkParts,
  sourceFileDir: string,
): string => {
  const resolved = resolveRelativePath(parts.filePath!, sourceFileDir);
  const altText = parts.alias ?? path.posix.basename(parts.filePath!);
  return `![${altText}](${resolved})`;
};

const convertLinkWithPath = (
  parts: WikilinkParts,
  sourceFileDir: string,
): string => {
  if (
    parts.filePath!.startsWith("http://") ||
    parts.filePath!.startsWith("https://")
  ) {
    return `[${buildDisplayText(parts)}](${parts.filePath!})`;
  }

  const resolved = resolveRelativePath(parts.filePath!, sourceFileDir);
  const anchor =
    parts.heading != null ? `#${encodeHeading(parts.heading)}` : "";
  return `[${buildDisplayText(parts)}](${resolved}${anchor})`;
};

const convertHeadingOnly = (parts: WikilinkParts): string =>
  `[${buildDisplayText(parts)}](#${encodeHeading(parts.heading!)})`;

export const convertWikilink = (raw: string, sourceFileDir: string): string => {
  const parts = parseWikilink(raw);

  if (parts.isEmbed && parts.filePath) {
    const ext = path.posix.extname(parts.filePath).toLowerCase();
    if (IMAGE_EXTENSIONS.has(ext))
      return convertImageEmbed(parts, sourceFileDir);
    if (parts.filePath) return convertLinkWithPath(parts, sourceFileDir);
  }

  if (parts.filePath) return convertLinkWithPath(parts, sourceFileDir);

  if (parts.heading != null) return convertHeadingOnly(parts);

  return raw;
};

// --- Pure Functions: Line & Body Transformation ---

export const transformWikilinksInLine = (
  line: string,
  sourceFileDir: string,
): string =>
  line
    .split(/(`[^`]+`)/g)
    .map((segment, i) =>
      i % 2 === 0
        ? segment.replace(WIKILINK_REGEX, (match) =>
            convertWikilink(match, sourceFileDir),
          )
        : segment,
    )
    .join("");

export const transformBody = (body: string, sourceFileDir: string): string => {
  let inCodeBlock = false;
  return body
    .split("\n")
    .map((line) => {
      if (line.trimStart().startsWith("```")) {
        inCodeBlock = !inCodeBlock;
        return line;
      }
      return inCodeBlock ? line : transformWikilinksInLine(line, sourceFileDir);
    })
    .join("\n");
};

// --- Pure Functions: Hard Line Breaks ---

export const addHardBreaks = (text: string): string =>
  text
    .split("\n")
    .map((line) => line.trimEnd() + "  ")
    .join("\n");

// --- Pure Functions: Frontmatter ---

export const splitFrontmatter = (
  content: string,
): { frontmatter: string; body: string } => {
  const lines = content.split("\n");

  if (lines[0]?.trim() !== "---") return { frontmatter: "", body: content };

  const endIndex = lines.findIndex((line, i) => i > 0 && line.trim() === "---");

  if (endIndex < 0) return { frontmatter: "", body: content };

  return {
    frontmatter: lines.slice(0, endIndex + 1).join("\n"),
    body: lines.slice(endIndex + 1).join("\n"),
  };
};

export const hasShareTrue = (frontmatterBlock: string): boolean =>
  /^share:\s*true\s*$/m.test(frontmatterBlock);

// --- Pure Functions: Full File Transformation ---

export const transformFile = (
  content: string,
  relativeFilePath: string,
): string | null => {
  const { frontmatter, body } = splitFrontmatter(content);

  if (!hasShareTrue(frontmatter)) return null;

  const sourceFileDir = path.posix.dirname(relativeFilePath);
  const transformedBody = transformBody(body, sourceFileDir);
  const withHardBreaks = addHardBreaks(transformedBody);

  return frontmatter ? `${frontmatter}\n${withHardBreaks}` : withHardBreaks;
};
