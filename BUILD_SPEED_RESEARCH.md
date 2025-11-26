# Build Speed Optimization Research

## Current State Analysis

### Build Metrics (Baseline)
- **1,866 Markdown files**
- **5,653 total output files** (HTML pages, OG images, assets, etc.)
- **Total build time: ~5 minutes** (306 seconds)
- **Parsing phase: ~30 seconds** (32s observed)
- **Emit phase: ~5 minutes** (the dominant bottleneck)
- **OG image generation: 1,866 images totaling ~67.5 MB**

### Build Pipeline Overview

The Quartz build process consists of three main phases:

1. **Transpilation** (~3 seconds): Uses esbuild to transpile the Quartz configuration and build scripts
2. **Markdown Parsing** (~30 seconds): Converts markdown files to HTML AST using unified/remark/rehype pipelines
3. **Emission** (~5 minutes): Generates output files including HTML pages, OG images, sitemap, RSS, etc.

### Code Architecture

```
quartz/
├── cli/handlers.js        # Main entry point for build command
├── build.ts               # Core build orchestration
├── processors/
│   ├── parse.ts          # Markdown parsing with worker threads
│   ├── filter.ts         # Content filtering
│   └── emit.ts           # Emission orchestration
├── plugins/
│   ├── transformers/     # Markdown and HTML transformers
│   ├── filters/          # Content filters
│   └── emitters/         # Output generators (ContentPage, OgImages, etc.)
└── worker.ts             # Worker thread implementation
```

---

## Identified Bottlenecks

### 1. OG Image Generation (Major)
**Location:** `quartz/plugins/emitters/ogImage.tsx`

- Generates 1,866 individual social media preview images using Satori + Sharp
- Each image requires:
  - Satori SVG rendering
  - Sharp WebP conversion
  - File I/O
- Processing is **sequential** within the emitter
- Fetching fonts from Google Fonts (though cached after first build)

**Evidence:**
```typescript
// ogImage.tsx:112-121
async *emit(ctx, content, _resources) {
  // ...
  for (const [_tree, vfile] of content) {
    if (vfile.data.frontmatter?.socialImage !== undefined) continue
    yield processOgImage(ctx, vfile.data, fonts, fullOptions)  // Sequential!
  }
}
```

### 2. Content Page Rendering (Moderate)
**Location:** `quartz/plugins/emitters/contentPage.tsx`

- Renders HTML for each page individually
- Uses Preact render-to-string
- Includes deep cloning of AST for transclusion support
- Processing is **sequential** via async generator

**Evidence:**
```typescript
// renderPage.tsx:198
const root = clone(componentData.tree) as Root  // Deep clone for each page
```

### 3. Sequential Emitter Execution (Moderate)
**Location:** `quartz/processors/emit.ts`

- All emitters run in parallel with `Promise.all`, BUT
- Each emitter internally processes files sequentially via async generators
- No batch processing or worker pool for emission phase

**Evidence:**
```typescript
// emit.ts:18-47
await Promise.all(
  cfg.plugins.emitters.map(async (emitter) => {
    // Each emitter yields files one at a time
    for await (const file of emitted) {
      emittedFiles++
    }
  })
)
```

### 4. Parser Concurrency (Minor - Already Optimized)
**Location:** `quartz/processors/parse.ts`

- Already uses worker pool for markdown parsing
- Default concurrency is `clamp(fps.length / 128, 1, 4)` = 4 threads for this repo
- Chunk size of 128 files per worker

---

## Optimization Ideas

### Idea 1: Parallelize OG Image Generation Using Worker Pool

**Description:** Move OG image generation to a worker pool similar to markdown parsing. Each worker would handle a batch of images.

**Implementation Approach:**
1. Create a new worker function for OG image processing
2. Split content into chunks and distribute to workers
3. Use `workerpool` (already a dependency) to manage parallelism

**Effort:** Medium (2-3 days)
- Requires creating new worker script for image generation
- Need to handle Satori/Sharp in worker context
- Must serialize font data to workers

**Complexity:** Medium
- Satori and Sharp may have thread-safety considerations
- Font data serialization could be tricky
- Error handling across workers needs care

**Payoff:** High
- Could reduce OG image time from ~4.5 minutes to ~1-1.5 minutes (3-4x speedup)
- OG images are the dominant bottleneck

**Maintainability:** Medium
- Adds parallel processing complexity
- But follows existing pattern from parse.ts

**Confidence:** 75%
- Similar parallelization works for markdown parsing
- Sharp is known to work in workers
- Satori may need careful handling

---

### Idea 2: Disable OG Image Generation for Development Builds

**Description:** Add a flag to skip OG image generation during development/testing builds, only generating them for production.

**Implementation Approach:**
1. Add `--skipOgImages` or `--production` CLI flag
2. Conditionally include/exclude CustomOgImages emitter
3. Or add environment variable check in the emitter

**Effort:** Low (1-2 hours)
- Simple CLI argument addition
- Conditional plugin loading

**Complexity:** Low
- Minimal code changes
- Clear behavior

**Payoff:** High for development workflow
- Reduces dev build from 5m to ~30s
- Doesn't help production builds

**Maintainability:** High
- Simple, clear feature
- Easy to understand and maintain

**Confidence:** 95%
- Straightforward implementation
- No technical risks

---

### Idea 3: Incremental OG Image Generation with Caching

**Description:** Cache generated OG images and only regenerate when content changes.

**Implementation Approach:**
1. Hash content (title, description, date) to create cache key
2. Store generated images in `.quartz-cache/og-images/`
3. On rebuild, check if cached version matches current content
4. Copy from cache instead of regenerating

**Effort:** Medium (2-3 days)
- Hash computation for content
- Cache directory management
- Cache invalidation logic

**Complexity:** Medium
- Need robust content hashing
- Cache cleanup/invalidation strategy
- Disk space management considerations

**Payoff:** Very High for incremental builds
- First build unchanged
- Subsequent builds: only regenerate changed content
- Typical edit touches 1-10 files → 5-10 seconds vs 5 minutes

**Maintainability:** Medium
- Cache invalidation can be tricky
- Need to handle edge cases (font changes, config changes)

**Confidence:** 85%
- Standard caching pattern
- Content hashing is reliable
- Similar approaches used in many SSGs

---

### Idea 4: Use Batch Processing in Content Page Emitter

**Description:** Process multiple pages concurrently within the ContentPage emitter instead of one at a time.

**Implementation Approach:**
1. Collect all pages to render into batches
2. Use `Promise.all` with limited concurrency (e.g., p-limit)
3. Yield results in batches

**Effort:** Low-Medium (1-2 days)
- Refactor async generator to batch processing
- Add concurrency limiting

**Complexity:** Low
- Simple Promise.all pattern
- No worker threads needed

**Payoff:** Medium
- HTML rendering is CPU-bound but fast
- Parallelization might save 30-60 seconds
- Less impact than OG image optimization

**Maintainability:** High
- Simple parallel pattern
- Easy to understand

**Confidence:** 80%
- Standard parallelization
- Need to verify no shared state issues

---

### Idea 5: Optimize rfdc (Clone) with Faster Alternative

**Description:** Replace `rfdc` deep clone with a faster alternative or avoid cloning entirely.

**Implementation Approach:**
1. Profile to confirm clone is a bottleneck
2. Try faster alternatives like `structuredClone` or `lodash.cloneDeep`
3. Or refactor to avoid deep cloning when possible

**Effort:** Low (1-2 hours for profiling and swap)

**Complexity:** Low
- Drop-in replacement
- Test for correctness

**Payoff:** Low-Medium
- Clone is called per page (1,866 times)
- rfdc is already quite fast
- Likely saves only 5-10 seconds

**Maintainability:** High
- Simple change if switching libraries

**Confidence:** 60%
- Unclear if clone is a significant bottleneck
- Need profiling to verify

---

### Idea 6: Pre-generate Static Components

**Description:** Cache rendered static components (Header, Footer, etc.) that don't change between pages.

**Implementation Approach:**
1. Identify components that render the same across all pages
2. Pre-render these components once
3. Inject pre-rendered HTML into page templates

**Effort:** Medium (2-3 days)
- Component analysis
- Template injection system
- Cache management

**Complexity:** Medium-High
- Components may have page-specific variations
- Need careful analysis of what's truly static

**Payoff:** Low-Medium
- Preact render-to-string is already fast
- Most components have page-specific data
- Likely saves 15-30 seconds

**Maintainability:** Medium
- Adds caching complexity
- Need to invalidate when config changes

**Confidence:** 50%
- Uncertain which components are truly static
- Benefits depend on component structure

---

### Idea 7: Lazy Asset Copying with Timestamps

**Description:** Only copy assets that are newer than their destinations.

**Implementation Approach:**
1. Check file modification times before copying
2. Skip unchanged files

**Effort:** Low (1-2 hours)

**Complexity:** Low
- Simple mtime comparison
- Already exists in many build tools

**Payoff:** Low
- Assets are ~30MB, mostly images
- File copying is fast
- Maybe saves 5-10 seconds on incremental builds

**Maintainability:** High
- Simple, well-understood pattern

**Confidence:** 90%
- Standard approach
- Minimal risk

---

### Idea 8: Move to Native Sharp Batch Processing

**Description:** Use Sharp's native batch processing capabilities instead of processing images one at a time.

**Implementation Approach:**
1. Collect all SVGs from Satori first
2. Use Sharp's pipeline to process all images concurrently
3. Sharp internally manages thread pool

**Effort:** Medium (1-2 days)

**Complexity:** Medium
- Need to restructure emit flow
- Handle backpressure for large batches

**Payoff:** Medium-High
- Sharp is highly optimized for batch processing
- Could reduce image processing time by 50%

**Maintainability:** Medium
- Different processing pattern
- Need to handle memory for large batches

**Confidence:** 70%
- Sharp supports this well
- Need to verify memory usage with 1,866 images

---

## Recommendation

### Primary Recommendation: Implement Ideas 2 + 3 (Combination)

**Phase 1: Quick Win - Idea 2 (Skip OG Images flag)**
- Immediate development experience improvement
- 1-2 hours of work
- Drops dev build from 5m to ~30s

**Phase 2: Production Optimization - Idea 3 (OG Image Caching)**
- Addresses production build times for incremental updates
- 2-3 days of work
- Makes subsequent builds fast while keeping all features

### Secondary Recommendation: Idea 1 (Parallel OG Generation)

If Phase 2 caching isn't sufficient or if full rebuilds are common:
- Implement worker pool for OG images
- Higher effort but provides 3-4x speedup for full builds

### Why Not Other Ideas?

- **Idea 4 (Batch ContentPage):** Smaller impact, parsing is already parallelized
- **Idea 5 (Clone optimization):** Need profiling first, likely minimal impact
- **Idea 6 (Static components):** Complex with uncertain payoff
- **Idea 7 (Lazy assets):** Already fast, minimal gain
- **Idea 8 (Sharp batch):** Good but Idea 1 is more impactful

---

## Summary Table

| Idea | Effort | Complexity | Payoff | Maintainability | Confidence |
|------|--------|------------|--------|-----------------|------------|
| 1. Parallel OG Workers | Medium | Medium | High | Medium | 75% |
| 2. Skip OG Flag | Low | Low | High (dev) | High | 95% |
| 3. OG Image Caching | Medium | Medium | Very High | Medium | 85% |
| 4. Batch ContentPage | Low-Med | Low | Medium | High | 80% |
| 5. Faster Clone | Low | Low | Low-Med | High | 60% |
| 6. Static Components | Medium | Med-High | Low-Med | Medium | 50% |
| 7. Lazy Asset Copy | Low | Low | Low | High | 90% |
| 8. Sharp Batch | Medium | Medium | Med-High | Medium | 70% |

---

## Code Citations

### OG Image Generation (Primary Bottleneck)
- `quartz/plugins/emitters/ogImage.tsx:112-121` - Sequential emit loop
- `quartz/plugins/emitters/ogImage.tsx:28-66` - generateSocialImage function
- `quartz/util/og.tsx:17-66` - Font fetching (cached)

### Markdown Parsing (Already Parallelized)
- `quartz/processors/parse.ts:148-222` - parseMarkdown with worker pool
- `quartz/worker.ts` - Worker thread implementation

### Content Emission
- `quartz/processors/emit.ts:9-50` - Main emit orchestration
- `quartz/plugins/emitters/contentPage.tsx:76-119` - ContentPage emitter

### Build Configuration
- `quartz/cli/args.js` - CLI arguments including `--concurrency`
- `quartz.config.ts` - Plugin configuration

---

## Next Steps

1. **Discuss recommendations** with stakeholders
2. **Choose approach** based on priorities (dev experience vs production builds)
3. **Implement selected optimizations** in order of impact
4. **Measure results** after each change
5. **Iterate** based on findings
