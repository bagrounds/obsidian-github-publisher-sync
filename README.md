# 📚 obsidian-github-publisher-sync

🏗️ A publishing pipeline that transforms an [Obsidian](https://obsidian.md) vault into a public website at [bagrounds.org](https://bagrounds.org/). 🔄 Content flows one way: from the Obsidian vault (source of truth) on a mobile device, through the [Enveloppe](https://github.com/Enveloppe/obsidian-enveloppe) plugin, into this GitHub repository, and out to GitHub Pages via [Quartz](https://quartz.jzhao.xyz/).

🤖 On top of this static publishing layer, a suite of **GitHub Actions workflows** adds AI-powered features: daily blog generation, social media posting, internal linking, image generation, and comment injection — all without ever writing back to the git repository.

## 🌐 Architecture Overview

```
┌─────────────────────┐      Enveloppe        ┌──────────────────────┐
│  Obsidian Vault      │ ─────────────────────▶ │  GitHub Repository   │
│  (phone, read-only)  │ ◀──── ob sync ─────── │  content/ directory   │
└─────────────────────┘                        └──────────┬───────────┘
                                                          │
                                  ┌───────────────────────┼──────────────────┐
                                  │                       │                  │
                            GitHub Actions          GitHub Pages         Giscus
                           (6 workflows)          (Quartz SSG)       (comments)
                                  │                       │                  │
                    ┌─────────────┼─────────────┐         │                  │
                    │             │             │          │                  │
               Blog Gen     Social Post    Internal     Deploy           Comment
              + Images       to X/BS/M     Linking    (build +          injection
                                                      deploy)           (SEO)
```

### 📱 Obsidian Vault → GitHub (Enveloppe)

📝 The `content/` directory is a **read-only mirror** of the Obsidian vault. 🔒 No GitHub Action or script ever commits to the repository. 📤 The [Enveloppe](https://github.com/Enveloppe/obsidian-enveloppe) Obsidian plugin pushes notes marked with `share: true` in their frontmatter to this repo.

### 🔄 GitHub → Obsidian Vault (ob sync)

🔙 Generated content (blog posts, images, updated frontmatter) flows back to the vault via the [`obsidian-headless`](https://www.npmjs.com/package/obsidian-headless) CLI (`ob sync`). 📂 The `scripts/sync-file-to-obsidian.ts` script copies files into a locally synced vault directory, then pushes changes back.

### 🌍 GitHub → Website (Quartz + GitHub Pages)

🏗️ On every push to `main`, the **Deploy** workflow builds the site with [Quartz 4](https://quartz.jzhao.xyz/) (a static site generator for Obsidian vaults) and deploys to GitHub Pages. 💬 After building, `inject-static-giscus.ts` fetches [Giscus](https://giscus.app/) discussion comments via the GitHub GraphQL API and injects static HTML for SEO visibility.

## 📂 Content Organization

| 📁 Directory | 📊 Count | 📝 Description |
|---|---|---|
| 📚 `books/` | ~957 | 📖 Book reports and reading notes |
| 🪞 `reflections/` | ~492 | 📝 Daily journal / blog entries |
| 📺 `videos/` | ~700 | 🎬 Video notes and summaries |
| 🌌 `topics/` | ~91 | 💡 Topic pages (philosophy, CS, etc.) |
| 📄 `articles/` | ~81 | 📰 Article notes |
| 🤖💬 `bot-chats/` | ~49 | 🗣️ Conversations with AI |
| 💾 `software/` | ~31 | 🖥️ Software tool notes |
| 👥 `people/` | ~18 | 🧑 People notes |
| 🛍️ `products/` | ~6 | 🛒 Product reviews |
| 🎤 `presentations/` | 2 | 🎙️ Talk slides and notes |
| 🧰 `tools/` | 1 | 🧮 Interactive tools (calculator) |
| 🎮 `games/` | 1 | 🧬 Interactive games (Valence) |
| 🤖 `auto-blog-zero/` | ~12 | 📝 AI-generated daily blog posts |
| 🐔 `chickie-loo/` | ~12 | 🐣 AI-generated chicken-themed blog posts |
| 🤖 `ai-blog/` | ~30 | 📝 AI agent blog posts about code changes |

## ⚙️ GitHub Actions Workflows

### 1. 🚀 Deploy (`deploy.yml`)

🔄 Triggers on push to `main`. 🏗️ Builds the Quartz site, injects static Giscus comments for SEO, and deploys to GitHub Pages.

### 2. 📝 Auto Blog Zero (`auto-blog-zero.yml`)

⏰ Daily at 8:00 AM PT. 🤖 Generates a new blog post using Gemini AI based on the author's recent reflections and GitHub Discussions. 🖼️ Optionally generates a cover image using Cloudflare Workers AI (FLUX.1 Schnell). 📤 Syncs the post back to the Obsidian vault.

### 3. 🐔 Chickie Loo (`chickie-loo.yml`)

⏰ Daily at 7:00 AM PT. 🐣 Same architecture as Auto Blog Zero but with a chicken-keeping themed personality and priority user.

### 4. 📢 Auto Post to Social Media (`tweet-reflection.yml`)

⏰ Every 2 hours. 🔍 Uses BFS from the most recent reflection to discover unposted content. 📱 Posts to Twitter/X, Bluesky, and Mastodon with platform-specific formatting and length limits. 🤖 Uses Gemini to generate engaging summaries. 📊 Tracks posted status via frontmatter sections in the Obsidian vault.

### 5. 🔗 Internal Linking (`internal-linking.yml`)

⏰ Daily at 11:30 PM PT. 📥 Pulls the Obsidian vault, uses Gemini AI to identify genuine book references in content files, inserts wikilinks, and pushes changes back to the vault. 📊 BFS traversal from the most recent reflection with incremental analysis tracking via `link_analysis_model` and `link_analysis_time` frontmatter. 📱 Operates directly on the vault — never writes to `content/`.

### 6. 🖼️ Backfill Blog Images (`backfill-blog-images.yml`)

⏰ Daily at 10:00 PM PT. 🔍 Finds blog posts missing cover images and generates them using a two-stage pipeline: Gemini describes the image → Cloudflare FLUX.1 Schnell generates it.

## 🧩 Key Scripts

| 📜 Script | 📝 Purpose |
|---|---|
| `scripts/internal-linking.ts` | 🔗 CLI for BFS-driven wikilink insertion |
| `scripts/generate-blog-post.ts` | 📝 AI blog post generation |
| `scripts/generate-blog-image.ts` | 🖼️ AI cover image generation |
| `scripts/auto-post.ts` | 📢 Social media orchestrator |
| `scripts/tweet-reflection.ts` | 📱 Platform-specific posting |
| `scripts/sync-file-to-obsidian.ts` | 📤 Single file vault sync |
| `scripts/pull-vault-posts.ts` | 📥 Pull posts from vault |
| `scripts/inject-static-giscus.ts` | 💬 SEO comment injection |
| `scripts/check-gemini-quota.ts` | 📊 API quota monitoring |
| `scripts/backfill-blog-images.ts` | 🖼️ Image backfill orchestrator |

## 📚 Library Modules (`scripts/lib/`)

| 📦 Module | 📝 Purpose |
|---|---|
| `internal-linking.ts` | 🔗 BFS traversal, Gemini book identification, wikilink insertion |
| `blog-image.ts` | 🖼️ Image generation pipeline (Cloudflare + Gemini) |
| `blog-series.ts` | 📝 Blog post generation with series context |
| `blog-prompt.ts` | 🤖 Prompt engineering for blog generation |
| `obsidian-sync.ts` | 📤 Obsidian vault pull/push via headless CLI |
| `frontmatter.ts` | 📋 YAML frontmatter parsing and note I/O |
| `gemini.ts` | 🤖 Gemini API client utilities |
| `gemini-quota.ts` | 📊 Quota checking via GCP APIs |
| `platforms/` | 📱 Platform-specific posting (Twitter, Bluesky, Mastodon) |
| `retry.ts` | 🔄 Exponential backoff retry logic |
| `text.ts` | ✂️ Text processing and truncation |
| `html.ts` | 🌐 HTML parsing utilities |
| `env.ts` | 🔧 Environment variable validation |
| `types.ts` | 📐 Shared domain types |

## 🔗 Internal Linking System

🧠 The internal linking system uses a **BFS-driven, AI-identification architecture** to insert wikilinks for book references, operating directly on the Obsidian vault.

### 📊 Pipeline

```
Pull Vault → BFS from Most Recent Reflection → For Each File:
  ├─ Check link_analysis_model (skip if already analyzed)
  ├─ Check force_analyze_links (override skip)
  ├─ Filter eligible books (not already linked)
  ├─ Gemini identifies genuine book references
  ├─ extractJsonArray handles messy AI responses
  ├─ Record link_analysis_model + link_analysis_time
  ├─ Find text positions (deterministic regex)
  ├─ Log diff (both dry-run and live)
  └─ Insert wikilinks → Push Vault
```

### 🔑 Key Design Decisions

- 📱 **Vault-native** — Reads from and writes to the Obsidian vault directly (`--content-dir` flag). The `content/` directory in the repo stays read-only.
- 🤖 **AI identifies, code positions** — Gemini receives the full document body + all available book titles and identifies which books are genuinely referenced as literary works. Deterministic regex matching only runs after AI confirmation.
- 📚 **Books-only index** — `LINKABLE_DIRS = ["books"]` constrains link targets to book pages, avoiding false positives from generic words matching topic or software pages.
- 🔒 **Incremental analysis** — Each analyzed file gets `link_analysis_model` and `link_analysis_time` frontmatter. Files with a `link_analysis_model` are skipped. Use `force_analyze_links: true` in frontmatter for manual re-analysis.
- 🔧 **Robust JSON parsing** — `extractJsonArray` handles Gemini responses wrapped in code fences, with trailing text, or other formatting quirks.
- 🛡️ **Rate-limit resilience** — Per-minute 429s trigger retry with exponential backoff. Daily quota exhaustion throws `QuotaExhaustedError` to halt the pipeline cleanly.
- 📊 **Summary statistics** — Completion log includes `filesVisited`, `filesModified`, `filesSkipped`, and `totalLinksAdded`.
- 📝 **Diff logging for all runs** — Both dry runs and live runs emit `diff` events with line-level changes.

## 🌐 Quartz Site Features

🏗️ The website at [bagrounds.org](https://bagrounds.org/) is built with Quartz 4 and includes:

- 🔊 **Text-to-Speech (TTS)** — Browser-based speech synthesis with play/pause controls, wake lock to prevent screen sleep during playback, and auto-play for continuous reading across pages.
- 💬 **Giscus Comments** — GitHub Discussions-backed comments on every page, with static HTML injection for search engine visibility.
- 🎮 **Interactive Games** — Games like [Valence](https://bagrounds.org/games/valence) built with Pixi.js, loaded as external static JS files.
- 🧮 **Interactive Tools** — Browser-based calculator and other utility pages.
- 🎨 **Solarized Theme** — Dark/light mode using the Solarized color palette.
- 📊 **OG Images** — Auto-generated Open Graph images for social sharing.
- 🔍 **Full-text Search** — FlexSearch-powered client-side search.
- 📡 **RSS Feed** — Full-HTML RSS with up to 1000 items.

## 🔧 Environment Variables

### 🔑 Secrets

| 🔐 Variable | 📝 Purpose |
|---|---|
| `GEMINI_API_KEY` | 🤖 Google Gemini API key (used by blog gen, social posting, internal linking, image description) |
| `CLOUDFLARE_API_TOKEN` | ☁️ Cloudflare Workers AI API token (image generation) |
| `CLOUDFLARE_ACCOUNT_ID` | ☁️ Cloudflare account identifier |
| `HUGGINGFACE_API_TOKEN` | 🤗 Hugging Face Inference API token (fallback image generation) |
| `OBSIDIAN_AUTH_TOKEN` | 📤 Obsidian headless sync authentication token |
| `OBSIDIAN_VAULT_NAME` | 📂 Name of the Obsidian vault to sync with |
| `OBSIDIAN_VAULT_PASSWORD` | 🔒 Obsidian vault encryption password (social posting only) |
| `TWITTER_API_KEY` | 🐦 Twitter/X API key |
| `TWITTER_API_SECRET` | 🐦 Twitter/X API secret |
| `TWITTER_ACCESS_TOKEN` | 🐦 Twitter/X access token |
| `TWITTER_ACCESS_SECRET` | 🐦 Twitter/X access secret |
| `BLUESKY_IDENTIFIER` | 🦋 Bluesky handle |
| `BLUESKY_APP_PASSWORD` | 🦋 Bluesky app password |
| `MASTODON_INSTANCE_URL` | 🐘 Mastodon instance URL |
| `MASTODON_ACCESS_TOKEN` | 🐘 Mastodon access token |
| `GCP_SERVICE_ACCOUNT_KEY` | ☁️ GCP service account JSON (quota monitoring) |
| `GITHUB_TOKEN` | 🔑 GitHub token (blog gen reads discussions, Giscus comments) |

### ⚙️ Configuration Variables (GitHub Repository Variables)

| 🔧 Variable | 📝 Default | 📝 Purpose |
|---|---|---|
| `BLOG_GEMINI_MODEL` | `gemini-3.1-flash-lite-preview` | 🤖 Model for blog post generation |
| `LINKING_MODEL` | `gemini-3.1-flash-lite-preview` | 🔗 Model for internal link identification |
| `IMAGE_GEMINI_MODEL` | `gemini-3.1-flash-image-preview` | 🖼️ Model for native image generation |
| `PROMPT_DESCRIBER_MODEL` | `gemini-3.1-flash-lite-preview` | 📝 Model for image prompt description |
| `CLOUDFLARE_IMAGE_MODEL` | `@cf/black-forest-labs/flux-1-schnell` | ☁️ Cloudflare image generation model |
| `HUGGINGFACE_IMAGE_MODEL` | `black-forest-labs/FLUX.1-schnell` | 🤗 Hugging Face image generation model |
| `GEMINI_MODEL` | `gemma-3-27b-it` | 📱 Model for social media post generation |
| `AUTO_BLOG_ZERO_PRIORITY_USER` | `bagrounds` | 👤 GitHub user for blog discussion priority |
| `CHICKIE_LOO_PRIORITY_USER` | `ChickieLoo` | 🐔 GitHub user for Chickie Loo priority |
| `DISABLE_TWITTER` | _(empty)_ | 🚫 Set to disable Twitter posting |
| `DISABLE_BLUESKY` | _(empty)_ | 🚫 Set to disable Bluesky posting |
| `DISABLE_MASTODON` | _(empty)_ | 🚫 Set to disable Mastodon posting |

## 🧪 Testing

```bash
# Run all tests
npx tsx --test scripts/**/*.test.ts scripts/*.test.ts quartz/**/*.test.ts

# Run specific test file
npx tsx --test scripts/lib/internal-linking.test.ts

# Type check
tsc --noEmit

# Format check
npx prettier . --check
```

📊 ~870+ tests across ~200 test suites covering internal linking, blog image generation, frontmatter parsing, text processing, social media posting, and Quartz components.

## 🏗️ Development

```bash
# Install dependencies
npm ci

# Build the Quartz site locally
npx quartz build --serve

# Run internal linking (dry run)
GEMINI_API_KEY=... npx tsx scripts/internal-linking.ts --dry-run --max-files 10

# Generate a blog post
GEMINI_API_KEY=... npx tsx scripts/generate-blog-post.ts --series auto-blog-zero

# Check Gemini API quota
GEMINI_API_KEY=... npx tsx scripts/check-gemini-quota.ts
```

## 📐 Design Principles

- 🏗️ **Strong static types** — TypeScript with strict mode, inspired by Haskell
- 🧩 **Functional declarative patterns** — `map`, `reduce`, `filter`, `flatMap` over loops; `const` over `let`; expression-oriented
- 🔧 **Unix philosophy** — Small, composable scripts with clear boundaries
- 📐 **Domain-driven design** — Explicit types for domain concepts
- 📖 **Self-documenting code** — Well-named functions and variables over comments
- 📱 **Obsidian vault is source of truth** — `content/` is read-only; all mutations flow through vault sync
- 🚫 **Never commit from workflows** — GitHub Actions use `contents: read` permissions only

## 📋 Specs

📄 Detailed product and engineering design specs live in `specs/`:

| 📄 Spec | 📝 Description |
|---|---|
| [`image-generation.md`](specs/image-generation.md) | 🖼️ Image generation pipeline — architecture, provider resolution, frontmatter schema, rate limiting, backfill prioritization |
