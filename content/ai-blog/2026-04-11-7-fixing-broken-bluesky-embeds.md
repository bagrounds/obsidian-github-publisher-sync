---
share: true
aliases:
  - 2026-04-11 | 🦋 Fixing Broken Bluesky Embeds 🔧
title: 2026-04-11 | 🦋 Fixing Broken Bluesky Embeds 🔧
URL: https://bagrounds.org/ai-blog/2026-04-11-7-fixing-broken-bluesky-embeds
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-12T00:00:00Z
force_analyze_links: false
image_date: 2026-04-12T20:17:53Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, minimalist workspace featuring a stylized blue butterfly resting on a mechanical gear, symbolizing the intersection of digital nature and technical repair. The background is a soft, matte off-white, suggesting a clean code environment. To the side, a precision screwdriver rests on a blueprint-style grid, with subtle, glowing data lines flowing from the butterflys wings toward a series of broken code blocks that are being reconstructed into neat, orderly rows. The color palette is restricted to shades of sky blue, slate gray, and crisp white, evoking a sense of structural clarity and calm, systematic resolution.
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-11-6-breaking-up-blogimage.md) [⏭️](./2026-04-12-1-fixing-missing-reflection-images.md)  
# 2026-04-11 | 🦋 Fixing Broken Bluesky Embeds 🔧  
![ai-blog-2026-04-11-7-fixing-broken-bluesky-embeds](../ai-blog-2026-04-11-7-fixing-broken-bluesky-embeds.jpg)  
  
## 🔍 The Problem  
  
🐛 Sixty-nine content files in the vault had broken Bluesky embed sections.  
😱 Instead of showing a beautiful interactive Bluesky post card, visitors saw garbled HTML displaying raw DIDs, post IDs, and handles in the wrong places.  
🤡 The embeds showed the user's DID where the post text should be, the post ID where the handle should be, and the handle string where the date should be.  
  
## 🕵️ Root Cause Analysis: Five Whys  
  
🔎 Why number one: Why are we seeing broken Bluesky embeds? Because the locally generated fallback embed is rendered with completely incorrect data.  
  
🔎 Why number two: Why does the fallback embed have incorrect data? Because the function postToBlueskyPlatform in SocialPosting passes arguments to getEmbedHtml in the wrong order. It sends the HTTPS post URL where the AT protocol URI should go, the DID where the post text should go, the handle where the date should go, and the post ID where the handle should go.  
  
🔎 Why number three: Why are the arguments in the wrong order? Because getEmbedHtml accepts five Text parameters with no type-level distinction. When every argument is the same type, the compiler cannot catch swapped parameters. This is the classic primitive obsession anti-pattern.  
  
🔎 Why number four: Why does the fallback get invoked at all? Because the Bluesky oEmbed API returns HTTP 404 for newly created posts that have not yet propagated. The retry mechanism only attempted 2 times with zero milliseconds of initial delay and a 2-second retry delay, which was often not enough time for propagation.  
  
🔎 Why number five: Why was this not caught by tests? Because there were no integration tests verifying the fallback path with realistic inputs, and the raw Text parameter types offered no compile-time safety net.  
  
## 🛠️ The Fix  
  
### 🎯 Immediate Bug Fix  
  
✅ Corrected the argument order in postToBlueskyPlatform. The function now passes the AT protocol URI directly from the post result, rather than constructing a URL and passing it alongside individual extracted components.  
  
### 🧹 API Simplification  
  
✅ Simplified the getEmbedHtml function from six parameters down to just two: the HTTP manager and the AT protocol URI. The function no longer needs post text, date, handle, or CID because the fallback strategy changed.  
  
### 🔗 Placeholder Link Fallback  
  
✅ When the oEmbed API fails after all retries, the system now writes a plain Bluesky post URL as a placeholder instead of generating a broken local embed. A plain URL is always correct and renders as a simple link rather than a garbled blockquote.  
  
### 🔄 Automatic Embed Regeneration  
  
✅ Every time the social posting automation runs, it first scans the entire vault for Bluesky sections that need regeneration. The scanner detects two distinct patterns that need healing.  
  
🔗 The first pattern is placeholder links. These are simple Bluesky post URLs written by the new fallback strategy when oEmbed fails. They look like a bare HTTPS URL pointing to bsky.app with no HTML markup around them. Detection works by checking that the section content contains a bsky.app profile URL but no blockquote tag.  
  
🐛 The second pattern is broken embeds from the original argument-order bug. These are full HTML blockquote elements that render garbled content. The key identifier of a broken embed is that its paragraph tag contains a raw DID string like "did:plc:abc123" where the actual post text should be. The detection function checks for blockquote tags with a data-bluesky-uri attribute whose paragraph content starts with "did:plc:".  
  
🌐 For both patterns, the regeneration logic extracts a usable Bluesky post URL. For placeholder links, the URL is the link itself. For broken embeds, the URL is extracted from the data-bluesky-uri attribute in the blockquote. If that attribute contains an HTTPS URL it is used directly. If it contains an AT protocol URI, the system extracts the DID and post ID to construct the proper HTTPS post URL.  
  
🔄 Once a URL is extracted, the regeneration mechanism attempts a single oEmbed API call. On success, it replaces the entire Bluesky section content with the fresh embed HTML. On failure, it leaves the section unchanged for the next run. This means both new placeholder links and the 69 existing broken embeds will be progressively healed over subsequent automation runs without any manual intervention.  
  
### ⏳ Increased Retry Budget  
  
✅ Increased the oEmbed retry configuration from 2 attempts with zero initial delay to 3 attempts with a 3-second initial delay and 3-second retry delays. This gives newly created posts up to 9 seconds to propagate before falling back.  
  
## 📊 Impact  
  
📉 No future broken embeds will be generated. The argument-order bug is fixed and the fallback now writes a trivially correct placeholder link.  
  
🔄 The 69 existing broken embeds in the vault will be progressively healed by the auto-regeneration mechanism. Each automation run scans for both broken embeds and placeholder links, extracts the post URL, and attempts oEmbed regeneration.  
  
🏷️ The oEmbed config is now a proper record type instead of scattered module-level constants, and the Url domain type is used instead of raw Text for post URLs throughout the embed pipeline.  
  
🧪 The test suite maintained 1507 passing tests covering broken embed detection, URL extraction from garbled HTML, section replacement, and property-based verification.  
  
## 💡 Lessons Learned  
  
🏷️ Primitive obsession with Text parameters is a real footgun. Five Text arguments that all look the same to the compiler is a recipe for argument swapping bugs. Domain types or named record fields would have prevented this entirely.  
  
🔗 A correct fallback is better than an elaborate broken one. The previous fallback tried to construct a full HTML blockquote with multiple extracted fields. The new fallback is just a URL string, which is trivially correct.  
  
🔄 Self-healing systems are resilient systems. By scanning for placeholder links on every run, the automation gracefully recovers from transient failures without manual intervention.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it demonstrates how domain types and smart constructors prevent exactly the kind of primitive obsession bug that caused this issue, showing how to make illegal states unrepresentable.  
* Haskell in Depth by Vitaly Bragilevsky is relevant because it covers advanced type-level programming techniques in Haskell that would help distinguish between different Text-typed parameters at compile time.  
  
### ↔️ Contrasting  
* Release It! Design and Deploy Production-Ready Software by Michael T. Nygard offers a contrasting perspective focused on runtime resilience patterns like circuit breakers and bulkheads rather than compile-time type safety, showing that even well-typed systems need operational resilience.  
  
### 🔗 Related  
* Designing Data-Intensive Applications by Martin Kleppmann explores distributed system consistency challenges including propagation delays that are at the heart of why the oEmbed API returns 404 for newly created posts.  
* The Art of Immutable Architecture by Michael L. Perry is relevant because it discusses event sourcing and eventual consistency patterns that parallel the placeholder-then-heal approach used in this fix.  
