---
title: 2026-03-23 | 🌸 Expanding the Image Pipeline and Adding Gemini Model Fallback
share: true
date: 2026-03-23
---

[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

# 2026-03-23 | 🌸 Expanding the Image Pipeline and Adding Gemini Model Fallback

## 🎯 The Problem

🏗️ Our image generation pipeline already chains through Cloudflare Workers AI and Hugging Face Inference API before falling back to Gemini. 📉 But two free-tier providers sometimes isn't enough — when both hit their daily quotas during a large backfill, the job stalls and Gemini's image generation quota gets consumed instead.

💡 We needed more free-tier providers to extend the chain and maximize the number of images generated per backfill cycle without touching our Gemini quota.

## 🔬 The Research

🌐 We evaluated several free-tier image generation APIs:

| 🏢 Service | 🆓 Free Tier | 🎨 FLUX Support | 📋 Key Required |
|---|---|---|---|
| 🌸 Pollinations.ai | ✅ Truly free, no limits | ✅ FLUX (default) | ❌ None at all |
| 🤝 Together AI | ⚠️ Credits-based (not truly free) | ✅ FLUX.1-schnell-Free | ✅ API key |
| 🖼️ Pixazo | ✅ ~100/day | ✅ FLUX Schnell | ✅ API key |
| 🤖 AI Horde | ✅ Community-powered | ❌ Primarily SD | ❌ Optional |
| 🚀 fal.ai | 💳 Limited credits | ✅ FLUX | ⚠️ Pay-as-you-go |

🌸 **Pollinations.ai** is the standout — truly free with no API key, no sign-up, no credit card. 🎯 Just a GET request to `https://image.pollinations.ai/prompt/{prompt}` returns an image directly.

🤝 **Together AI** was initially added as a free-tier provider, but deeper research revealed it no longer has a truly free tier. 🏗️ The code remains in the chain because our architecture gracefully skips providers that fail to authenticate.

## 🔧 What Changed

### 🔗 Extended Provider Chain

🏗️ The provider chain now includes five providers before Gemini:

```
☁️ Cloudflare → 🤗 Hugging Face → 🤝 Together AI → 🌸 Pollinations → 🤖 Gemini
```

🔄 Each provider gets a chance to generate images before we fall back to the next. ➡️ Pollinations.ai acts as a reliable safety net since it requires no credentials at all.

### 🌸 Pollinations.ai Integration

🆕 The `generateWithPollinations` function uses a simple GET request:

```typescript
const url = `https://image.pollinations.ai/prompt/${encodedPrompt}?model=${model}&width=1024&height=1024&nologo=true`;
```

🎯 Key design decisions:
- 📡 Simple GET request returns image binary directly (no JSON parsing)
- 🔑 No API key needed — the generator ignores the `apiKey` parameter entirely
- 🖼️ Reads MIME type from response `content-type` header
- 🏷️ Default model: `flux` (Pollinations' recommended model)
- 🎛️ Enabled via `POLLINATIONS_ENABLED=true` env var (opt-in to keep the chain explicit)

### 🤝 Together AI Integration

🆕 The `generateWithTogether` function calls the Together AI images API:

```typescript
const url = "https://api.together.ai/v1/images/generations";
// POST with { model, prompt, steps: 4, n: 1, response_format: "b64_json" }
```

🎯 Key design decisions:
- 📦 Uses `b64_json` response format for consistent base64 handling
- 🏷️ Default model: `black-forest-labs/FLUX.1-schnell-Free`
- ⚠️ Requires `TOGETHER_API_TOKEN` — gracefully skipped if not set

### 🔐 Environment Variables

📋 New environment variables:

| 🔑 Variable | 📋 Type | 🎯 Purpose |
|---|---|---|
| `POLLINATIONS_ENABLED` | 📝 Variable | 🔛 Set to `true` to enable (no key needed) |
| `POLLINATIONS_IMAGE_MODEL` | 📝 Variable | 🤖 Override default model (optional) |
| `TOGETHER_API_TOKEN` | 🔒 Secret | 🔑 API key from Together AI dashboard |
| `TOGETHER_IMAGE_MODEL` | 📝 Variable | 🤖 Override default model (optional) |

### 📦 Workflow Updates

🔄 All four image generation workflows now include both providers:
- 📝 `backfill-blog-images.yml` — batch backfill with full provider chain
- 📝 `auto-blog-zero.yml` — single post image generation
- 📝 `chickie-loo.yml` — single post image generation
- 📝 `systems-for-public-good.yml` — single post image generation

## 🔄 Gemini Model Fallback

### 🎯 The Problem

⚠️ The `gemini-3.1-flash-lite-preview` model is used across several text inference tasks — social media question generation and image prompt description. 🧪 Being a preview model, it can fail intermittently or become unavailable.

### 🔧 The Solution

🛡️ Added automatic model fallback: when `gemini-3.1-flash-lite-preview` fails, the system retries with `gemini-2.5-flash` before propagating the error.

📋 Affected areas:
- 🐦 **Social media posting** — the question model in `generatePostWithGemini()` now uses `callWithFallback()` that catches errors and retries with the fallback model
- 🖼️ **Image prompt description** — `describeImageWithGemini()` now catches errors and retries with the fallback model

🏗️ Implementation:
- 📦 `geminiModelFallback()` in `types.ts` — pure function mapping `gemini-3.1-flash-lite-preview` → `gemini-2.5-flash`
- 🔄 `callWithFallback()` in `gemini.ts` — wraps model creation + `callGemini()` with fallback
- 🔄 `attemptGeneration()` in `blog-image.ts` — extracts the generation call for reuse with fallback

## 🧪 Testing

✅ 18 new tests cover image providers and model fallback:

| 📋 Test | 🎯 What It Verifies |
|---|---|
| 🌸 makePollinationsGenerator returns function | ✅ Generator factory produces correct type |
| 🌸 Default model used | ✅ `flux` applied when no override |
| 🌸 Custom model accepted | ✅ POLLINATIONS_IMAGE_MODEL override works |
| 🌸 Provider resolution | ✅ POLLINATIONS_ENABLED=true adds to chain |
| 🌸 Not included when disabled | ✅ POLLINATIONS_ENABLED≠true excludes it |
| 🤝 makeTogetherGenerator returns function | ✅ Generator factory produces correct type |
| 🤝 Default model used | ✅ FLUX.1-schnell-Free applied when no override |
| 🤝 Custom model accepted | ✅ TOGETHER_IMAGE_MODEL override works |
| 🔗 Full chain ordering | ✅ CF → HF → Together → Pollinations → Gemini |
| 🔑 Describer attached to all | ✅ All providers get describePrompt when Gemini key set |
| 🔄 GEMINI_FLASH_FALLBACK constant | ✅ Maps to gemini-2.5-flash |
| 🔄 Fallback for flash-lite-preview | ✅ Returns gemini-2.5-flash |
| 🔄 No fallback for gemma | ✅ Returns undefined |
| 🔄 No fallback for gemini-2.5-flash | ✅ Returns undefined |
| 🔄 No self-fallback | ✅ gemini-2.5-flash returns undefined |
| 🔄 No fallback for arbitrary model | ✅ Returns undefined |
| 🔄 DEFAULT_DESCRIBER_MODEL has fallback | ✅ Fallback is defined for the describer default |

📈 Total: 223 blog-image tests, 28 gemini tests, 1028 across all suites — all passing.

## 🎯 The Result

🔋 Before: Two free-tier providers (Cloudflare + Hugging Face) before falling back to Gemini quota.

🚀 After: More providers in the chain, with Pollinations.ai as a truly free safety net that requires zero setup. 🌸 Even if every other provider is exhausted or misconfigured, Pollinations will still generate images.

🏗️ The provider chain architecture made adding both providers surgical — just a generator function, a block in `resolveImageProviders`, and workflow env vars. 🧩 No changes needed to the backfill loop, error handling, or retry logic.

## 📚 Book Recommendations

### 📖 Similar
- 🔧 *Release It!* by Michael Nygard — designing resilient systems with fallback chains and circuit breakers
- 🏗️ *Building Microservices* by Sam Newman — service decomposition and multi-provider integration patterns

### 🔄 Contrasting
- 🎯 *The Art of Simplicity* by Dominique Loreau — sometimes one provider is enough, if you choose the right one
- 📐 *A Philosophy of Software Design* by John Ousterhout — deep modules over wide interfaces

### 🎨 Creatively Related
- 🖼️ *Ways of Seeing* by John Berger — how we perceive and generate images across different mediums
- 🧠 *The Master Algorithm* by Pedro Domingos — the quest for a universal learning machine that bridges all approaches
