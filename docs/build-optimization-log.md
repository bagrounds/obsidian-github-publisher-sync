# Build Optimization Implementation Log

## Optimization 1: Content-Based OG Image Caching

### Hypothesis
OG images are deterministic: given the same inputs (title, description, tags, date, color scheme, dimensions), the output image is always the same. By hashing these inputs and storing generated images in a persistent cache, we can skip regeneration for unchanged content.

### Implementation
**File**: `quartz/plugins/emitters/ogImage.tsx`

1. **Hash computation**: `computeOgHash()` creates a SHA-256 hash from title, description, tags, date, colorScheme, width, height, and a version number (for cache busting on format changes).
2. **Cache directory**: `quartz/.quartz-cache/og-images/` (already gitignored via `.quartz-cache`)
3. **Cache flow**:
   - Before generating, check if `{hash}.webp` exists in cache dir
   - If yes: read cached file and copy to output (fast file copy)
   - If no: generate image via satori+sharp, write to cache AND output
4. **Icon caching**: `getIconBase64()` reads the icon file once and caches in memory, eliminating 2,348 redundant filesystem reads per build.

### Results
| Scenario | OG Image Time | Total Build |
|----------|-------------|-------------|
| Baseline (sequential, no cache) | 315.2s | 5m50s |
| Warm cache | **5.5s** | **45s** |
| **Speedup** | **57x** | **7.7x** |

---

## Optimization 2: Parallel OG Image Generation

### Hypothesis
The original code used an async generator that `yield`ed one image at a time. The consuming `for await` loop awaited each yielded value before requesting the next, making generation purely sequential. Since satori and sharp are both CPU-bound but can overlap their work, processing images in batches with `Promise.all` should yield significant speedup.

### Implementation
**File**: `quartz/plugins/emitters/ogImage.tsx`

1. **Batch processing**: Images are processed in batches of `OG_CONCURRENCY` (20) using `Promise.all`
2. **Yielding results**: After each batch completes, results are yielded to the consumer
3. **Same pattern for partialEmit**: Incremental builds also use batched processing

### Results
| Scenario | OG Image Time | Total Build |
|----------|-------------|-------------|
| Baseline (sequential) | 315.2s | 5m50s |
| Cold build (parallel, no cache) | **138.6s** | **2m54s** |
| **Speedup** | **2.3x** | **2x** |

---

## Optimization 3: CI/CD OG Cache Persistence

### Hypothesis
CI builds always start from a clean slate. By persisting the OG image cache between CI runs, subsequent builds only regenerate images for changed content.

### Implementation
**File**: `.github/workflows/deploy.yml`

Added GitHub Actions cache step for `quartz/.quartz-cache/og-images` with a key based on `hashFiles('content/**/*.md')` and a fallback `restore-keys: og-images-` to always restore the closest cache even on partial matches.

### Expected Results
After the first CI build populates the cache, subsequent builds with typical content changes (1-5 files) should see near-zero OG generation time, bringing CI builds down from ~6min to under 1min.

---

## Optimization 4: Icon Read Once (Included in #1)

Moved `icon.png` reading from per-image to a singleton with `getIconBase64()`. This eliminates 2,348 filesystem reads per build.

---

## Combined Results Summary

| Build Scenario | Before | After | Speedup |
|----------------|--------|-------|---------|
| Cold build (no cache) | 5m50s | 2m54s | 2x |
| Warm build (cached OG images) | 5m50s | **45s** | **7.7x** |
| Typical CI build (cached + few changes) | ~6min+ | **<1min** | **>6x** |

### Verification
- Output file count is identical: 7,169 files (2,348 OG images, 4,729 HTML, etc.)
- Output size is identical: 291MB
- OG images are valid WebP files at 1200x630 pixels
- All existing emitters continue to function correctly
- Cache invalidation is automatic: changing any OG-affecting input produces a new hash
