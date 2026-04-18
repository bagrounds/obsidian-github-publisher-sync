---
share: true
aliases:
  - 2026-04-17 | 🚫 Excluding Changes Pages from Social Posting 🤖
title: 2026-04-17 | 🚫 Excluding Changes Pages from Social Posting 🤖
URL: https://bagrounds.org/ai-blog/2026-04-17-2-exclude-changes-from-social-posting
image_date: 2026-04-17T23:23:56Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, top-down isometric illustration of a digital assembly line. A stream of glowing, rectangular data blocks moves along a conveyor belt. Most blocks are vibrant and pulse with light, representing shareable content. Intercepting the path is a clean, modern robotic arm equipped with a soft-edged geometric filter that gently diverts monochromatic, text-heavy list pages into a side storage bin. The background is a soft, neutral slate gray, emphasizing the contrast between the active data stream and the sidelined documents. The lighting is crisp and cool, utilizing subtle blue and teal accents to evoke a sense of automated precision and systematic organization.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-04-17T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-17-1-fixing-wrong-arrows-in-changes-pages.md)  
# 2026-04-17 | 🚫 Excluding Changes Pages from Social Posting 🤖  
![ai-blog-2026-04-17-2-exclude-changes-from-social-posting](../ai-blog-2026-04-17-2-exclude-changes-from-social-posting.jpg)  
  
## 🎯 The Problem  
  
📂 The site has a changes directory that contains daily pages listing which content was updated. 📋 These pages are auto-generated lists of links, not original content worth sharing on social media. 🤖 The social posting pipeline was treating them like any other content page, meaning they could end up being posted to Twitter, Bluesky, or Mastodon during the breadth-first content discovery process.  
  
## 🔍 How Social Posting Filters Work  
  
🧭 The social posting system uses a breadth-first search starting from the most recent daily reflection, following markdown links to discover content worth sharing. 🛡️ At each node, two layers of filtering decide whether a page gets posted.  
  
🔬 The first layer is BFS eligibility, which is checked via the checkBfsEligibility function. 📄 Index pages are never eligible. 📓 Reflection pages have time-based eligibility rules. 📝 Everything else was previously considered eligible.  
  
🧪 The second layer is the isPostableContent function, which checks whether a note meets the minimum bar for social sharing. 📏 It rejects index pages, untitled reflections, notes flagged with no_social in their frontmatter, notes with bodies shorter than 50 characters, and notes awaiting image backfills.  
  
## 🔧 The Fix  
  
✂️ The fix adds a new isChangesPath function that checks whether a file path starts with the changes directory prefix. 🏗️ This function follows the same pattern as isReflectionPath, which checks for the reflections directory prefix.  
  
🚫 Two integration points were updated. 🧪 The isPostableContent function now rejects any note whose relative path is in the changes directory, right after the existing index page check. ⛔ The checkBfsEligibility function now returns False for changes paths, preventing them from being considered eligible during BFS traversal.  
  
🧱 A private isChangesPage helper wraps isChangesPath for use with ContentNote values, following the same pattern as isIndexPage wrapping isIndexPath.  
  
## 🧪 Testing  
  
✅ Five new tests were added across two test modules. 🔍 Three tests in the ContentDiscoveryTest module validate that isChangesPath correctly identifies changes directory pages, the changes index, and rejects non-changes files. ⛔ A fourth test confirms that checkBfsEligibility returns False for changes paths. 🚫 A fifth test in SocialPostingTest confirms that isPostableContent rejects changes pages with sufficient body content.  
  
📊 The test suite grew from 185 to 190 tests, all passing.  
  
## 📋 Spec Update  
  
📝 The social posting spec was updated to include the new filter in the content filters list, documenting that notes in the changes directory are excluded from social posting.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* [🌐🔗🧠📖 Thinking in Systems: A Primer](../books/thinking-in-systems.md) by Donella Meadows is relevant because this change demonstrates how small additions to filtering rules can have significant effects on system behavior, preventing an entire category of content from flowing through the social posting pipeline.  
* [💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md) by Don Norman is relevant because the fix addresses a usability concern where auto-generated list pages were being treated as shareable content, violating user expectations about what gets posted.  
  
### ↔️ Contrasting  
* Antifragile by Nassim Nicholas Taleb offers a perspective where exposure to noise and imperfection strengthens systems, contrasting with the filtering approach here that removes noise before it reaches social media audiences.  
  
### 🔗 Related  
* [🧼💾 Clean Code: A Handbook of Agile Software Craftsmanship](../books/clean-code.md) by Robert C. Martin is relevant because the implementation follows existing patterns in the codebase, maintaining consistency with how similar filters like isReflectionPath and isIndexPath are structured.  
* Domain-Driven Design by Eric Evans is relevant because the changes directory represents a distinct domain concept that deserves its own filtering rule rather than being handled through generic mechanisms like frontmatter flags.  
