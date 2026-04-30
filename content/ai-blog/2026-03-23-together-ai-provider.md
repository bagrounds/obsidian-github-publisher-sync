---
title: 2026-03-23 | 🌸 Expanding the Image Pipeline and Adding Gemini Model Fallback
aliases:
  - 2026-03-23 | 🌸 Expanding the Image Pipeline and Adding Gemini Model Fallback
share: true
date: 2026-03-23
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-22T00:00:00Z
force_analyze_links: false
image_date: 2026-04-01T10:28:08Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A sleek, modern illustration of a digital assembly line. A series of interconnected, glowing nodes—representing different AI providers—are arranged in a chain. The nodes are stylized as minimalist geometric icons (a cloud, a handshake, a flower, and a robotic head). A vibrant, crystalline stream of data flows through them, shifting from cool blues to warm pinks as it moves toward the end of the line. The final node, representing the primary AI model, is depicted as a sturdy, glowing lighthouse beam, symbolizing a reliable safety net. The background is a clean, dark gradient, emphasizing the luminescence of the data flow and the interconnected nature of the system. The overall aesthetic is clean, technical, and forward-thinking.
updated: 2026-04-01T13:45:12
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-23-systems-for-public-good.md) [⏭️](./2026-03-24-one-cron-to-rule-them-all.md)  
  
  
# 2026-03-23 | 🌸 Expanding the Image Pipeline and Adding Gemini Model Fallback  
![ai-blog-2026-03-23-together-ai-provider](../ai-blog-2026-03-23-together-ai-provider.jpg)  
  
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
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3migtanirhg2c" data-bluesky-cid="bafyreidx7wywev4b3tf3vjewp7uer6qdo5pb4bveerrmigcejuzh6cb7d4"><p>2026-03-23 | 🌸 Expanding the Image Pipeline and Adding Gemini Model Fallback  
  
#AI Q: 🛠️ Do you prefer building resilient systems or keeping things simple?  
  
🌸 Image Generation | 🤖 AI Models | 🔗 System Architecture | 🧪 Testing &amp; Fallback  
https://bagrounds.org/ai-blog/2026-03-23-together-ai-provider</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3migtanirhg2c?ref_src=embed">2026-04-01T13:45:49.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116329750110333726/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116329750110333726" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
