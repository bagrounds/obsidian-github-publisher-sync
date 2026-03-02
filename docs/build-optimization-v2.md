# Build Optimization V2 — CI Performance Analysis & Fixes

## Context

After the V1 optimizations (PR #5719), which improved build times from ~18m to ~12m with OG image caching and parallel generation, CI builds were still taking ~11 minutes. Local builds were much faster (~40s warm cache), indicating the CI slowdown was environment-specific.

## CI Log Analysis

From the CI run logs (main branch, after V1 optimizations):

| Phase | CI Time | Local Time | Ratio |
|-------|---------|------------|-------|
| Clean | 9ms | 6ms | ~1.5x |
| Glob | 47ms | 32ms | ~1.5x |
| **Parse (4 threads)** | **11 min** | **30s** | **~22x** |
| Filter | 2ms | 2ms | 1x |
| Emit (warm cache) | 11s | 11s | ~1x |
| OG Images (cached) | 6.2s | 5.5s | ~1.1x |
| **Total** | **~11 min** | **~40s** | **~16x** |

The **parse step** was the sole remaining bottleneck — 11 minutes in CI vs 30 seconds locally, a 22x slowdown.

## Root Cause: Per-File Git Date Lookups

### The Problem

The `CreatedModifiedDate` transformer plugin (`quartz/plugins/transformers/lastmod.ts`) uses `@napi-rs/simple-git` to get the last modification date for each file:

```typescript
// Called once PER FILE (2,348 times) inside worker threads
modified ||= await repo.getFileLatestModifiedDateAsync(relativePath)
```

**Why this is slow in CI:**
1. Each call traverses git history to find the file's last commit
2. With `fetch-depth: 0` (full history), each lookup scans potentially thousands of commits
3. `@napi-rs/simple-git` uses native bindings (libgit2) that have overhead in Docker containers
4. Running 2,348 individual git operations in parallel worker threads creates I/O contention
5. The Docker container (`node:20-bullseye-slim`) has limited I/O performance

### Locally vs CI

Locally, git operations are fast because:
- The `.git` directory is on a fast local filesystem (often SSD with hot page cache)
- No Docker filesystem layer overhead
- OS-level caching of git pack files is warm

In CI (Docker on GitHub Actions):
- Cold filesystem with no OS-level caching
- Docker overlay filesystem adds latency
- Shared infrastructure with variable I/O performance

## Optimizations Applied

### 1. Bulk Git Date Pre-computation (HIGH IMPACT)

**Before:** 2,348 individual `getFileLatestModifiedDateAsync()` calls → **11 minutes in CI**

**After:** Single `git log --format="COMMIT %ct" --name-only` command → **16ms**

**Implementation** (`quartz/build.ts`):
- Before parsing, run a single `git log` command that outputs all commits with timestamps and changed file names
- Parse the output to build a `Record<string, number>` map (relativePath → epoch milliseconds)
- The first occurrence of each file in the reverse-chronological output is its latest modification date
- Pass the pre-computed map through `BuildCtx` to worker threads
- Workers check the map before falling back to per-file git lookups

**Why this works:** A single `git log` traversal processes the entire history once (O(commits)), vs O(files × commits) for per-file lookups.

### 2. Remove Docker Container from CI (MEDIUM IMPACT)

**Before:** `container: image: node:20-bullseye-slim` + `apt-get install git` (~15s overhead)

**After:** Native `ubuntu-latest` runner + `actions/setup-node@v4`

**Benefits:**
- Eliminates Docker image pull time (~6s)
- Eliminates `apt-get update && apt-get install -y git` (~7s)
- Native filesystem I/O (no overlay filesystem)
- Better native module (napi-rs) compatibility
- Git is pre-installed on ubuntu-latest

### 3. Semaphore-Based OG Image Concurrency (REQUESTED)

**Before:** Fixed batch sizes with `Promise.all` — all 20 tasks in a batch must complete before the next batch starts

**After:** Semaphore pattern — maintains 20 concurrent tasks at all times. When one finishes, the next starts immediately. No "batch boundary" idle time.

**Implementation** (`quartz/plugins/emitters/ogImage.tsx`):
- `runWithConcurrency<T>()` generator function manages a pool of up to N concurrent promises
- Each completed promise immediately triggers the next task
- Results are yielded as they complete (no waiting for batch boundaries)

### 4. Comprehensive Build Logging (REQUESTED)

Added detailed timing and diagnostics:

```
Pre-computed git dates for 2614 files in 16ms
Parsed 2348 Markdown files in 30s
  OG Images: 2348 images in 1.8s (cache: 2348 hits/0 misses, 100.0% hit rate, concurrency: 20)
Emitted 7169 files to `public` in 11s
  ContentPage: 2337 files in 11.0s
  AliasRedirects: 2373 files in 10.3s
  CustomOgImages: 2348 files in 5.4s
  ...
Done processing 2348 files in 40s
```

Logging includes:
- Git date pre-computation timing and file count
- Parse phase timing per thread phase (text→markdown, markdown→html)
- OG image cache hit/miss counts and hit rate percentage
- Per-emitter file counts and timing (sorted by duration)
- Total build duration

### 5. CI Workflow Improvements

- **Branch testing**: Added `copilot/optimize-ci-build-times` branch trigger
- **Separated build/deploy jobs**: Build job runs on all branches; deploy only on `main`
- **Environment protection**: Deploy job has explicit `github-pages` environment

## Results

### Local Build (Warm Cache)

| Metric | V1 | V2 | Improvement |
|--------|-----|-----|-------------|
| Git dates | (included in parse) | **16ms** | N/A |
| Parse | 30s | **30s** | Same (git was masked by parallelism locally) |
| OG Images | 5.5s | **1.8s** | 3x (semaphore avoids batch idle) |
| Total Emit | 11s | **11s** | Same |
| **Total Build** | **40s** | **40s** | Same locally |

### Expected CI Build (Warm Cache)

| Metric | V1 (CI) | V2 (CI Expected) | Improvement |
|--------|---------|-------------------|-------------|
| Docker setup | ~15s | **0s** | Eliminated |
| Git dates | 11 min (in parse) | **<1s** | **~660x** |
| Parse | 11 min | **~30-60s** | **~11-22x** |
| OG Images (cached) | 6.2s | **~2-6s** | Similar |
| Total Emit | 11s | **~11s** | Similar |
| **Total Build** | **~11 min** | **~45-75s** | **~9-15x** |

## Remaining Bottlenecks & Options for Further Optimization

If sub-1-minute build time is still not achieved after these changes, the remaining bottlenecks are:

### 1. Parse Time (~30-60s)
The markdown parsing pipeline processes 2,348 files through KaTeX math rendering, Shiki syntax highlighting, and various remark/rehype transforms. This is inherently CPU-intensive.

**Options to reduce:**
- **Parse caching**: Cache serialized AST results keyed by file content hash. Risk: complex serialization, cross-file dependencies
- **Reduce transformer scope**: Skip KaTeX/Shiki for files without math/code (requires pre-scanning)
- **More worker threads**: Increase from 4 to match available vCPUs (diminishing returns)

### 2. Emit Time (~11s with warm cache)
Emitters process all files even when only a few changed. The `ContentPage` and `AliasRedirects` emitters each take ~10s.

**Options to reduce:**
- **Skip unchanged emitter outputs**: Only re-emit files whose inputs changed
- **Don't clean output directory**: Use incremental output instead of full clean-and-rebuild (risk: stale files)

### 3. Nice Properties at Risk
Any of these further optimizations would compromise:
- **Correctness guarantees**: Parse caching could serve stale results if cache keys don't capture all dependencies
- **Simplicity**: Incremental builds add complexity and potential for stale artifacts
- **Determinism**: Caching introduces state that affects build behavior

## Files Changed

| File | Change |
|------|--------|
| `quartz/build.ts` | Added `precomputeGitDates()`, integrated into build pipeline |
| `quartz/util/ctx.ts` | Added `gitModifiedDates` to `BuildCtx` interface |
| `quartz/processors/parse.ts` | Pass `gitModifiedDates` to worker threads |
| `quartz/plugins/transformers/lastmod.ts` | Use pre-computed dates, skip per-file git lookups |
| `quartz/plugins/emitters/ogImage.tsx` | Semaphore concurrency, cache hit/miss logging |
| `.github/workflows/deploy.yml` | Remove Docker, add branch trigger, separate build/deploy |
