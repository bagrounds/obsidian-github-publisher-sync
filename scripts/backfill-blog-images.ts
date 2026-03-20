#!/usr/bin/env npx tsx

import path from "node:path";
import { backfillImages } from "./lib/blog-image.ts";

const DEFAULT_IMAGE_MODEL = "gemini-2.0-flash-preview-image-generation";

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

const main = async (): Promise<void> => {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error("❌ GEMINI_API_KEY is required");
    process.exit(1);
  }

  const model = process.env.IMAGE_GEMINI_MODEL ?? DEFAULT_IMAGE_MODEL;
  const repoRoot = path.resolve(import.meta.dirname, "..");
  const attachmentsDir =
    process.env.ATTACHMENTS_DIR ?? path.join(repoRoot, "attachments");

  const directories = [
    { path: path.join(repoRoot, "reflections"), id: "reflections" },
    { path: path.join(repoRoot, "ai-blog"), id: "ai-blog" },
    { path: path.join(repoRoot, "auto-blog-zero"), id: "auto-blog-zero" },
    { path: path.join(repoRoot, "chickie-loo"), id: "chickie-loo" },
  ] as const;

  log({
    event: "backfill_start",
    model,
    attachmentsDir,
    directories: directories.map((d) => d.id),
  });

  const result = await backfillImages({
    directories,
    attachmentsDir,
    apiKey,
    model,
    onProgress: log,
  });

  log({
    event: "backfill_complete",
    imagesGenerated: result.imagesGenerated,
    filesUpdated: result.filesUpdated,
    stoppedByQuota: result.stoppedByQuota,
  });

  if (result.stoppedByQuota) {
    console.log("⚠️ Stopped due to API quota exhaustion. Will resume tomorrow.");
  } else if (result.imagesGenerated === 0) {
    console.log("✅ All posts already have images.");
  } else {
    console.log(`✅ Generated ${result.imagesGenerated} images, updated ${result.filesUpdated} files.`);
  }
};

if (process.argv[1]?.endsWith("backfill-blog-images.ts")) {
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
