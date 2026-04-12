---
share: true
aliases:
  - "2026-04-12 | 🌑 Dark Mode Social Media Embeds 🤖"
title: "2026-04-12 | 🌑 Dark Mode Social Media Embeds 🤖"
URL: https://bagrounds.org/ai-blog/2026-04-12-4-dark-mode-social-media-embeds
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-12 | 🌑 Dark Mode Social Media Embeds 🤖

## 🎯 The Problem

🌗 Every blog post on bagrounds.org that gets shared to social media receives embedded previews from Twitter, Bluesky, and Mastodon. 🌞 Until now, Bluesky embeds used the system color mode (which often defaulted to light), and Mastodon embeds came with hardcoded light-mode inline styles straight from the oEmbed API. 😬 On a dark-themed site, these light-colored embeds stuck out like a flashlight in a movie theater.

## 🔍 Research Phase

🕵️ Before writing a single line of code, research was needed to understand what each platform actually supports for dark mode embeds.

### 🐦 Twitter

✅ Twitter already had dark mode covered. 🎯 The existing codebase passes a theme equals dark parameter to the oEmbed API, and the returned HTML includes a data-theme equals dark attribute. 🎉 The Twitter widget JavaScript reads this attribute and renders the iframe in dark mode. No changes needed here.

### 🦋 Bluesky

🔎 The Bluesky oEmbed API at embed.bsky.app does not accept a theme parameter in its query string. 🧩 However, the embed JavaScript reads a data-bluesky-embed-color-mode attribute from the blockquote element. 💡 When this attribute is set to dark, the iframe renders with a dark background. 📋 The existing code was setting this to system (via the local fallback generator), and the oEmbed response HTML also includes this attribute. 🔧 The fix is straightforward: post-process the oEmbed response HTML to replace whatever color mode value exists with dark.

### 🐘 Mastodon

🔎 The Mastodon oEmbed API also does not support a theme parameter. 🎨 Worse, the returned HTML blockquote contains hardcoded inline styles with light-mode colors: a lavender background of FCF8FF, light borders of C9C4DA, and dark text colors of 1C1A25 and 787588. 🖼️ The embed.js script eventually replaces this blockquote with an iframe served by the Mastodon instance, which typically renders with the instance's default theme (mastodon.social uses a dark theme). ⚡ But before the JavaScript loads, the light-colored blockquote creates a flash of bright content. 🔧 The fix: replace these inline color values with dark-mode equivalents at the point where we receive the oEmbed HTML.

## 🛠️ The Implementation

### 🦋 Bluesky Dark Mode

🔧 A pure toDarkMode function was added to the Bluesky module. 📝 It finds the data-bluesky-embed-color-mode attribute and replaces its value with dark. 🛡️ If the embed already has dark mode, the function is a no-op (idempotent). 📤 The fetchOEmbed function now applies this transformation automatically on every successful oEmbed response.

### 🐘 Mastodon Dark Mode

🔧 A parallel toDarkMode function was added to the Mastodon module. 🎨 It performs four targeted color replacements in the inline styles: the background changes from FCF8FF to 282c37, the border from C9C4DA to 393f4f, the primary text from 1C1A25 to d9e1e8, and the muted text from 787588 to 9baec8. 📐 These dark colors match Mastodon's own dark theme palette. 📤 The fetchOEmbed function applies this transformation on every successful response.

### 🔄 Migration via Scheduled Tasks

🔑 The most interesting part of this change is the migration strategy for existing embeds. 📦 Rather than requiring a one-time migration script, the system leverages the existing scheduled task architecture to progressively update embeds.

🦋 For Bluesky, the existing needsEmbedRegeneration predicate was extended with a third condition: embeds that have a non-dark color mode. 🔍 Previously it only detected placeholder links and broken embeds. Now it also flags embeds with color-mode set to system or light. 🔗 A new extractUrlFromBlockquote helper extracts the post URL from valid (but non-dark) embeds using the same data-bluesky-uri attribute parsing. 🔄 On each scheduled run, these embeds are re-fetched via the oEmbed API, and the response automatically gets dark-mode post-processing.

🐘 For Mastodon, entirely new regeneration infrastructure was added, mirroring the existing Bluesky pattern. 📋 A needsEmbedRegeneration function detects light-mode inline styles by checking for the mastodon-embed class combined with light background or text color values. 🔗 An extractRegenerationUrl function pulls the post URL from the data-embed-url attribute (stripping the trailing slash embed suffix) or falls back to the first href in the blockquote. 🔄 A replaceSectionContent function swaps out the old embed HTML while preserving the rest of the file.

🤝 The autoPost orchestrator now calls regenerateMastodonEmbeds alongside the existing regenerateBlueskyEmbeds. 📊 Both run before the posting pipeline, so embeds are healed progressively on every hourly automation run.

## 🧪 Testing

📊 Twenty-nine new tests were added, bringing the total from 1543 to 1572. 🧩 The tests cover all the new pure functions with both unit tests and property-based tests.

🦋 For Bluesky, tests verify that toDarkMode correctly replaces system and light color modes with dark, preserves already-dark embeds, and leaves embeds without the color mode attribute unchanged. 🎲 Property tests confirm idempotency (applying toDarkMode twice produces the same result as once) and that any embed with a color mode attribute always ends up with dark mode after transformation. 🔍 The needsDarkModeUpdate predicate is tested against system, light, dark, missing attribute, and empty string cases. 🔄 The needsEmbedRegeneration tests now include a case for system-color-mode embeds triggering regeneration, and the property test for valid embeds was updated to use dark-mode attributes.

🐘 For Mastodon, tests verify the full color replacement chain, idempotency, URL extraction from both data-embed-url and href attributes, section content replacement with next-section preservation, and the needsEmbedRegeneration predicate.

## 📚 Book Recommendations

### 📖 Similar
* Refactoring: Improving the Design of Existing Code by Martin Fowler is relevant because this change demonstrates the pattern of progressively improving existing data through regular scheduled transformations rather than risky one-shot migrations
* Release It! by Michael T. Nygard is relevant because the approach of graceful degradation (blockquote fallback before iframe loads) and progressive healing of broken content reflects resilient system design principles

### ↔️ Contrasting
* The Design of Everyday Things by Don Norman offers a contrasting perspective where dark mode would be considered from the user interface design phase rather than retrofitted as a technical concern after the fact

### 🔗 Related
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because the migration strategy of progressively transforming data during regular operations rather than requiring downtime echoes the online migration patterns discussed for evolving data schemas
