#!/usr/bin/env npx tsx
/**
 * Internal Linking CLI — BFS-driven wikilink insertion.
 *
 * Usage:
 *   npx tsx scripts/internal-linking.ts [--max-files N] [--dry-run] [--model MODEL] [--content-dir DIR]
 *
 * Environment:
 *   GEMINI_API_KEY   Optional. Gemini API key for AI identification of book references.
 *   LINKING_MODEL    Optional. Override the Gemini model (default: gemini-3.1-flash-lite-preview).
 *
 * The --content-dir flag specifies where to read/write content files. In production,
 * this points to the Obsidian vault directory (pulled via obsidian-headless). For dry
 * runs and local testing, it defaults to the repo's content/ directory.
 *
 * @module internal-linking-cli
 */

import path from "node:path";
import { run, DEFAULT_LINKING_MODEL, type LinkingConfig } from "./lib/internal-linking.ts";

const DEFAULT_MAX_FILES = 10;

interface CliArgs {
  readonly maxFiles: number;
  readonly dryRun: boolean;
  readonly model: string;
  readonly contentDir: string | undefined;
}

const parseArgs = (argv: readonly string[]): CliArgs => {
  const args = argv.slice(2);

  const flagValue = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    return idx >= 0 && idx + 1 < args.length ? (args[idx + 1] as string) : undefined;
  };

  const maxFiles = parseInt(flagValue("--max-files") ?? `${DEFAULT_MAX_FILES}`, 10);
  const dryRun = args.includes("--dry-run");
  const model =
    flagValue("--model") ??
    process.env.LINKING_MODEL ??
    DEFAULT_LINKING_MODEL;
  const contentDir = flagValue("--content-dir");

  return { maxFiles: Number.isNaN(maxFiles) ? DEFAULT_MAX_FILES : maxFiles, dryRun, model, contentDir };
};

const main = async (): Promise<void> => {
  const args = parseArgs(process.argv);
  const contentDir = args.contentDir
    ? path.resolve(args.contentDir)
    : path.resolve(import.meta.dirname, "..", "content");
  const apiKey = process.env.GEMINI_API_KEY;

  const config: LinkingConfig = {
    contentDir,
    maxFiles: args.maxFiles,
    apiKey,
    model: args.model,
    dryRun: args.dryRun,
  };

  console.log(
    JSON.stringify({
      event: "cli_start",
      maxFiles: args.maxFiles,
      dryRun: args.dryRun,
      model: args.model,
      contentDir,
      hasApiKey: !!apiKey,
    }),
  );

  const result = await run(config);

  console.log(
    JSON.stringify({
      event: "cli_complete",
      filesVisited: result.filesVisited,
      filesModified: result.filesModified,
      filesSkipped: result.filesSkipped,
      totalLinksAdded: result.totalLinksAdded,
    }),
  );

  // Output modified files for downstream use
  const modifiedFiles = result.fileResults
    .filter((r) => r.modified)
    .map((r) => r.relativePath);

  if (modifiedFiles.length > 0) {
    console.log(
      JSON.stringify({
        event: "modified_files",
        files: modifiedFiles,
      }),
    );
  }
};

if (process.argv[1]?.endsWith("internal-linking.ts")) {
  main().catch((error) => {
    console.error(
      JSON.stringify({
        event: "fatal_error",
        message: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      }),
    );
    process.exit(1);
  });
}

export { parseArgs };
