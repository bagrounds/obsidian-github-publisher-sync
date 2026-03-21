#!/usr/bin/env npx tsx

import path from "node:path";
import {
  processNote,
  resolveImageProvider,
} from "./lib/blog-image.ts";

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

const parseArgs = (
  argv: readonly string[],
): { notePath: string } => {
  const args = argv.slice(2);
  const flagValue = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    return idx >= 0 && idx + 1 < args.length
      ? (args[idx + 1] as string)
      : undefined;
  };

  const notePath = flagValue("--note") ?? args.find((a) => !a.startsWith("--")) ?? "";

  if (!notePath) {
    console.error("Usage: generate-blog-image.ts --note <path>");
    process.exit(1);
  }

  return { notePath };
};

const main = async (): Promise<void> => {
  const config = parseArgs(process.argv);
  const provider = resolveImageProvider(process.env as Record<string, string | undefined>);

  const repoRoot = path.resolve(import.meta.dirname, "..");
  const attachmentsDir =
    process.env.ATTACHMENTS_DIR ?? path.join(repoRoot, "attachments");

  const notePath = path.isAbsolute(config.notePath)
    ? config.notePath
    : path.resolve(config.notePath);

  log({
    event: "generate_image_start",
    notePath,
    model: provider.model,
    attachmentsDir,
  });

  const result = await processNote(
    notePath,
    attachmentsDir,
    provider.apiKey,
    provider.model,
    provider.generator,
    provider.describePrompt,
  );

  if (result.skipped) {
    log({ event: "image_skipped", notePath, reason: "already exists or no title" });
  } else {
    log({
      event: "image_generated",
      notePath,
      imagePath: result.imagePath,
      imageName: result.imageName,
    });
  }
};

if (process.argv[1]?.endsWith("generate-blog-image.ts")) {
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

export { main };
