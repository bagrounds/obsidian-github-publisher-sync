# Build Speed Optimization Research

## Current State Analysis

### Build Metrics (Baseline - CI Environment)
- **1,866 Markdown files**
- **5,653 total output files** (HTML pages, OG images, assets, etc.)
- **Total CI build time: ~12 minutes** (observed from GitHub Actions workflow runs)
- **Quartz build step: ~11.5 minutes** (20:52:41 to 21:04:20 in recent runs)
- **OG image generation: 1,866 images totaling ~100MB**

### GitHub Actions Workflow Configuration

**File:** `.github/workflows/deploy.yml`

```yaml
name: Deploy Quartz site to GitHub Pages

on:
  push:
    branches:
      - main

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    container:
      image: node:20-bullseye-slim
    steps:
      - name: Install git
        run: |
          apt-get update
          apt-get install -y git

      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # Fetch all history

      - name: Configure Git
        run: |
          git config --global --add safe.directory "$GITHUB_WORKSPACE"
          git config --global user.email "github-actions[bot]@users.noreply.github.com"
          git config --global user.name "github-actions[bot]"

      - name: Cache Node Modules
        id: cache
        uses: actions/cache@v4
        with:
          path: node_modules
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Install Dependencies (if cache is not hit)
        if: ${{ steps.cache.outputs.cache-hit != 'true' }}
        run: npm ci

      - name: Build Quartz
        run: npx quartz build

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: public

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

**Key observations:**
1. Node modules are cached, but the `public/` output folder is NOT cached
2. The build always regenerates ALL OG images from scratch
3. The build runs `npx quartz build` which calls `rimraf(path.join(output, "*"))` to delete the entire `public/` directory before building

### Build Pipeline Overview

The Quartz build process consists of three main phases:

1. **Transpilation** (~3 seconds): Uses esbuild to transpile the Quartz configuration and build scripts
2. **Markdown Parsing** (~30 seconds): Converts markdown files to HTML AST using unified/remark/rehype pipelines
3. **Emission** (~11 minutes): Generates output files including HTML pages, OG images, sitemap, RSS, etc.

### Code Architecture

```
quartz/
├── cli/handlers.js        # Main entry point for build command
├── build.ts               # Core build orchestration (line 70: rimraf deletes public/)
├── processors/
│   ├── parse.ts          # Markdown parsing with worker threads
│   ├── filter.ts         # Content filtering
│   └── emit.ts           # Emission orchestration
├── plugins/
│   ├── transformers/     # Markdown and HTML transformers
│   ├── filters/          # Content filters
│   └── emitters/         # Output generators (ContentPage, OgImages, etc.)
│       └── ogImage.tsx   # OG image generation (PRIMARY BOTTLENECK)
├── util/
│   └── og.tsx            # Font fetching and image template
└── worker.ts             # Worker thread implementation

.github/workflows/
└── deploy.yml            # GitHub Actions CI/CD workflow
```

---

## Identified Bottleneck: OG Image Generation

**Location:** `quartz/plugins/emitters/ogImage.tsx`

The OG image emitter is the primary build bottleneck, consuming approximately 10+ minutes of the 11.5-minute build:

### How OG Images Are Generated

1. **Font Loading** (`quartz/util/og.tsx:17-66`):
   - Fonts are fetched from Google Fonts on first run
   - Fonts are cached locally in `.quartz-cache/fonts/`
   - Subsequent builds skip font fetching

2. **Image Generation** (`ogImage.tsx:68-101`):
   ```typescript
   async function processOgImage(ctx, fileData, fonts, fullOptions) {
     // Extract content data that affects the image
     const title = fileData.frontmatter?.title ?? "Untitled"
     const description = fileData.frontmatter?.description ?? fileData.description
     
     // Generate SVG using Satori
     const stream = await generateSocialImage({title, description, fonts, cfg, fileData}, fullOptions)
     
     // Write to public/{slug}-og-image.webp
     return write({ctx, content: stream, slug: `${slug}-og-image`, ext: ".webp"})
   }
   ```

3. **Sequential Processing** (`ogImage.tsx:112-121`):
   ```typescript
   async *emit(ctx, content, _resources) {
     const fonts = await getSatoriFonts(headerFont, bodyFont)
     
     for (const [_tree, vfile] of content) {
       if (vfile.data.frontmatter?.socialImage !== undefined) continue
       yield processOgImage(ctx, vfile.data, fonts, fullOptions)  // Sequential!
     }
   }
   ```

4. **Image Content Factors** (`quartz/util/og.tsx:173-365`):
   The OG image template uses these data fields:
   - `title` - from frontmatter
   - `description` - from frontmatter or generated
   - `date` - modified/created date
   - `readingTime` - calculated from `fileData.text`
   - `tags` - first 3 tags from frontmatter
   - Config theme colors (from `quartz.config.ts`)
   - Site icon (`quartz/static/icon.png`)

### Why Builds Delete Output First

**Location:** `quartz/build.ts:68-71`
```typescript
const release = await mut.acquire()
perf.addEvent("clean")
await rimraf(path.join(output, "*"), { glob: true })
console.log(`Cleaned output directory \`${output}\` in ${perf.timeSince("clean")}`)
```

This ensures a clean build state but means ALL 1,866 OG images are regenerated every time, even when only 1-2 files changed.

---

## Implementation Plan: OG Image Caching for CI

### Goal
Reduce CI build time from ~12 minutes to ~2 minutes for typical content updates by caching OG images and only regenerating changed ones.

### How the System Currently Works

1. **CI Trigger:** Push to `main` branch triggers GitHub Actions workflow
2. **Checkout:** Full git history is fetched (`fetch-depth: 0`)
3. **Cache Restore:** Node modules are restored from cache if `package-lock.json` unchanged
4. **Build:**
   a. `rimraf` deletes entire `public/` directory
   b. Parse all 1,866 markdown files (~30s)
   c. Generate all 5,653 output files (~11 minutes)
   d. OG images are generated sequentially via Satori → Sharp pipeline
5. **Deploy:** Upload `public/` to GitHub Pages

### How the System Will Work After This Change

1. **CI Trigger:** Push to `main` branch triggers GitHub Actions workflow
2. **Checkout:** Full git history is fetched
3. **Cache Restore:** 
   a. Node modules restored from cache
   b. **NEW:** OG image cache restored from `.quartz-cache/og-images/`
4. **Build:**
   a. `rimraf` deletes `public/` directory (unchanged)
   b. Parse all markdown files (~30s)
   c. **NEW:** For each OG image:
      - Compute content hash from (title, description, date, tags, text-length)
      - Check if cached image exists with matching hash
      - If cached: copy from cache to `public/`
      - If not cached: generate image, save to `public/` AND cache
   d. Generate other output files
5. **Cache Save:** **NEW:** Save OG image cache for next build
6. **Deploy:** Upload `public/` to GitHub Pages

### Detailed Implementation

#### Step 1: Create Cache Key Function

Add to `quartz/plugins/emitters/ogImage.tsx`:

```typescript
import { createHash } from "crypto"

interface OgImageCacheKey {
  title: string
  description: string
  date: string | null
  tags: string[]
  textLength: number
  configVersion: string  // Hash of theme/typography config
}

function computeCacheKey(fileData: QuartzPluginData, cfg: GlobalConfiguration, configHash: string): string {
  const data: OgImageCacheKey = {
    title: fileData.frontmatter?.title ?? "",
    description: fileData.frontmatter?.description ?? fileData.description ?? "",
    date: fileData.dates?.modified?.toISOString() ?? fileData.dates?.created?.toISOString() ?? null,
    tags: (fileData.frontmatter?.tags ?? []).slice(0, 3),
    textLength: (fileData.text ?? "").length,
    configVersion: configHash  // Pre-computed once during emit initialization
  }
  
  return createHash("sha256").update(JSON.stringify(data)).digest("hex").slice(0, 16)
}

// Compute config hash once at emitter initialization
function computeConfigHash(cfg: GlobalConfiguration): string {
  return createHash("sha256").update(JSON.stringify({
    colors: cfg.theme.colors,
    typography: cfg.theme.typography,
    baseUrl: cfg.baseUrl,
  })).digest("hex").slice(0, 8)
}
```

#### Step 2: Implement Cache Check and Save Logic

Modify `processOgImage` function:

```typescript
import path from "path"
import fs from "node:fs/promises"
import { QUARTZ } from "../../util/path"
import chalk from "chalk"

const OG_CACHE_DIR = path.join(QUARTZ, ".quartz-cache", "og-images")

// Sanitize slug to create a valid filename
function sanitizeSlug(slug: string): string {
  return Buffer.from(slug).toString("base64url")
}

async function processOgImage(
  ctx: BuildCtx,
  fileData: QuartzPluginData,
  fonts: SatoriOptions["fonts"],
  fullOptions: SocialImageOptions,
  configHash: string,  // Pre-computed config hash
) {
  const cfg = ctx.cfg.configuration
  const slug = fileData.slug!
  const outputSlug = `${slug}-og-image` as FullSlug
  
  // Compute cache key
  const cacheKey = computeCacheKey(fileData, cfg, configHash)
  const cacheFileName = `${sanitizeSlug(slug)}_${cacheKey}.webp`
  const cachePath = path.join(OG_CACHE_DIR, cacheFileName)
  
  // Check if cached version exists
  try {
    await fs.access(cachePath)
    // Cache hit: copy to output using fs.copyFile
    const outputPath = path.join(ctx.argv.output, outputSlug + ".webp")
    await fs.mkdir(path.dirname(outputPath), { recursive: true })
    await fs.copyFile(cachePath, outputPath)
    return outputPath
  } catch {
    // Cache miss: generate new image
    console.log(chalk.yellow(`[OG cache miss] ${slug}`))
  }
  
  // Generate image (existing logic)
  const titleSuffix = cfg.pageTitleSuffix ?? ""
  const title = (fileData.frontmatter?.title ?? i18n(cfg.locale).propertyDefaults.title) + titleSuffix
  const description =
    fileData.frontmatter?.socialDescription ??
    fileData.frontmatter?.description ??
    unescapeHTML(fileData.description?.trim() ?? i18n(cfg.locale).propertyDefaults.description)

  const stream = await generateSocialImage({title, description, fonts, cfg, fileData}, fullOptions)
  
  // Ensure cache directory exists
  await fs.mkdir(OG_CACHE_DIR, { recursive: true })
  
  // Write to cache first
  const buffer = await stream.toBuffer()
  await fs.writeFile(cachePath, buffer)
  
  // Write to output
  return write({
    ctx,
    content: buffer,
    slug: outputSlug,
    ext: ".webp",
  })
}
```

#### Step 2b: Update Emit Function to Use Config Hash

The `emit` function should compute the config hash once and pass it to each `processOgImage` call:

```typescript
async *emit(ctx, content, _resources) {
  const cfg = ctx.cfg.configuration
  const headerFont = cfg.theme.typography.header
  const bodyFont = cfg.theme.typography.body
  const fonts = await getSatoriFonts(headerFont, bodyFont)
  
  // Compute config hash once for all images
  const configHash = computeConfigHash(cfg)

  for (const [_tree, vfile] of content) {
    if (vfile.data.frontmatter?.socialImage !== undefined) continue
    yield processOgImage(ctx, vfile.data, fonts, fullOptions, configHash)
  }
}
```

#### Step 3: Update GitHub Actions Workflow

Modify `.github/workflows/deploy.yml`:

```yaml
name: Deploy Quartz site to GitHub Pages

on:
  push:
    branches:
      - main
      - copilot/exploratory-research-build-speed  # For testing

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    container:
      image: node:20-bullseye-slim
    steps:
      - name: Install git
        run: |
          apt-get update
          apt-get install -y git

      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Configure Git
        run: |
          git config --global --add safe.directory "$GITHUB_WORKSPACE"
          git config --global user.email "github-actions[bot]@users.noreply.github.com"
          git config --global user.name "github-actions[bot]"

      - name: Cache Node Modules
        id: cache-node
        uses: actions/cache@v4
        with:
          path: node_modules
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Cache OG Images
        id: cache-og
        uses: actions/cache@v4
        with:
          path: quartz/.quartz-cache/og-images
          # Use a stable key - the cache directory contains content-hashed files
          # so old/stale entries are naturally ignored on cache miss
          key: ${{ runner.os }}-og-images-v1
          restore-keys: |
            ${{ runner.os }}-og-images-

      - name: Install Dependencies (if cache is not hit)
        if: ${{ steps.cache-node.outputs.cache-hit != 'true' }}
        run: npm ci

      - name: Build Quartz
        run: npx quartz build

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: public

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
        with:
          artifact_name: github-pages
          reporting_interval: 300
          error_count: 180
```

### Why This Will Work

1. **Cache Persistence:** GitHub Actions `actions/cache@v4` persists data across workflow runs. The `restore-keys` pattern allows partial matches, so even if the exact SHA doesn't match, the most recent cache is restored.

2. **Cache Key Stability:** The cache key includes:
   - Title, description, date, tags (content that appears in the image)
   - Text length (affects reading time calculation)
   - Config version (theme colors, fonts)
   
   If any of these change, the file gets a new cache key and is regenerated.

3. **Incremental Updates:** 
   - First build: ~12 minutes (generates all 1,866 images, saves to cache)
   - Subsequent builds: ~2 minutes (only regenerates changed images)
   - Typical edit: 1-10 changed files = 1-10 images regenerated

4. **No Public Folder Conflict:** The cache is stored in `.quartz-cache/og-images/`, NOT in `public/`. The `rimraf` of `public/` doesn't affect the cache.

5. **Automatic Cleanup:** Old cache entries naturally expire (unused entries aren't carried forward). GitHub also has cache size limits that force cleanup.

### Potential Issues and Mitigations

| Issue | Mitigation |
|-------|------------|
| Cache corruption | Hash-based keys mean corrupted entries are just cache misses |
| Theme changes invalidate all | `configVersion` in cache key triggers full rebuild |
| Font changes | Fonts cached separately in `.quartz-cache/fonts/` |
| Cache too large | GitHub limits to 10GB per repo; 1,866 × 50KB = ~90MB is fine |
| Stale cache entries | Use `sha` in key for automatic rotation; old keys expire after 7 days |

### Testing Plan

1. **Local Testing:**
   ```bash
   # First run - generates cache
   rm -rf quartz/.quartz-cache/og-images
   time npx quartz build
   
   # Second run - uses cache
   rm -rf public
   time npx quartz build
   
   # Modify one file
   echo "test" >> content/index.md
   rm -rf public
   time npx quartz build  # Should only regenerate 1 image
   ```

2. **CI Testing (on feature branch):**
   - Push change to feature branch
   - First run builds all images
   - Push second change
   - Second run should be significantly faster
   - Compare build times in workflow run summaries

3. **Validation:**
   - Compare generated images before/after to ensure identical output
   - Verify cache hit/miss logging is working
   - Check that theme changes trigger full rebuild

---

## Summary

### Changes Required

1. **`quartz/plugins/emitters/ogImage.tsx`:**
   - Add `computeCacheKey()` function
   - Modify `processOgImage()` to check cache before generating
   - Save generated images to cache directory

2. **`.github/workflows/deploy.yml`:**
   - Add OG image cache step using `actions/cache@v4`

### Expected Results

| Metric | Before | After |
|--------|--------|-------|
| First CI build | ~12 min | ~12 min |
| Subsequent CI builds | ~12 min | ~2 min |
| Build with 1-10 changed files | ~12 min | ~1-2 min |

### Confidence Level: 90%

This approach is low-risk because:
- Cache misses gracefully fall back to regeneration
- No changes to build output (images are identical)
- Uses well-established GitHub Actions caching patterns
- Similar caching already works for fonts in `.quartz-cache/fonts/`
