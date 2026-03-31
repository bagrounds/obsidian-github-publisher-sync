# Deploy Workflow Spec

## Overview
The `deploy.yml` GitHub Actions workflow builds the Quartz static site and deploys it to GitHub Pages.

## Trigger
- Runs on every `push` to any branch (`**`)
- Enables build validation on feature branches and PRs

## Concurrency
- All runs share a single concurrency group (`pages`)
- In-progress runs are cancelled when a new push arrives

## Jobs

### Build
- Runs on all branches
- Checks out the full git history (`fetch-depth: 0`) for date computation
- Uses Node 22 and npm for the Quartz build
- Caches `node_modules` and `.quartz-cache` across runs
- Builds the site with `npx quartz build`
- Downloads the `inject-giscus` binary from the latest successful Haskell CI run
- Injects pre-rendered Giscus comments into the static HTML
- Uploads the built `public/` directory as a GitHub Pages artifact

### Deploy
- **Only runs on `main` branch** (`if: github.ref == 'refs/heads/main'`)
- Deploys the built artifact to the `github-pages` environment

## Invariants
- Only `main` branch deploys reach production; feature branches only validate the build
- The deploy step never runs on non-main branches to prevent accidental overwrites of the live site

## Frontmatter Safety
The Quartz build processes YAML frontmatter via `coerceToArray` in `quartz/plugins/transformers/frontmatter.ts`. This function:
- Treats empty strings (`""`) as absent (returns `undefined`)
- Filters out empty strings after splitting comma-separated values
- Returns `undefined` when no valid values remain
- Cleans up the `data.tags` and `data.aliases` properties when the coerced result is empty, preventing downstream type errors (e.g., `TagPage` expecting an array)

This prevents content with `aliases: ""` or `tags: ""` from generating root-level redirect files or breaking emitter plugins.
