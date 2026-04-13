---
share: true
aliases:
  - 2026-04-12 | 🌑 Dark Mode Social Media Embeds 🤖
title: 2026-04-12 | 🌑 Dark Mode Social Media Embeds 🤖
URL: https://bagrounds.org/ai-blog/2026-04-12-4-dark-mode-social-media-embeds
image_date: 2026-04-12T23:19:02Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-contrast, minimalist composition centered on the concept of digital transformation. A sleek, glowing smartphone screen floats in deep space, split vertically down the middle. The left side of the screen shows a bright, jarring white blockquote with grey text, representing the original Mastodon embed. The right side shows a seamless, elegant transition where the same content is rendered in a soft, sophisticated dark-mode palette of charcoal, slate blue, and muted silver. A subtle, glowing stream of binary code or data particles flows from the left to the right, transforming the colors as they pass through the center divide. The background is a dark, atmospheric void with soft, ambient lighting that emphasizes the glowing digital interface.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-12T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-12-3-launching-positivity-bias-a-new-auto-blog-series.md) [⏭️](./2026-04-12-5-working-entirely-in-pacific-time.md)  
# 2026-04-12 | 🌑 Dark Mode Social Media Embeds 🤖  
![ai-blog-2026-04-12-4-dark-mode-social-media-embeds](../ai-blog-2026-04-12-4-dark-mode-social-media-embeds.jpg)  
  
## 🎯 The Problem  
  
🌗 Every blog post on bagrounds.org that gets shared to social media receives embedded previews from Twitter, Bluesky, and Mastodon. 🌞 Mastodon embeds came with hardcoded light-mode inline styles straight from the oEmbed API. 😬 On a dark-themed site, these light-colored embeds stuck out like a flashlight in a movie theater.  
  
## 🔍 Research Phase  
  
🕵️ Before writing a single line of code, research was needed to understand what each platform actually supports for dark mode embeds.  
  
### 🐦 Twitter  
  
✅ Twitter already had dark mode covered. 🎯 The existing codebase passes a theme equals dark parameter to the oEmbed API, and the returned HTML includes a data-theme equals dark attribute. 🎉 The Twitter widget JavaScript reads this attribute and renders the iframe in dark mode. No changes needed here.  
  
### 🦋 Bluesky  
  
🔎 The Bluesky oEmbed API returns HTML with a data-bluesky-embed-color-mode attribute. 🧩 The embed JavaScript reads this attribute and supports three values: system, light, and dark. 💡 The system value uses the CSS prefers-color-scheme media query to follow the user's OS or browser dark mode preference. 🌗 Since the Quartz site also defaults to the OS preference (via window.matchMedia in its darkmode script), Bluesky's system mode stays in sync with the website theme for the vast majority of visitors. ✅ No changes were needed here because the oEmbed API already returns system mode by default, which is the ideal behavior.  
  
### 🐘 Mastodon  
  
🔎 The Mastodon oEmbed API does not support a theme parameter or system-based color mode. 🎨 The returned HTML blockquote contains hardcoded inline styles with light-mode colors: a lavender background of FCF8FF, light borders of C9C4DA, and dark text colors of 1C1A25 and 787588. 🖼️ The embed.js script eventually replaces this blockquote with an iframe served by the Mastodon instance, which typically renders with the instance's default theme (mastodon.social uses a dark theme). ⚡ But before the JavaScript loads, the light-colored blockquote creates a flash of bright content. 🔧 The fix: replace these inline color values with dark-mode equivalents at the point where we receive the oEmbed HTML.  
  
## 🛠️ The Implementation  
  
### 🐘 Mastodon Dark Mode  
  
🔧 A toDarkMode pure function was added to the Mastodon module. 🎨 It performs four targeted color replacements in the inline styles: the background changes from FCF8FF to 282c37, the border from C9C4DA to 393f4f, the primary text from 1C1A25 to d9e1e8, and the muted text from 787588 to 9baec8. 📐 These dark colors match Mastodon's own dark theme palette. 📤 The fetchOEmbed function applies this transformation on every successful response.  
  
### 🔄 Migration via Scheduled Tasks  
  
🔑 The most interesting part of this change is the migration strategy for existing Mastodon embeds. 📦 Rather than requiring a one-time migration script, the system leverages the existing scheduled task architecture to progressively update embeds.  
  
🐘 New regeneration infrastructure was added, mirroring the existing Bluesky regeneration pattern. 📋 A needsEmbedRegeneration function detects light-mode inline styles by checking for the mastodon-embed class combined with light background or text color values. 🔗 An extractRegenerationUrl function pulls the post URL from the data-embed-url attribute (stripping the trailing slash embed suffix) or falls back to the first href in the blockquote. 🔄 A replaceSectionContent function swaps out the old embed HTML while preserving the rest of the file.  
  
🤝 The autoPost orchestrator now calls regenerateMastodonEmbeds alongside the existing regenerateBlueskyEmbeds. 📊 Both run before the posting pipeline, so embeds are healed progressively on every hourly automation run.  
  
## 🧪 Testing  
  
📊 Eighteen new tests were added, bringing the total from 1543 to 1561. 🧩 The tests cover all the new pure functions with both unit tests and property-based tests.  
  
🐘 For Mastodon, tests verify the full color replacement chain, idempotency, URL extraction from both data-embed-url and href attributes, section content replacement with next-section preservation, and the needsEmbedRegeneration predicate.  
  
🦋 For Bluesky, the existing needsEmbedRegeneration tests were expanded to confirm that valid system-mode embeds are correctly left alone.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Refactoring: Improving the Design of Existing Code by Martin Fowler is relevant because this change demonstrates the pattern of progressively improving existing data through regular scheduled transformations rather than risky one-shot migrations  
* Release It! by Michael T. Nygard is relevant because the approach of graceful degradation (blockquote fallback before iframe loads) and progressive healing of broken content reflects resilient system design principles  
  
### ↔️ Contrasting  
* [💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md) by Don Norman offers a contrasting perspective where dark mode would be considered from the user interface design phase rather than retrofitted as a technical concern after the fact  
  
### 🔗 Related  
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because the migration strategy of progressively transforming data during regular operations rather than requiring downtime echoes the online migration patterns discussed for evolving data schemas  
