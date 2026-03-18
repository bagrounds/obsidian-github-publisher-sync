/**
 * Compare two content directories for parity checking.
 *
 * Usage:
 *   npx tsx scripts/compare-content.ts --dir1 content/ --dir2 content-transformed/
 *
 * Reports files unique to each directory and files with differing content.
 * Useful for verifying that CI-transformed content matches Enveloppe output.
 *
 * @module compare-content
 */

import fs from "node:fs";
import path from "node:path";

// --- Types ---

interface ComparisonResult {
  readonly onlyInDir1: readonly string[];
  readonly onlyInDir2: readonly string[];
  readonly differing: readonly DiffEntry[];
  readonly matching: number;
}

interface DiffEntry {
  readonly file: string;
  readonly dir1Lines: number;
  readonly dir2Lines: number;
  readonly firstDiffLine: number;
  readonly dir1Sample: string;
  readonly dir2Sample: string;
}

// --- File Discovery ---

const findMarkdownFiles = (dir: string, base: string = dir): string[] =>
  fs.existsSync(dir)
    ? fs
        .readdirSync(dir, { withFileTypes: true })
        .flatMap((entry) => {
          const fullPath = path.join(dir, entry.name);
          if (entry.isDirectory() && !entry.name.startsWith(".")) {
            return findMarkdownFiles(fullPath, base);
          }
          return entry.isFile() && entry.name.endsWith(".md")
            ? [path.relative(base, fullPath)]
            : [];
        })
        .sort()
    : [];

// --- Comparison ---

const findFirstDiff = (
  lines1: readonly string[],
  lines2: readonly string[],
): number => {
  const maxLen = Math.max(lines1.length, lines2.length);
  const diffIndex = Array.from({ length: maxLen }, (_, i) => i).findIndex(
    (i) => lines1[i] !== lines2[i],
  );
  return diffIndex >= 0 ? diffIndex + 1 : -1;
};

const compareFiles = (
  file: string,
  dir1: string,
  dir2: string,
): DiffEntry | null => {
  const content1 = fs.readFileSync(path.join(dir1, file), "utf-8");
  const content2 = fs.readFileSync(path.join(dir2, file), "utf-8");

  if (content1 === content2) return null;

  const lines1 = content1.split("\n");
  const lines2 = content2.split("\n");
  const firstDiffLine = findFirstDiff(lines1, lines2);

  return {
    file,
    dir1Lines: lines1.length,
    dir2Lines: lines2.length,
    firstDiffLine,
    dir1Sample: lines1[firstDiffLine - 1] ?? "<missing>",
    dir2Sample: lines2[firstDiffLine - 1] ?? "<missing>",
  };
};

const compareDirectories = (dir1: string, dir2: string): ComparisonResult => {
  const files1 = new Set(findMarkdownFiles(dir1));
  const files2 = new Set(findMarkdownFiles(dir2));

  const onlyInDir1 = [...files1].filter((f) => !files2.has(f));
  const onlyInDir2 = [...files2].filter((f) => !files1.has(f));

  const commonFiles = [...files1].filter((f) => files2.has(f));
  const diffs = commonFiles
    .map((file) => compareFiles(file, dir1, dir2))
    .filter((d): d is DiffEntry => d !== null);

  return {
    onlyInDir1,
    onlyInDir2,
    differing: diffs,
    matching: commonFiles.length - diffs.length,
  };
};

// --- CLI ---

const parseArgs = (args: readonly string[]): { dir1: string; dir2: string } => {
  const dir1Index = args.indexOf("--dir1");
  const dir2Index = args.indexOf("--dir2");

  const dir1 = dir1Index >= 0 ? args[dir1Index + 1] : undefined;
  const dir2 = dir2Index >= 0 ? args[dir2Index + 1] : undefined;

  if (!dir1 || !dir2) {
    console.error(
      "Usage: npx tsx scripts/compare-content.ts --dir1 <dir> --dir2 <dir>",
    );
    process.exit(1);
  }

  return { dir1: dir1!, dir2: dir2! };
};

const printResult = (result: ComparisonResult, dir1: string, dir2: string) => {
  console.log("\n📊 Content Comparison Report\n");

  console.log(`✅ Matching files: ${result.matching}`);

  if (result.onlyInDir1.length > 0) {
    console.log(`\n📁 Only in ${dir1} (${result.onlyInDir1.length}):`);
    result.onlyInDir1.forEach((f) => console.log(`  - ${f}`));
  }

  if (result.onlyInDir2.length > 0) {
    console.log(`\n📁 Only in ${dir2} (${result.onlyInDir2.length}):`);
    result.onlyInDir2.forEach((f) => console.log(`  - ${f}`));
  }

  if (result.differing.length > 0) {
    console.log(`\n⚠️  Differing files (${result.differing.length}):`);
    result.differing.forEach((d) => {
      console.log(`\n  📄 ${d.file}`);
      console.log(`     Lines: ${d.dir1Lines} vs ${d.dir2Lines}`);
      console.log(`     First diff at line ${d.firstDiffLine}:`);
      console.log(`     ${dir1}: "${d.dir1Sample}"`);
      console.log(`     ${dir2}: "${d.dir2Sample}"`);
    });
  }

  const total =
    result.matching +
    result.differing.length +
    result.onlyInDir1.length +
    result.onlyInDir2.length;
  const parity = result.matching / Math.max(total, 1);
  console.log(
    `\n📈 Parity: ${(parity * 100).toFixed(1)}% (${result.matching}/${total})`,
  );
};

// --- Entry Point ---

const main = () => {
  const { dir1, dir2 } = parseArgs(process.argv.slice(2));
  const result = compareDirectories(dir1, dir2);
  printResult(result, dir1, dir2);

  if (
    result.differing.length > 0 ||
    result.onlyInDir1.length > 0 ||
    result.onlyInDir2.length > 0
  ) {
    process.exit(1);
  }
};

main();
