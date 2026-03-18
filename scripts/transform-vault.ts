/**
 * Transform raw Obsidian vault files into Quartz-compatible content.
 *
 * Usage:
 *   npx tsx scripts/transform-vault.ts --vault vault/ --output content-transformed/
 *
 * Reads all .md files from the vault directory, applies Enveloppe-equivalent
 * transformations (wikilink conversion, hard breaks), and writes shareable
 * files to the output directory.
 *
 * @module transform-vault
 */

import fs from "node:fs";
import path from "node:path";

import { transformFile } from "./lib/vault-transform.ts";

// --- CLI Argument Parsing ---

interface TransformOptions {
  readonly vaultDir: string;
  readonly outputDir: string;
}

const parseArgs = (args: readonly string[]): TransformOptions => {
  const vaultIndex = args.indexOf("--vault");
  const outputIndex = args.indexOf("--output");

  const vaultDir = vaultIndex >= 0 ? args[vaultIndex + 1] : undefined;
  const outputDir = outputIndex >= 0 ? args[outputIndex + 1] : undefined;

  if (!vaultDir || !outputDir) {
    console.error(
      "Usage: npx tsx scripts/transform-vault.ts --vault <dir> --output <dir>",
    );
    process.exit(1);
  }

  return { vaultDir: vaultDir!, outputDir: outputDir! };
};

// --- File Discovery ---

const findMarkdownFiles = (dir: string, base: string = dir): string[] =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory() && !entry.name.startsWith(".")) {
      return findMarkdownFiles(fullPath, base);
    }
    return entry.isFile() && entry.name.endsWith(".md")
      ? [path.relative(base, fullPath)]
      : [];
  });

// --- Main ---

interface TransformResult {
  readonly transformed: number;
  readonly skipped: number;
}

type FileOutcome = "transformed" | "skipped";

const processFile = (
  relativePath: string,
  vaultDir: string,
  outputDir: string,
): FileOutcome => {
  const sourcePath = path.join(vaultDir, relativePath);
  const content = fs.readFileSync(sourcePath, "utf-8");
  const posixPath = relativePath.split(path.sep).join(path.posix.sep);
  const result = transformFile(content, posixPath);

  if (result === null) return "skipped";

  const outputPath = path.join(outputDir, relativePath);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, result, "utf-8");
  console.log(`  ✅ ${relativePath}`);
  return "transformed";
};

const transformVault = (options: TransformOptions): TransformResult => {
  const { vaultDir, outputDir } = options;

  if (!fs.existsSync(vaultDir)) {
    console.error(`Vault directory not found: ${vaultDir}`);
    process.exit(1);
  }

  const files = findMarkdownFiles(vaultDir);
  console.log(`Found ${files.length} markdown files in ${vaultDir}`);

  const outcomes = files.map((f) => processFile(f, vaultDir, outputDir));
  const transformed = outcomes.filter((o) => o === "transformed").length;
  const skipped = outcomes.filter((o) => o === "skipped").length;

  console.log(
    `\nDone: ${transformed} transformed, ${skipped} skipped (no share: true)`,
  );
  return { transformed, skipped };
};

// --- Entry Point ---

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  transformVault(options);
};

main();
