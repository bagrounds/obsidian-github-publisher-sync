import fs from "node:fs";
import path from "node:path";
import { parseFrontmatter } from "./frontmatter.ts";

export interface BlogPost {
  readonly filename: string;
  readonly date: string;
  readonly title: string;
  readonly body: string;
}

const EXCLUDED_FILES = new Set(["index.md", "AGENTS.md", "IDEAS.md"]);

const isPostFile = (filename: string): boolean =>
  filename.endsWith(".md") && !EXCLUDED_FILES.has(filename);

const parsePostFile = (seriesDir: string) => (filename: string): BlogPost => {
  const content = fs.readFileSync(path.join(seriesDir, filename), "utf-8");
  const { frontmatter, body } = parseFrontmatter(content);
  return {
    filename,
    date: filename.match(/^(\d{4}-\d{2}-\d{2})/)?.[1] ?? "",
    title: frontmatter["title"] ?? filename.replace(/\.md$/, ""),
    body,
  };
};

export const readSeriesPosts = (seriesDir: string): readonly BlogPost[] =>
  !fs.existsSync(seriesDir)
    ? []
    : fs.readdirSync(seriesDir).filter(isPostFile).sort().reverse().map(parsePostFile(seriesDir));

export const readAgentsMd = (seriesDir: string): string => {
  const agentsPath = path.join(seriesDir, "AGENTS.md");
  return fs.existsSync(agentsPath) ? fs.readFileSync(agentsPath, "utf-8") : "";
};

export const readIdeasMd = (seriesDir: string): string => {
  const ideasPath = path.join(seriesDir, "IDEAS.md");
  return fs.existsSync(ideasPath) ? fs.readFileSync(ideasPath, "utf-8") : "";
};
