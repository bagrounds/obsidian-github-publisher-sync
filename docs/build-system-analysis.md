# Build System Analysis

## Overview

This document provides a comprehensive analysis of the Quartz 4.5.0 build system used by this site (bagrounds.org). The build system is a static site generator that converts ~2,348 Markdown files into a fully rendered website with HTML pages, social images, RSS feeds, sitemaps, and static assets.

## Build Pipeline Architecture

The build has two main stages:

### Stage 1: esbuild Transpilation (`handleBuild` in `quartz/cli/handlers.js`)
- esbuild bundles the entire Quartz TypeScript codebase into a single cached JS module (`quartz/.quartz-cache/transpiled-build.mjs`)
- This includes SCSS compilation via `esbuild-sass-plugin` and inline script bundling
- The output is dynamically imported to run Stage 2

### Stage 2: Site Generation (`buildQuartz` in `quartz/build.ts`)
1. **Clean** — `rimraf` clears `public/` directory (~6ms)
2. **Glob** — Finds all content files in `content/` (~34ms)
3. **Parse** — Markdown → AST → HTML processing using worker threads (~31s)
4. **Filter** — Removes drafts based on frontmatter (~2ms)
5. **Emit** — Runs all emitter plugins in parallel to write output files (~5m15s)

### Emitter Plugins (run via `Promise.all`)

| Emitter | Files | Time | % of Emit |
|---------|-------|------|-----------|
| **CustomOgImages** | **2,348** | **315.2s** | **90.2%** |
| ContentPage | 2,337 | 13.6s | 3.9% |
| AliasRedirects | 2,373 | 13.1s | 3.7% |
| ContentIndex | 3 | 4.8s | 1.4% |
| Assets | 79 | 4.7s | 1.3% |
| FolderPage | 11 | 4.0s | — |
| TagPage | 8 | 4.0s | — |
| ComponentResources | 3 | 3.9s | — |
| Static | 6 | 3.9s | — |
| 404Page | 1 | 3.7s | — |

**Total emit: 7,169 files in ~5m15s**

## Baseline Build Timing

| Phase | Duration |
|-------|----------|
| Clean | 6ms |
| Glob | 34ms |
| Parse (4 threads) | 31s |
| Filter | 2ms |
| **Emit (all emitters)** | **5m15s** |
| **Total** | **~5m50s** |

## Root Cause Analysis: 5 Whys

### Why is the build slow?
**Because the emit phase takes 5+ minutes.**

### Why does the emit phase take 5+ minutes?
**Because CustomOgImages takes 315 seconds to generate 2,348 social images.**

### Why does CustomOgImages take 315 seconds?
**Because each OG image is generated sequentially (one at a time) and each takes ~134ms:**
- The `emit()` method is an async generator that `yield`s one image at a time
- The consuming `for await` loop in `emit.ts` processes each yield serially
- Each image requires: JSX → SVG (satori) → WebP (sharp)

### Why is each image generated individually without parallelism or caching?
1. **No parallelism**: The async generator pattern (`yield processOgImage(...)`) produces images one-by-one; the consumer awaits each before requesting the next.
2. **No caching**: Every build regenerates all 2,348 OG images from scratch, even if the content hasn't changed.
3. **Redundant I/O**: The icon file is read from disk for every single image.

### Why does even a single image take 134ms?
**Because each image requires two CPU-intensive transformations:**
1. **satori** (~80-100ms): Converts JSX/CSS to SVG by running a full layout engine (Yoga/WASM)
2. **sharp** (~30-50ms): Converts the SVG buffer to WebP format using libvips
3. **sharp concurrency is 1**: Only one libvips thread is used per sharp call

## Key Observations

1. **OG images dominate build time** — 315s out of 350s total (90% of the build)
2. **Content rarely changes in bulk** — Typical commits add/modify 1-5 files
3. **OG image inputs are deterministic** — For a given (title, description, tags, date, config), the output image is always the same
4. **No incremental caching** — The entire `public/` directory is cleaned and regenerated every build
5. **Emitters run in Promise.all but OG is sequential** — Other emitters finish fast; OG serializes everything

## Desirable Properties of the Current Build System

1. **Correctness**: Every output file is up-to-date after each build
2. **Determinism**: Same inputs always produce same outputs
3. **Simplicity**: Clean slate each build avoids stale artifact issues
4. **Complete output**: All pages, images, feeds, sitemaps generated together
5. **Incremental watch mode**: Rebuilds only changed content during development

---

## Optimization Proposals

### 1. Content-Based OG Image Caching (HIGH IMPACT, LOW RISK)

**Concept**: Hash the inputs to each OG image (title, description, tags, date, config colors/fonts, etc.). Store generated images in a persistent cache directory (`.quartz-cache/og-images/`). Before generating an image, check if a cached version with the same hash exists; if so, copy it instead of regenerating.

**Expected impact**: Near-zero OG image generation time for unchanged content. On a typical build where only 1-5 files changed, this would reduce OG time from 315s to <5s.

**Risk**: Very low. The hash captures all inputs that affect the image. Cache invalidation is automatic (content change = new hash = regenerate).

### 2. Parallel OG Image Generation (HIGH IMPACT, LOW RISK)

**Concept**: Instead of yielding one image at a time via the async generator, batch-process images using controlled concurrency (e.g., `Promise.all` with batches of N, or `p-limit`). With 4 CPU cores available, 4-8x speedup is achievable.

**Expected impact**: 4-8x speedup on OG generation (315s → ~40-80s for uncached images).

**Risk**: Low. sharp and satori are both thread-safe. Memory usage increases proportionally to concurrency.

### 3. Persist OG Cache in CI/CD (MEDIUM IMPACT, LOW RISK)

**Concept**: Add the `.quartz-cache/og-images/` directory to the GitHub Actions cache. Between CI runs, only new/changed content triggers OG regeneration.

**Expected impact**: CI builds drop from 6min to <1min for typical content changes.

**Risk**: Very low. Cache is invalidated correctly by content hash.

### 4. Avoid Cleaning Output Directory Entirely (MEDIUM IMPACT, MEDIUM RISK)

**Concept**: Instead of `rimraf public/*` at the start, use content-aware output that only writes changed files and removes deleted ones. This avoids unnecessary re-emission of static assets and other unchanged content.

**Expected impact**: Saves 13-15s on ContentPage and AliasRedirects.

**Risk**: Medium. Stale files could remain if the cleanup logic has bugs.

### 5. Read icon.png Once Instead of Per-Image (LOW IMPACT, LOW RISK)

**Concept**: The `generateSocialImage` function reads `quartz/static/icon.png` for every single image. Cache this at the emitter level (read once, pass to all).

**Expected impact**: Eliminates ~2,348 unnecessary filesystem reads, saving ~1-2s.

**Risk**: Negligible.

### 6. Increase sharp Concurrency (LOW IMPACT, LOW RISK)

**Concept**: Set `sharp.concurrency()` to match available CPU cores (currently defaults to 1).

**Expected impact**: Modest improvement when combined with parallel generation.

**Risk**: Negligible.

### 7. Skip Parsing Unchanged Files (MEDIUM IMPACT, HIGH RISK)

**Concept**: Cache parsed AST/HTML output and only re-parse changed markdown files.

**Expected impact**: Could reduce 31s parse time to near-zero for incremental builds.

**Risk**: High. Would need to track all transitive dependencies (plugins, config, etc.) to ensure cache validity.

---

## Implementation Priority

1. **Content-Based OG Image Caching** — Highest impact, easiest to implement correctly
2. **Parallel OG Image Generation** — Complements caching for cold builds
3. **CI/CD Cache Persistence** — Ensures caching benefits apply to production builds
4. **Icon Read Optimization** — Simple fix, small but measurable improvement
5. **Remaining optimizations** — Lower priority, implement if target not met

## Target

Reduce build time from ~6 minutes to under 1 minute for typical incremental builds.
