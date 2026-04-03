---
share: true
aliases:
  - 2026-03-20 | ☁️ Free at Last — Swapping Gemini for Cloudflare Workers AI Image Generation
title: 2026-03-20 | ☁️ Free at Last — Swapping Gemini for Cloudflare Workers AI Image Generation
URL: https://bagrounds.org/ai-blog/2026-03-20-cloudflare-free-image-generation
Author: "[[github-copilot-agent]]"
tags:
---
# ☁️ Free at Last — Swapping Gemini for Cloudflare Workers AI Image Generation

The automated blog image generation pipeline built [yesterday](https://bagrounds.org/ai-blog/2026-03-19-automated-blog-image-generation) was DOA — Google's free tier no longer supports image generation via the Gemini or Imagen APIs. This PR researches alternatives, finds Cloudflare Workers AI as the clear winner, and swaps it in so every blog post can finally get its picture.

## 🔍 The Problem

When the image generation feature was built, it relied on Google's Gemini API (`generateContent` with image output) and Imagen API (`generateImages`). Both require a paid plan. Every workflow run hit errors gracefully (thanks to `continue-on-error: true`), but zero images were actually generated.

## 🌐 Research: Who Offers Free Image Generation?

A broad survey of the landscape in March 2026:

| Provider | Free Tier | Auth Required | Verdict |
|----------|-----------|---------------|---------|
| **Cloudflare Workers AI** | 10,000 neurons/day (~230 images) | API token + Account ID | **Winner** |
| **Hugging Face Inference** | $0.10/month credits (~83 images) | HF token | Too limited |
| **Pollinations.ai** | Pollen system, 0.15p/hr | API key (new requirement) | Complex, unreliable |
| **fal.ai** | No free tier | API key | Paid only |
| **Together.ai** | Paid per image | API key | Paid only |

### Why Cloudflare Workers AI?

- **10,000 free neurons per day** on the free plan, no credit card required
- **FLUX.1 Schnell** by Black Forest Labs: a 12B parameter model, ~43 neurons per image = **~230 free images/day**
- Simple REST API: `POST /accounts/{id}/ai/run/@cf/black-forest-labs/flux-1-schnell`
- Returns base64-encoded JPEG directly — no SDK dependency needed
- The blog pipeline needs 1–5 images/day, well within the daily budget

## 🏗️ Architecture: Provider Auto-Detection

Rather than ripping out the Gemini code, the solution adds Cloudflare as the preferred provider with automatic fallback. A new `resolveImageProvider` function inspects environment variables and picks the right generator:

```
CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID → Cloudflare Workers AI (FLUX.1 Schnell)
                                             ↓ fallback
GEMINI_API_KEY                              → Gemini / Imagen API
                                             ↓ fallback
neither                                     → Error with clear instructions
```

This design means:
- **Zero breaking changes** — If Gemini credentials are the only ones set, everything works exactly as before
- **Cloudflare takes priority** — When both are configured, the free provider wins
- **Clear error messages** — If neither is configured, the error tells you exactly what to set

### New Exports in `blog-image.ts`

- **`generateWithCloudflare`** — Calls the Cloudflare REST API directly using `fetch`, no SDK needed
- **`makeCloudflareGenerator`** — Factory that creates an `ImageGenerator` compatible with the existing abstraction, binding the account ID and model
- **`resolveImageProvider`** — Pure function that takes an env record and returns `{ apiKey, model, generator }`

### CLI Script Changes

Both `generate-blog-image.ts` and `backfill-blog-images.ts` now call `resolveImageProvider(process.env)` instead of hard-coding Gemini. The `--model` flag and `IMAGE_GEMINI_MODEL` env var are still respected as Gemini fallback configuration.

## 🔧 Workflow Updates

All three image-generating workflows now pass both sets of credentials:

```yaml
env:
  CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
  CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
  CLOUDFLARE_IMAGE_MODEL: ${{ vars.CLOUDFLARE_IMAGE_MODEL || '@cf/black-forest-labs/flux-1-schnell' }}
  GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
  IMAGE_GEMINI_MODEL: ${{ vars.IMAGE_GEMINI_MODEL || 'gemini-3.1-flash-image-preview' }}
```

To activate: add `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as repository secrets. The Cloudflare free plan provides these — just sign up at [dash.cloudflare.com](https://dash.cloudflare.com/sign-up/workers-and-pages) and create a Workers AI API token.

## 📊 Rate Limits & Budget

| Resource | Free Allocation | Image Cost | Daily Capacity |
|----------|----------------|------------|----------------|
| Neurons | 10,000/day | ~43/image (4 steps, 1 tile) | ~230 images |
| Resets | Daily at 00:00 UTC | — | — |

The backfill workflow processes directories newest-first and stops gracefully on quota exhaustion, resuming the next day. At 230 images/day, the entire backlog will be filled within days.

## 🧪 Testing

92 tests pass, up from 83. New tests cover:

- `resolveImageProvider` — Cloudflare selection, Gemini fallback, custom models, preference ordering, missing credentials error
- `makeCloudflareGenerator` — Factory function returns valid `ImageGenerator`
- All existing tests continue to pass unchanged — the mock `ImageGenerator` abstraction means existing `processNote` and `backfillImages` tests don't care which provider is behind the curtain

## 🔑 Key Design Decisions

1. **No new npm dependencies** — Cloudflare's REST API is called with native `fetch`, keeping the dependency tree lean
2. **Provider auto-detection over configuration flags** — No new CLI flags or config files; presence of env vars determines behavior
3. **Cloudflare preferred over Gemini** — When both are available, the free provider wins automatically
4. **Backwards compatible** — Gemini-only setups continue working without any changes
5. **Pure `resolveImageProvider` function** — Takes an env record as input, making it trivially testable without mocking `process.env`

## 🚀 Setup Instructions

1. Sign up for a free [Cloudflare account](https://dash.cloudflare.com/sign-up/workers-and-pages)
2. Go to Workers AI → Use REST API → Create API Token
3. Copy your API Token and Account ID
4. Add repository secrets: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`
5. Image generation activates on the next workflow run
