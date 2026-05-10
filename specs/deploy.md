# Deploy Workflow Spec

## Overview
The `deploy.yml` GitHub Actions workflow builds the Quartz static site and deploys it to GitHub Pages.

## Trigger
- Runs on `push` to the `main` branch
- Can be triggered manually via `workflow_dispatch` from any branch
- PRs do not trigger a deployment automatically, preventing stale or partial builds from overwriting the live site

## Concurrency
- All runs share a single concurrency group (`pages`)
- In-progress runs are cancelled when a new push arrives

## Jobs

### Build
- Runs on `main` only
- Checks out the full git history (`fetch-depth: 0`) for date computation
- Uses Node 22 and npm for the Quartz build
- Caches `node_modules` and `.quartz-cache` across runs
- Builds the site with `npx quartz build`
- Downloads the `inject-giscus` binary from the latest successful Haskell CI run
- Injects pre-rendered Giscus comments into the static HTML
- Uploads the built `public/` directory as a GitHub Pages artifact

### Deploy
- Deploys the built artifact to the `github-pages` environment
- Runs only on `main` (gated by `if: github.ref == 'refs/heads/main'`), so the live site always reflects the latest merged code
- When triggered manually from a non-main branch the build job still runs (useful for verifying the build succeeds), but no deployment occurs

## AliasRedirects: Disabled
The `AliasRedirects` Quartz emitter plugin is **disabled** (removed from `quartz.config.ts`). Aliases in frontmatter are only used by Obsidian for wikilink display text — nobody navigates to emoji-heavy title URLs. Disabling AliasRedirects eliminates the risk of empty aliases overwriting the homepage.

## Frontmatter Safety
The Quartz build processes YAML frontmatter via `coerceToArray` in `quartz/plugins/transformers/frontmatter.ts`. This function:
- Treats empty strings (`""`) as absent (returns `undefined`)
- Filters out empty strings after splitting comma-separated values
- Returns `undefined` when no valid values remain
- Cleans up the `data.tags` and `data.aliases` properties when the coerced result is empty, preventing downstream type errors (e.g., `TagPage` expecting an array)

## Blog Frontmatter Generation
The `assembleFrontmatter` function in `haskell/src/Automation/BlogPrompt.hs` generates blog post frontmatter. It must NOT include empty `tags:` fields, as the Obsidian publisher normalizes `tags:` (null) to `tags: ""` (empty string), which breaks the Quartz `TagPage` emitter.
