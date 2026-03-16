import fs from "node:fs";
import path from "node:path";
import { parseFrontmatter } from "./frontmatter.ts";

export interface BookEntry {
  readonly filename: string;
  readonly title: string;
}

const isBookFile = (filename: string): boolean =>
  filename.endsWith(".md") && filename !== "index.md";

const parseBookEntry = (booksDir: string) => (filename: string): BookEntry => {
  const content = fs.readFileSync(path.join(booksDir, filename), "utf-8");
  const { frontmatter } = parseFrontmatter(content);
  return {
    filename,
    title: frontmatter["title"] ?? filename.replace(/\.md$/, ""),
  };
};

export const readBookCatalog = (booksDir: string): readonly BookEntry[] =>
  !fs.existsSync(booksDir)
    ? []
    : fs.readdirSync(booksDir).filter(isBookFile).sort().map(parseBookEntry(booksDir));

const stemOf = (filename: string): string => filename.replace(/\.md$/, "");

export const formatBookCatalogForPrompt = (catalog: readonly BookEntry[]): string =>
  catalog.length === 0
    ? ""
    : catalog.map((b) => `- ${stemOf(b.filename)} | ${b.title}`).join("\n");

export const buildBookRecommendationsPrompt = (catalog: readonly BookEntry[]): string => {
  if (catalog.length === 0) return "";
  const catalogText = formatBookCatalogForPrompt(catalog);
  return `

## 📚 Book Recommendations Instructions

🔚 Near the end of your post (before the closing question), include a book recommendations section.
📖 Pick 3-5 books from the catalog below that are relevant to today's topic.
✅ Use ONLY books from this catalog — do not invent book titles or filenames.
📝 Use this EXACT format:

## 📚 Book Recommendations

### ✨ Similar

- [[books/FILENAME_STEM|EMOJI_TITLE]] by AUTHOR

### 🧠 Deeper Exploration

- [[books/FILENAME_STEM|EMOJI_TITLE]] by AUTHOR

📋 Available books (FILENAME_STEM | EMOJI_TITLE):
${catalogText}`;
};
