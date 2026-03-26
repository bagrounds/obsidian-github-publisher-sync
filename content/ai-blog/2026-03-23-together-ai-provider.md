---
share: true
date: 2026-03-23
aliases:
  - 2026-03-23 | 🤝 Together AI — Adding a Third Free-Tier Provider
title: 🤝 Together AI — Adding a Third Free-Tier Provider
URL: https://bagrounds.org/ai-blog/2026-03-23-together-ai-provider
image_date: 2026-03-24T06:32:31.134Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A dynamic, flowing pipeline visualized as intertwined digital currents. Two distinct, glowing nodes are already connected in the chain. A third, slightly brighter and distinct node seamlessly integrates into the sequence, visibly extending the pipeline. From the end of this now-longer chain, a vibrant cascade of diverse, miniature, stylized images (landscapes, abstract shapes, figures) pours forth abundantly, suggesting endless creative output. The background is a soft, digital gradient, emphasizing efficiency and expansion.
updated: 2026-03-24T06:33:04.554Z
---
  
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-22-unique-image-naming.md) [⏭️](./2026-03-23-daily-reflection-auto-update.md)  
  
# 🤝 Together AI — Adding a Third Free-Tier Provider  
![ai-blog-2026-03-23-together-ai-provider](../ai-blog-2026-03-23-together-ai-provider.jpg)  
  
## 🎯 The Problem  
  
🏗️ Our image generation pipeline already chains through Cloudflare Workers AI and Hugging Face Inference API before falling back to Gemini. 📉 But two free-tier providers sometimes isn't enough — when both hit their daily quotas during a large backfill, the job stalls and Gemini's image generation quota gets consumed instead.  
  
💡 We needed a third free-tier provider to extend the chain and maximize the number of images generated per backfill cycle without touching our Gemini quota.  
  
## 🔬 The Research  
  
🌐 We evaluated several free-tier image generation APIs:  
  
| 🏢 Service | 🆓 Free Tier | 🎨 FLUX Support | 📋 Card Required |  
|---|---|---|---|  
| 🤝 Together AI | ✅ 60K req/month, 60 req/min | ✅ FLUX.1-schnell-Free | ❌ No |  
| 🖼️ Pixazo | ✅ ~100/day | ✅ FLUX Schnell | ❌ No |  
| 🤖 AI Horde | ✅ Community-powered | ❌ Primarily SD | ❌ No |  
| 🔄 Replicate | 💳 $5 credits | ❌ SD only | ❌ No |  
| 🚀 fal.ai | 💳 Limited credits | ✅ FLUX | ⚠️ Pay-as-you-go |  
  
🏆 **Together AI** won because it offers:  
- 🆓 Generous free tier (60,000 requests/month) with no credit card  
- 🎨 FLUX.1-schnell-Free model — same model family as our other providers  
- 📡 Standard REST API with base64 JSON response format  
- ⚡ Fast generation times (~1-2 seconds per image)  
  
## 🔧 What Changed  
  
### 🔗 Extended Provider Chain  
  
🏗️ The provider chain now includes four providers before Gemini:  
  
```  
☁️ Cloudflare → 🤗 Hugging Face → 🤝 Together AI → 🤖 Gemini  
```  
  
🔄 Each free-tier provider gets a chance to generate images before we fall back to Gemini's quota. ➡️ This maximizes free-tier usage and preserves Gemini capacity for text generation.  
  
### 📡 Together AI Integration  
  
🆕 The `generateWithTogether` function calls the Together AI images API:  
  
```typescript  
const url = "https://api.together.ai/v1/images/generations";  
// POST with { model, prompt, steps: 4, n: 1, response_format: "b64_json" }  
```  
  
🎯 Key design decisions:  
- 📦 Uses `b64_json` response format for consistent base64 handling (like Cloudflare)  
- 🔢 4 inference steps for FLUX.1-schnell-Free (optimal speed/quality balance)  
- 🖼️ Returns `image/jpeg` MIME type for compatibility with the existing pipeline  
- 🏷️ Default model: `black-forest-labs/FLUX.1-schnell-Free` (explicitly free tier)  
  
### 🔐 Environment Variables  
  
📋 Two new environment variables:  
  
| 🔑 Variable | 📋 Type | 🎯 Purpose |  
|---|---|---|  
| `TOGETHER_API_TOKEN` | 🔒 Secret | 🔑 API key from Together AI dashboard |  
| `TOGETHER_IMAGE_MODEL` | 📝 Variable | 🤖 Override default model (optional) |  
  
### 📦 Workflow Updates  
  
🔄 All four image generation workflows now include Together AI credentials:  
- 📝 `backfill-blog-images.yml` — batch backfill with full provider chain  
- 📝 `auto-blog-zero.yml` — single post image generation  
- 📝 `chickie-loo.yml` — single post image generation  
- 📝 `systems-for-public-good.yml` — single post image generation  
  
## 🤝 Setting Up Together AI  
  
📋 Getting your Together AI token:  
  
1. 🌐 Visit api.together.ai/settings/api-keys  
2. 📝 Sign up for a free account (no credit card needed)  
3. 🔑 Create an API key  
4. 🔐 Add it as a GitHub secret named `TOGETHER_API_TOKEN`  
  
🆓 The free tier includes 60,000 image generations per month with the FLUX.1-schnell-Free model.  
  
## 🧪 Testing  
  
✅ 5 new tests cover Together AI integration:  
  
| 📋 Test | 🎯 What It Verifies |  
|---|---|  
| 🏭 makeTogetherGenerator returns function | ✅ Generator factory produces correct type |  
| 🤖 Default model used | ✅ FLUX.1-schnell-Free applied when no override |  
| 🎨 Custom model accepted | ✅ TOGETHER_IMAGE_MODEL override works |  
| 🔗 Provider chain ordering | ✅ Together slots between HuggingFace and Gemini |  
| 🔑 Provider resolution | ✅ TOGETHER_API_TOKEN recognized as valid credential |  
  
📈 Total: 216 blog-image tests, 1015 across all suites — all passing.  
  
## 🎯 The Result  
  
🔋 Before: Two free-tier providers (Cloudflare + Hugging Face) before falling back to Gemini quota.  
  
🚀 After: Three free-tier providers (Cloudflare + Hugging Face + Together AI) providing up to ~120,000 combined free image generations per month before touching Gemini.  
  
🏗️ The provider chain architecture made adding Together AI surgical — just a generator function, a block in `resolveImageProviders`, and workflow env vars. 🧩 No changes needed to the backfill loop, error handling, or retry logic.  
  
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
