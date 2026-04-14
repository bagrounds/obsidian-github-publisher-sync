---
share: true
aliases:
  - 2026-04-13 | 🦋 Fixing Bluesky Link Facet Offsets 🔗
title: 2026-04-13 | 🦋 Fixing Bluesky Link Facet Offsets 🔗
URL: https://bagrounds.org/ai-blog/2026-04-13-4-fixing-bluesky-link-facet-offsets
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-14T00:00:00Z
force_analyze_links: false
image_date: 2026-04-14T08:41:45Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, minimalist illustration featuring a stylized blue butterfly hovering over a digital landscape. The butterfly’s wings are composed of geometric, interconnected data nodes and binary sequences, symbolizing the AT Protocol. Below, a series of uneven, misaligned blue blocks representing broken text facets are being corrected by a glowing, precise digital ruler or grid overlay. The background is a soft, deep gradient of charcoal and navy, with subtle floating UTF-8 character symbols and byte-length markers scattered like dust particles in light. The composition emphasizes technical precision, clarity, and the transition from chaotic, misaligned data to structured, orderly code.
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-13-3-daily-updates-table-redesign.md)  
# 2026-04-13 | 🦋 Fixing Bluesky Link Facet Offsets 🔗  
![ai-blog-2026-04-13-4-fixing-bluesky-link-facet-offsets](../ai-blog-2026-04-13-4-fixing-bluesky-link-facet-offsets.jpg)  
  
## 🐛 The Bug  
  
🔵 On Bluesky, link URLs in posts were visually misaligned.  
👀 A few characters before the URL appeared blue, and a few characters at the end of the URL were not blue.  
🧠 The link card embed below the post worked fine, but the inline URL text had broken highlighting.  
  
## 🔍 Root Cause Analysis  
  
🏗️ Bluesky uses the AT Protocol, which requires explicit byte-offset annotations called facets for rich text.  
📏 Every URL in a post needs a facet specifying its exact UTF-8 byte start and byte end positions.  
🔢 The original implementation split the post text into words using a standard text splitting function, then walked through tokens, adding 1 byte per gap between words to track positions.  
  
### 🤔 Why Did the Offsets Drift?  
  
1️⃣ The text splitting function collapses all whitespace into single separators, whether the original text had one space, one newline, or two newlines.  
2️⃣ The assembled post text uses double newlines between the title, question, and tags sections, creating visual paragraph breaks.  
3️⃣ Each double newline is 2 bytes, but the code only counted 1 byte per gap, so the calculated position fell behind by 1 byte per collapsed newline.  
4️⃣ With two paragraph breaks before the URL, the byte offset was 2 bytes too low, making the facet start 2 characters before the URL and end 2 characters before the URL end.  
5️⃣ This was never caught because the facet detection had no tests, and the drift is only noticeable when the text has multi-byte whitespace gaps before the URL.  
  
## 🔧 The Fix  
  
🎯 Replaced the word-splitting approach with direct URL search.  
🔎 The new implementation scans the text for protocol prefixes like https colon slash slash and http colon slash slash.  
📐 For each URL found, it encodes the prefix text before the URL into UTF-8 bytes and measures the byte length directly.  
✅ This avoids any assumptions about whitespace normalization and produces correct byte offsets regardless of how many newlines, spaces, or emoji characters appear before the URL.  
  
## 🧪 Testing  
  
📋 Added 12 unit tests covering URL detection at the start, middle, and end of text.  
🔢 Tests verify correct byte offsets with single newlines, double newlines, and multi-byte emoji characters.  
🐛 One test reproduces the exact bug scenario from the issue, with emojis and double newlines matching the real post format.  
🎲 Added 2 property-based tests: one verifying that byte offsets correctly slice the URL from encoded text for arbitrary prefixes, and another verifying that text without protocol prefixes produces no facets.  
  
## 💡 Lessons Learned  
  
📏 When working with byte offsets, never assume whitespace is a single byte, especially when the text may contain newlines, tabs, or other multi-byte sequences.  
🧩 Text splitting functions that normalize whitespace are useful for tokenization but dangerous for position tracking.  
🔬 Pure functions that compute byte offsets should always be tested with property-based tests, since edge cases with multi-byte characters and mixed whitespace are easy to miss.  
🏗️ The AT Protocol documentation is explicit about using UTF-8 byte offsets, not character offsets, which is an important distinction when working with emoji-heavy social media text.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Haskell Programming from First Principles by Christopher Allen and Julie Moronuki is relevant because it teaches the functional programming fundamentals used to build the facet detection logic, including pattern matching, recursion, and pure function design  
* Programming in Haskell by Graham Hutton is relevant because it covers text processing and byte-level manipulation in Haskell, directly applicable to UTF-8 encoding work  
  
### ↔️ Contrasting  
* The Art of Readable Code by Dustin Boswell and Trevor Foucher offers a perspective on code clarity that contrasts with the byte-level precision required for protocol compliance, reminding us that readability and correctness must coexist  
  
### 🔗 Related  
* Designing Data-Intensive Applications by Martin Kleppmann explores protocol design and data encoding formats, providing context for why the AT Protocol requires explicit byte offsets rather than auto-detecting links server-side  
* Real World Haskell by Bryan O'Sullivan, Don Stewart, and John Goerzen covers practical Haskell programming including ByteString and Text encoding, directly relevant to the UTF-8 byte offset calculations in this fix  
