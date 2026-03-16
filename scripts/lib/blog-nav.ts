import fs from "node:fs";
import path from "node:path";

const EXCLUDED_FILES = new Set(["index.md", "AGENTS.md", "IDEAS.md"]);

const isPostFile = (filename: string): boolean =>
  filename.endsWith(".md") && !EXCLUDED_FILES.has(filename);

const listPostFilenames = (dir: string): readonly string[] =>
  fs.existsSync(dir) ? fs.readdirSync(dir).filter(isPostFile).sort() : [];

const stemOf = (filename: string): string => filename.replace(/\.md$/, "");

export const findMostRecentPost = (repoRoot: string, seriesId: string): string | undefined => {
  const rootDir = path.join(repoRoot, seriesId);
  const contentDir = path.join(repoRoot, "content", seriesId);
  const allFilenames = [...new Set([...listPostFilenames(rootDir), ...listPostFilenames(contentDir)])];
  return allFilenames.sort().reverse()[0];
};

export const buildNavLine = (seriesId: string, seriesNavLink: string, previousFilename: string | undefined): string => {
  const prevLink = previousFilename
    ? ` | [[${seriesId}/${stemOf(previousFilename)}|⏮️]]`
    : "";
  return `${seriesNavLink}${prevLink}`;
};

const nextWikilink = (seriesId: string, filename: string): string =>
  `[[${seriesId}/${stemOf(filename)}|⏭️]]`;

const nextMarkdownLink = (filename: string): string =>
  `[⏭️](./${filename})`;

const isWikilinkNavLine = (line: string): boolean => line.startsWith("[[");

const hasPipeSeparator = (line: string): boolean => line.includes(" | ");

const appendNextToNavLine = (navLine: string, seriesId: string, newFilename: string): string => {
  const trimmed = navLine.replace(/\s+$/, "");
  const link = isWikilinkNavLine(trimmed)
    ? nextWikilink(seriesId, newFilename)
    : nextMarkdownLink(newFilename);
  const separator = hasPipeSeparator(trimmed) ? " " : " | ";
  return `${trimmed}${separator}${link}`;
};

const findNavLineIndex = (lines: readonly string[]): number | undefined => {
  const h1Index = lines.findIndex((line) => line.startsWith("# "));
  if (h1Index <= 0) return undefined;
  const candidate = h1Index - 1;
  const line = lines[candidate]?.trim() ?? "";
  return (line.startsWith("[") || line.startsWith("[[")) ? candidate : undefined;
};

export const addNextLinkToContent = (content: string, seriesId: string, newFilename: string): string | undefined => {
  const lines = content.split("\n");
  const navIndex = findNavLineIndex(lines);
  if (navIndex === undefined) return undefined;
  const currentNav = lines[navIndex] ?? "";
  if (currentNav.includes("⏭️")) return undefined;
  const updatedLines = [...lines];
  updatedLines[navIndex] = appendNextToNavLine(currentNav, seriesId, newFilename);
  return updatedLines.join("\n");
};

export const readPreviousPostContent = (repoRoot: string, seriesId: string, filename: string): string | undefined => {
  const rootPath = path.join(repoRoot, seriesId, filename);
  const contentPath = path.join(repoRoot, "content", seriesId, filename);
  const candidates = [rootPath, contentPath];
  const filePath = candidates.find((p) => fs.existsSync(p));
  return filePath ? fs.readFileSync(filePath, "utf-8") : undefined;
};

export const updatePreviousPost = (
  repoRoot: string,
  seriesId: string,
  previousFilename: string,
  newFilename: string,
): string | undefined => {
  const content = readPreviousPostContent(repoRoot, seriesId, previousFilename);
  if (!content) return undefined;
  const updated = addNextLinkToContent(content, seriesId, newFilename);
  if (!updated) return undefined;
  const outputPath = path.join(repoRoot, seriesId, previousFilename);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, updated, "utf-8");
  return outputPath;
};
