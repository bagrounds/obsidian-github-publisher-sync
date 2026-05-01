---
share: true
aliases:
  - 2026-04-04 | 🖼️ Reflection Image Timing Fix 🕐
title: 2026-04-04 | 🖼️ Reflection Image Timing Fix 🕐
URL: https://bagrounds.org/ai-blog/2026-04-04-reflection-image-timing-fix
image_date: 2026-04-05T17:16:32Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, high-contrast illustration featuring a stylized analog clock face floating against a soft, gradient background transitioning from deep indigo to warm amber. The clock’s hands are frozen at 10:00. Below the clock, a series of abstract, geometric paper-like rectangles—representing blog post notes—are scattered. Most of the rectangles are blank and grayscale, while one central rectangle is vibrant, colorful, and detailed, symbolizing the note that has finally received its creative title. Subtle, glowing digital particles drift upward toward the clock, representing the synchronization of the image backfill process. The overall aesthetic is clean, modern, and tech-focused, using a palette of deep blues, crisp whites, and a single accent of golden yellow to emphasize the fixed timing.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-20T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-04-1-page-based-updates-section.md) [⏭️](./2026-04-05-1-expanding-the-image-backfill-horizon.md)  
# 2026-04-04 | 🖼️ Reflection Image Timing Fix 🕐  
![ai-blog-2026-04-04-2-reflection-image-timing-fix](../ai-blog-2026-04-04-2-reflection-image-timing-fix.jpg)  
  
## 🐛 The Bug  
  
🔍 Daily reflections were getting cover images generated too early, before the creative title was assigned.  
  
📅 Each reflection starts the day with a bare date as its title, like 2026-04-04.  
  
🎨 The image backfill job runs every hour, scanning for notes that need images.  
  
🕙 The reflection-title task runs at 10 PM Pacific, generating a creative, emoji-enriched title based on the full day's content.  
  
⏰ Because the image backfill saw a non-empty title (the bare date), it generated an image immediately, hours before the creative title would arrive.  
  
## 🔬 Root Cause Analysis  
  
🧪 The processNote function in BlogImage decides whether to generate an image for a note.  
  
✅ It checks three conditions before proceeding: does the note already have an image, does it have a title, and can we derive a base name for the image file.  
  
🚫 The title check was simply whether the title text was empty.  
  
📝 Reflections always have a title from creation, set to the date string in their frontmatter.  
  
💡 So the empty-title guard never fired for reflections, and images were generated as soon as the note existed.  
  
## 🔧 The Fix  
  
🎯 We added a new function called isDateOnlyTitle that checks whether a note's extracted title is exactly equal to the date string.  
  
🧩 The candidate collection step, checkCandidate, now skips reflections whose title is still just the bare date.  
  
⏳ This means reflections only become image candidates after the reflection-title task has assigned a creative title at 10 PM Pacific.  
  
🔄 Once the creative title is in place, the next backfill run picks up the reflection and generates an image that reflects the full day's content.  
  
## 🧪 Testing  
  
✅ Seven new unit tests cover the isDateOnlyTitle function.  
  
🔍 Tests verify that date-only titles are correctly detected for both bare and quoted frontmatter values.  
  
🎭 Tests also confirm that creative titles (containing pipes, emojis, or descriptive text beyond the date) are NOT treated as date-only.  
  
📊 All 778 tests pass, up from 771 before the change.  
  
## 🏗️ Design Decisions  
  
🤔 We considered adding the guard in processNote itself, which is the single entry point for all image generation.  
  
📍 Instead, we placed it in checkCandidate, the candidate filtering step, because that function already knows the directory identity and has the right abstraction level for filtering logic.  
  
🧠 The isDateOnlyTitle function mirrors the logic already present in reflectionNeedsTitle from the ReflectionTitle module, maintaining consistency in how we determine whether a reflection has its creative title.  
  
🔒 This approach is safe because reflections are only processed through the backfill pipeline, never through single-post workflows.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Release It! by Michael T. Nygard is relevant because it covers designing systems that handle timing dependencies and scheduling gracefully, much like our reflection pipeline ordering.  
* A Philosophy of Software Design by John Ousterhout is relevant because it emphasizes reducing complexity through clear abstractions, which directly relates to our decision about where to place the guard logic.  
  
### ↔️ Contrasting  
* Move Fast and Break Things by Jonathan Taplin offers a perspective where speed of iteration trumps correctness, contrasting with our careful ordering of title generation before image generation.  
  
### 🔗 Related  
* [🧩🧱⚙️❤️ Domain-Driven Design: Tackling Complexity in the Heart of Software](../books/domain-driven-design.md) by Eric Evans explores how business rules should be encoded close to the domain model, which is exactly what we did by encoding the title-readiness check in the candidate filtering logic.  
