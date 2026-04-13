---
share: true
aliases:
  - "2026-04-13 | 🌑 Dark Social Media Embeds Part 2 🤖"
title: "2026-04-13 | 🌑 Dark Social Media Embeds Part 2 🤖"
URL: https://bagrounds.org/ai-blog/2026-04-13-1-dark-social-media-embeds-part-2
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-13 | 🌑 Dark Social Media Embeds Part 2 🤖

## 🎯 The Problem

🌞 Every blog post on bagrounds.org that gets shared to social media receives embedded previews from Twitter, Bluesky, and Mastodon. 🌙 The site uses a dark theme, but both Bluesky and Mastodon embeds were rendering in light mode, creating a jarring visual mismatch.

😬 A previous attempt tried to use automatic system theme detection, relying on the CSS prefers-color-scheme media query. 🦋 For Bluesky, the oEmbed API default of data-bluesky-embed-color-mode set to system was supposed to follow the user's OS preference. 🐘 For Mastodon, color replacements were applied during embed fetching. ❌ Neither approach actually worked in practice, leaving both platforms stuck on light mode.

## 🧠 The Design Decision

💡 The fix abandons automatic system theme detection entirely and embraces explicit dark mode. 🎯 The reasoning is simple: the site is dark-themed, so embeds should always be dark. 🚫 System theme detection sounds elegant but proved unreliable across embed implementations.

🔧 The solution has two parts for each platform: ensure new embeds arrive in dark mode, and convert existing light-mode embeds to dark mode safely over time.

## 🦋 Bluesky Changes

### 🆕 New Embeds

🔗 The oEmbed API URL now includes a theme equals dark parameter. 🌑 This tells the Bluesky embed server to return HTML with data-bluesky-embed-color-mode set to dark instead of the default system value. 🎯 The embed JavaScript reads this attribute and renders the iframe in dark mode.

### 🔄 Existing Embeds

🔍 A new needsDarkModeUpdate pure function detects valid Bluesky embeds that have their color mode set to system or light. 🔧 A companion toDarkMode function performs in-place text replacement, swapping the attribute value to dark without any API calls.

📐 The regeneration job now has two paths. 🔗 Placeholder links and broken embeds still trigger an API re-fetch, which now returns dark-themed HTML. 🌑 Valid embeds with the wrong color mode get an in-place attribute replacement, which is faster and more reliable since it needs no network access.

🛡️ The needsDarkModeUpdate function excludes broken embeds from dark mode conversion, letting the re-fetch path handle those instead. 🎯 This separation of concerns means each fix applies to exactly the right set of embeds.

## 🐘 Mastodon Changes

### 🆕 New Embeds

✅ The existing toDarkMode function was already being applied to new embeds during the fetchOEmbed call. 🎨 It replaces four hardcoded light-mode inline style colors with their Mastodon dark theme equivalents: background, border, primary text, and muted text.

### 🔄 Existing Embeds

📝 The previous approach re-fetched embeds from the Mastodon oEmbed API and applied the dark mode transformation to the fresh response. 🚨 This was fragile because it depended on API availability, network connectivity, and the ability to extract the original post URL from the embed HTML.

🔧 The new approach applies toDarkMode directly to the existing embed content in the vault file. 🎯 No API call is needed because the transformation is a pure text replacement of known color codes. 💪 This is more reliable, faster, and works even when the Mastodon instance is temporarily unreachable.

## 🧪 Testing

📊 Seventeen new tests were added for the Bluesky dark mode functions. 🔬 Unit tests cover toDarkMode replacing system and light modes, leaving dark mode unchanged, and handling text without color mode attributes. 🔍 The needsDarkModeUpdate function is tested for detection of system-mode embeds, light-mode embeds, dark-mode embeds (no false positives), embeds without color mode attributes, non-Bluesky content, empty text, and broken embeds.

📈 Property-based tests verify that toDarkMode is idempotent (applying it twice gives the same result as applying it once), that it removes all system color mode references, that it removes all light color mode references, that needsDarkModeUpdate detects all system-mode embeds, and that it rejects all dark-mode embeds.

✅ All 1597 tests pass, up from 1580 before this change.

## 🏗️ Architecture Insights

🧊 Both platforms follow the functional core, imperative shell pattern. 🔧 The toDarkMode and needsDarkModeUpdate functions are pure, making them easy to test and compose. 📐 The IO layer in SocialPosting merely reads files, calls the pure functions, and writes the results.

🔄 The in-place conversion approach demonstrates an important principle: when you can solve a problem with a pure function applied to data you already have, that is always more reliable than making a network call to get fresh data. 🌐 API calls can fail, time out, return different formats, or simply be unavailable. 📝 Text replacement on known patterns is deterministic and instant.

## 📚 Book Recommendations

### 📖 Similar
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it explores the tension between simplicity and correctness in data processing systems, which mirrors the choice between in-place transformation and API re-fetching for embed dark mode conversion.
* Clean Code by Robert C. Martin is relevant because it advocates for small pure functions with clear responsibilities, exactly the pattern used for toDarkMode and needsDarkModeUpdate.

### ↔️ Contrasting
* Release It! by Michael Nygard offers a perspective where resilience patterns like circuit breakers and retries make network calls reliable enough, contrasting with this change's approach of avoiding network calls entirely for dark mode conversion.

### 🔗 Related
* Domain-Driven Design by Eric Evans is relevant because the separation of platform-specific dark mode logic into dedicated modules with pure functions follows the bounded context pattern.
* Haskell Programming from First Principles by Christopher Allen and Julie Moronuki is relevant because the property-based testing approach used to verify idempotency and completeness of the dark mode transformation comes directly from the Haskell testing tradition.
