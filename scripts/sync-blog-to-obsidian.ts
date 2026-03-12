/**
 * Sync files to the Obsidian vault.
 *
 * A general-purpose tool for copying any local file(s) to any location
 * in the Obsidian vault. Supports both ad-hoc single-file copies and
 * batch blog-series syncing.
 *
 * The content/ directory is a ONE-WAY sync from Obsidian mobile.
 * We NEVER write to content/ — instead we write to the Obsidian vault
 * via headless sync, and the next mobile publish brings it to content/.
 *
 * Modes:
 *   1. File mode: copy one or more local files to specified vault paths.
 *   2. Series mode: sync an entire blog series (posts + auto-generated index).
 *   3. Default: sync ALL registered blog series.
 *
 * Usage:
 *   # Copy a single file to a specific vault path
 *   npx tsx scripts/sync-blog-to-obsidian.ts --file ai-blog/my-post.md --vault-path ai-blog/my-post.md
 *
 *   # Copy multiple files
 *   npx tsx scripts/sync-blog-to-obsidian.ts \
 *     --file ai-blog/post1.md --vault-path ai-blog/post1.md \
 *     --file ai-blog/post2.md --vault-path ai-blog/post2.md
 *
 *   # Sync a blog series (copies posts + regenerates index)
 *   npx tsx scripts/sync-blog-to-obsidian.ts --series auto-blog-zero
 *
 *   # Sync all registered blog series
 *   npx tsx scripts/sync-blog-to-obsidian.ts
 *
 *   # Dry run (preview without writing)
 *   npx tsx scripts/sync-blog-to-obsidian.ts --file foo.md --vault-path bar/foo.md --dry-run
 *
 * Environment variables:
 *   OBSIDIAN_AUTH_TOKEN      - Required. Obsidian API token.
 *   OBSIDIAN_VAULT_NAME      - Required. Vault identifier.
 *   OBSIDIAN_VAULT_PASSWORD   - Optional. Vault encryption password.
 *   OBSIDIAN_VAULT_CACHE_DIR  - Optional. Cache dir for warm sync.
 *
 * @module sync-blog-to-obsidian
 */

import fs from "node:fs";
import path from "node:path";

import {
  BLOG_SERIES,
  readSeriesPosts,
  generateSeriesIndex,
} from "./lib/blog-series.ts";
import type { BlogSeriesConfig } from "./lib/blog-series.ts";
import { syncObsidianVault, pushObsidianVault } from "./lib/obsidian-sync.ts";

// --- Types ---

interface FileCopySpec {
  /** Local file path (relative to repo root or absolute). */
  readonly localPath: string;
  /** Destination path inside the Obsidian vault (relative to vault root). */
  readonly vaultPath: string;
}

interface SyncArgs {
  /** Ad-hoc files to copy (file mode). */
  readonly files: readonly FileCopySpec[];
  /** Blog series to sync (series mode). */
  readonly seriesIds: readonly string[];
  /** Preview without writing. */
  readonly dryRun: boolean;
}

// --- Argument Parsing ---

function parseArgs(): SyncArgs {
  const args = process.argv.slice(2);
  const files: FileCopySpec[] = [];
  const seriesIds: string[] = [];
  let dryRun = false;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--file" && args[i + 1]) {
      const localPath = args[++i] as string;
      // The next arg must be --vault-path
      if (args[i + 1] !== "--vault-path" || !args[i + 2]) {
        console.error(`❌ --file must be followed by --vault-path <path>`);
        process.exit(1);
      }
      i++; // skip --vault-path
      const vaultPath = args[++i] as string;
      files.push({ localPath, vaultPath });
    } else if (arg === "--series" && args[i + 1]) {
      seriesIds.push(args[++i] as string);
    } else if (arg === "--dry-run") {
      dryRun = true;
    }
  }

  // Validate series IDs
  for (const id of seriesIds) {
    if (!BLOG_SERIES.has(id)) {
      const available = [...BLOG_SERIES.keys()].join(", ");
      console.error(`❌ Unknown series: ${id}. Available: ${available}`);
      process.exit(1);
    }
  }

  // Default: if no files and no series specified, sync all series
  if (files.length === 0 && seriesIds.length === 0) {
    seriesIds.push(...BLOG_SERIES.keys());
  }

  return { files, seriesIds, dryRun };
}

// --- File Copy Logic ---

/**
 * Copy a single file into the Obsidian vault.
 * Creates parent directories as needed. Only writes if content differs.
 * Returns true if the file was written (new or changed).
 */
export function copyFileToVault(
  localPath: string,
  vaultPath: string,
  vaultDir: string,
): boolean {
  if (!fs.existsSync(localPath)) {
    console.error(`  ❌ Local file not found: ${localPath}`);
    return false;
  }

  const dest = path.join(vaultDir, vaultPath);

  // Ensure parent directory exists
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  const localContent = fs.readFileSync(localPath, "utf-8");

  // Only write if the file is new or different
  if (fs.existsSync(dest)) {
    const vaultContent = fs.readFileSync(dest, "utf-8");
    if (vaultContent === localContent) {
      return false;
    }
  }

  fs.writeFileSync(dest, localContent, "utf-8");
  return true;
}

// --- Series Sync Logic ---

/**
 * Sync a single blog series from repo to Obsidian vault.
 * Copies all posts and regenerates the series index.
 * Returns the number of files written/updated.
 */
export function syncSeries(
  series: BlogSeriesConfig,
  repoRoot: string,
  vaultDir: string,
): number {
  const repoSeriesDir = path.join(repoRoot, series.id);

  if (!fs.existsSync(repoSeriesDir)) {
    console.log(`  ℹ️  No posts yet in ${series.id}/`);
    return 0;
  }

  const vaultSeriesDir = path.join(vaultDir, series.id);
  fs.mkdirSync(vaultSeriesDir, { recursive: true });

  const posts = readSeriesPosts(repoSeriesDir);
  let filesWritten = 0;

  for (const post of posts) {
    const srcPath = path.join(repoSeriesDir, post.filename);
    const written = copyFileToVault(srcPath, `${series.id}/${post.filename}`, vaultDir);
    if (written) {
      console.log(`  📄 ${post.filename}`);
      filesWritten++;
    }
  }

  // Generate/update the index file
  const indexContent = generateSeriesIndex(series, posts);
  const indexPath = path.join(vaultSeriesDir, "index.md");
  const existingIndex = fs.existsSync(indexPath) ? fs.readFileSync(indexPath, "utf-8") : "";

  if (existingIndex !== indexContent) {
    fs.writeFileSync(indexPath, indexContent, "utf-8");
    console.log(`  📋 index.md (${posts.length} posts)`);
    filesWritten++;
  }

  return filesWritten;
}

// --- Main ---

async function syncToObsidian(): Promise<void> {
  const config = parseArgs();
  const repoRoot = path.resolve(import.meta.dirname, "..");

  console.log(`📦 Sync to Obsidian vault`);
  console.log(`📅 ${new Date().toISOString()}`);

  if (config.files.length > 0) {
    console.log(`📄 Files: ${config.files.length} file(s) to copy`);
  }
  if (config.seriesIds.length > 0) {
    console.log(`📂 Series: ${config.seriesIds.join(", ")}`);
  }
  console.log();

  // --- Dry run ---
  if (config.dryRun) {
    console.log("🔍 DRY RUN — showing what would be synced:\n");

    for (const file of config.files) {
      const absLocal = path.isAbsolute(file.localPath)
        ? file.localPath
        : path.join(repoRoot, file.localPath);
      const exists = fs.existsSync(absLocal);
      console.log(`  📄 ${file.localPath} → vault:${file.vaultPath} ${exists ? "✅" : "❌ NOT FOUND"}`);
    }

    for (const seriesId of config.seriesIds) {
      const series = BLOG_SERIES.get(seriesId)!;
      const seriesDir = path.join(repoRoot, series.id);
      const posts = readSeriesPosts(seriesDir);
      console.log(`  ${series.icon} ${series.name}: ${posts.length} post(s)`);
      for (const post of posts) {
        console.log(`    📄 ${post.filename} — ${post.title}`);
      }
    }
    return;
  }

  // --- Validate credentials ---
  const authToken = process.env.OBSIDIAN_AUTH_TOKEN;
  const vaultName = process.env.OBSIDIAN_VAULT_NAME;
  if (!authToken || !vaultName) {
    console.error("❌ OBSIDIAN_AUTH_TOKEN and OBSIDIAN_VAULT_NAME are required");
    process.exit(1);
  }

  // --- Pull vault ---
  console.log("📥 Pulling Obsidian vault...");
  const vaultDir = await syncObsidianVault({
    authToken,
    vaultName,
    vaultPassword: process.env.OBSIDIAN_VAULT_PASSWORD || undefined,
  });
  console.log(`📂 Vault at: ${vaultDir}\n`);

  let totalFiles = 0;

  // --- File mode ---
  if (config.files.length > 0) {
    console.log("📄 Copying files...");
    for (const file of config.files) {
      const absLocal = path.isAbsolute(file.localPath)
        ? file.localPath
        : path.join(repoRoot, file.localPath);

      const written = copyFileToVault(absLocal, file.vaultPath, vaultDir);
      if (written) {
        console.log(`  ✅ ${file.localPath} → vault:${file.vaultPath}`);
        totalFiles++;
      } else if (fs.existsSync(absLocal)) {
        console.log(`  ⏭️  ${file.localPath} → already in sync`);
      }
    }
    console.log();
  }

  // --- Series mode ---
  for (const seriesId of config.seriesIds) {
    const series = BLOG_SERIES.get(seriesId)!;
    console.log(`${series.icon} Syncing ${series.name}...`);
    const count = syncSeries(series, repoRoot, vaultDir);
    totalFiles += count;
    if (count === 0) {
      console.log(`  ✅ Already in sync`);
    }
  }

  // --- Push ---
  if (totalFiles > 0) {
    console.log(`\n📤 Pushing ${totalFiles} file(s) to Obsidian vault...`);
    await pushObsidianVault(vaultDir, { authToken });
    console.log("✅ Obsidian vault updated!");
  } else {
    console.log("\n✅ Everything already in sync — nothing to push.");
  }

  // --- Verify ---
  console.log("\n🔍 Verification:");
  for (const file of config.files) {
    const dest = path.join(vaultDir, file.vaultPath);
    const exists = fs.existsSync(dest);
    console.log(`  📄 vault:${file.vaultPath} ${exists ? "✅" : "❌ MISSING"}`);
  }
  for (const seriesId of config.seriesIds) {
    const series = BLOG_SERIES.get(seriesId)!;
    const vaultSeriesDir = path.join(vaultDir, series.id);
    if (fs.existsSync(vaultSeriesDir)) {
      const files = fs.readdirSync(vaultSeriesDir).filter((f) => f.endsWith(".md"));
      console.log(`  ${series.icon} ${series.name}: ${files.length} file(s) in vault`);
    } else {
      console.log(`  ${series.icon} ${series.name}: ⚠️  directory not in vault`);
    }
  }

  console.log("\n🎉 Sync complete!");
}

// --- Entry Point ---

const isMainModule = process.argv[1]?.endsWith("sync-blog-to-obsidian.ts");
if (isMainModule) {
  syncToObsidian().catch((error) => {
    console.error(`❌ Fatal error: ${error instanceof Error ? error.message : error}`);
    if (error instanceof Error && error.stack) {
      console.error(error.stack);
    }
    process.exit(1);
  });
}

export { syncToObsidian };
