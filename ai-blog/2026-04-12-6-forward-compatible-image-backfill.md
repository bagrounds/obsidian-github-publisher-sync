---
share: true
aliases:
  - "2026-04-12 | 🖼️ Forward-Compatible Image Backfill & Propagation Delay 🏎️"
title: "2026-04-12 | 🖼️ Forward-Compatible Image Backfill & Propagation Delay 🏎️"
URL: https://bagrounds.org/ai-blog/2026-04-12-6-forward-compatible-image-backfill
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-12 | 🖼️ Forward-Compatible Image Backfill & Propagation Delay 🏎️

## 🎯 The Problem

🔍 Two related issues emerged in the automation pipeline that generates cover images for blog posts and decides when those posts are ready for social media.

📂 First, the image backfill system used a hardcoded Haskell sum type called ContentDirectory with exactly thirteen constructors, one for each known content directory. 🆕 Every time a new auto blog series was added through a JSON config file, someone had to manually add a new constructor to this type, update the round-trip text functions, and adjust the test count. 🚫 This was the opposite of forward-compatible.

🏎️ Second, when a note received a freshly generated image, the social posting system would immediately consider it ready to post. ⏰ But GitHub Pages deployments take time, so the image might not yet be live on the website when the social media post goes out. 👀 Followers clicking through would see a page without its cover image.

## 🔧 The Solution

### 🏷️ Extending ContentDirectory with AutoBlogSeries

🧠 The key insight was that the thirteen known content directories like Reflections, Books, and AiBlog are truly a closed set of well-known directories, but auto blog series are an open set discovered at runtime from JSON configs. 💡 Rather than abandon the strongly typed ContentDirectory ADT entirely, we added a single parameterized constructor: AutoBlogSeries Text. 🔒 This preserves type safety for the known directories while allowing new series to be represented without code changes.

🔀 The imageBackfillContentDirsFrom function now derives the full list of content directories by combining the known constructors with AutoBlogSeries wrappers around each discovered series identifier. 📦 The round-trip functions contentDirectoryToText and contentDirectoryFromText handle the mapping between the ADT and the filesystem directory names, falling back to AutoBlogSeries for any unrecognized name.

### 🔗 Threading ContentDirectory Through Social Posting

🐛 The autoPost and runPostingPipeline functions previously took a list of Text content identifiers, but the social posting image gate was not properly checking auto blog series directories. 🔧 Both functions now accept a list of ContentDirectory values. 📋 RunScheduled passes the same dynamically-computed list to both the image backfill task and the social posting task, ensuring consistent behavior.

### ⏰ Image Propagation Delay

🆕 A new noteImageDate field was added to the ContentNote record, storing a full UTCTime value parsed from the image_date frontmatter field. 🕐 This preserves second-level precision from the original timestamp rather than truncating to just a date.

🔍 The isAwaitingImageBackfill function was expanded to check not just whether a note lacks an image, but also whether it has an image generated too recently. 📏 If the time since image generation is less than 86400 seconds (one day), the note is still considered to be awaiting propagation. ✅ This gives GitHub Pages ample time to deploy the image before the note gets posted to social media.

### 🧹 Renaming Fields for Clarity

📛 All ContentNote fields were renamed from the abbreviated prefix pattern (cnFilePath, cnTitle, cnUrl) to full descriptive names (noteFilePath, noteTitle, noteUrl). 📖 This follows the no-abbreviations rule and makes the code more readable throughout the social posting module and all its callers.

## 🧪 Testing

🔬 All existing tests were updated for the new field names and ContentDirectory types. 📊 New tests verify the propagation delay behavior with second-precision timestamps, confirming that recently generated images defer posting and that images older than one day are considered propagated. ✅ All 1577 tests pass with zero hlint hints.

## 🎓 Lessons Learned

🏷️ When a set has a known core plus an open extension point, a sum type with a parameterized fallback constructor is the sweet spot between full static typing and stringly-typed systems. 🔒 The known constructors get exhaustive pattern matching while the fallback handles the dynamic portion.

🏎️ Race conditions between pipeline stages are easy to miss. 🔍 Image generation, website deployment, and social posting are three separate processes with no shared transaction boundary. ⏰ A simple time-based delay is more robust than checking the live website because it accounts for deployment queues, CDN propagation, and transient failures.

🕐 Preserving timestamp precision matters. 📅 Truncating a datetime to just a date loses the ability to reason about sub-day delays. 🔬 Using UTCTime with diffUTCTime provides exact elapsed-time arithmetic regardless of timezone.

## 📚 Book Recommendations

### 📖 Similar
* Domain-Driven Design by Eric Evans is relevant because this change exemplifies the tension between static domain types and dynamic configuration, a core DDD concern about when to use value objects versus raw identifiers.
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because the race condition fix addresses a classic distributed systems problem where eventual consistency between pipeline stages requires explicit synchronization.

### ↔️ Contrasting
* Types and Programming Languages by Benjamin C. Pierce offers the theoretical foundation for why sum types work well for closed sets, providing the counterpoint to the open extension problem solved here with a parameterized fallback constructor.

### 🔗 Related
* Release It! by Michael T. Nygard explores production stability patterns including the kind of timing-dependent failures that motivated the image propagation delay, covering circuit breakers, timeouts, and other resilience mechanisms.
