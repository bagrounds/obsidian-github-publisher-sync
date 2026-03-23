#!/usr/bin/env npx tsx

import path from "node:path";
import { backfillImages, resolveImageProviders } from "./lib/blog-image.ts";

const log = (data: Record<string, unknown>): void =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...data }));

const main = async (): Promise<void> => {
  const providers = resolveImageProviders(process.env as Record<string, string | undefined>);
  const primary = providers[0]!;
  const fallbacks = providers.slice(1);

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
    providers: providers.map((p) => ({ name: p.name, model: p.model })),
    attachmentsDir,
    directories: directories.map((d) => d.id),
  });

  const result = await backfillImages({
    directories,
    attachmentsDir,
    apiKey: primary.apiKey,
    model: primary.model,
    generate: primary.generator,
    describePrompt: primary.describePrompt,
    providerName: primary.name,
    fallbackProviders: fallbacks,
    onProgress: log,
  });

  log({
    event: "backfill_complete",
    imagesGenerated: result.imagesGenerated,
    filesUpdated: result.filesUpdated,
    stoppedByQuota: result.stoppedByQuota,
  });

  if (result.stoppedByQuota) {
    console.log("⚠️ Stopped due to API quota exhaustion across all providers. Will resume tomorrow.");
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
