# Change Log

## 2025-11-29: OG Image Caching for CI Build Speed Optimization

### Problem
CI builds were taking ~12 minutes, with OG image generation consuming most of that time. All 1,866 OG images were regenerated on every build, even when content hadn't changed.

### Solution
Implemented content-based caching for OG images. Images are cached based on a hash of the content that affects their appearance, and reused across builds when unchanged.

### Files Changed

#### `quartz/plugins/emitters/ogImage.tsx`
- Added `computeCacheKey()` function to generate a hash based on content affecting OG image output (slug, title, description, frontmatter dates, tags, text length, and config)
- Modified `processOgImage()` to check for cached images before generating new ones
- Cache hits copy existing images to output; cache misses generate and store new images
- Added cache miss logging for troubleshooting
- Fixed cache key stability: now uses frontmatter dates only (filesystem dates change on every CI checkout causing cache misses)

#### `.github/workflows/deploy.yml`
- Added OG image cache step using `actions/cache@v4`
- Cache stored in `quartz/.quartz-cache/og-images/`
- Added test branch trigger for `copilot/exploratory-research-build-speed`

### Expected Results

| Metric | Before | After |
|--------|--------|-------|
| First CI build | ~12 min | ~12 min |
| Subsequent CI builds | ~12 min | ~7 min |
| Build with 1-10 changed files | ~12 min | ~7 min |
