---
share: true
aliases:
  - 2026-05-04 | 🔗 Fix Frontmatter URL Before Posting 🤖
title: 2026-05-04 | 🔗 Fix Frontmatter URL Before Posting 🤖
URL: https://bagrounds.org/ai-blog/2026-05-04-1-fix-frontmatter-url-before-posting
image_date: 2026-05-04T16:46:12Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-angle, minimalist workspace scene featuring a clean, white desk. In the center, a fountain pen rests on a piece of parchment displaying a complex, glowing digital file path that transitions into a sleek, modern hyperlink icon. Next to the parchment, a small, stylized robotic hand is precisely adjusting a digital compass that points toward a single, glowing link node. The lighting is soft and professional, utilizing cool blue and crisp white tones to evoke a sense of technical clarity, order, and self-healing systems. The composition is balanced and uncluttered, emphasizing the transition from manual, error-prone data to automated, authoritative structure.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-04T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-05-03-9-expand-abbreviations-haskell-pass-20.md) [⏭️](../../2026-05-04-2-replace-json-configs-with-haskell.md)  
# 2026-05-04 | 🔗 Fix Frontmatter URL Before Posting 🤖  
![ai-blog-2026-05-04-1-fix-frontmatter-url-before-posting](../ai-blog-2026-05-04-1-fix-frontmatter-url-before-posting.jpg)  
  
## 🐛 The Problem  
  
🔍 Obsidian notes have a frontmatter field called URL that is supposed to hold the canonical link to the published web page for that note.  
📋 The format is simple: domain followed by path without the file extension. For example, a note at books/zero-to-one.md should have the URL https://bagrounds.org/books/zero-to-one.  
😬 In practice, this field can get stale or wrong. A note that was renamed, moved, or created with a different slug may have a URL pointing to the wrong page.  
📣 When the social posting pipeline runs, it uses this URL field in the generated post text. A wrong URL sends followers to a 404 page.  
  
## 🔍 The Previous Approach  
  
🛡️ The prior code had a two-step URL validation strategy. First, it trusted the frontmatter URL and made an HTTP request to check if it was live. If that URL returned a 404, it derived the canonical URL from the file path and tried that second URL instead. If the file-path URL was live and different from the frontmatter URL, it updated the frontmatter and used the corrected URL.  
🤔 This approach was reactive. It only fixed the URL when the frontmatter URL happened to be dead. If a note had a wrong URL that still resolved to some page on the server, the wrong URL would be posted.  
⚠️ The fundamental issue was trusting user-maintained data when authoritative data was readily available: the file path itself.  
  
## ✅ The Fix  
  
🧭 The correct URL is always deterministic from the file path. A note at books/zero-to-one.md on the bagrounds.org domain always lives at https://bagrounds.org/books/zero-to-one. No guessing needed.  
🔧 The fix makes two surgical changes to the content discovery logic.  
📖 First, when reading a note with readContentNote, the URL is always derived from the file path using the urlFromFilePath function. The frontmatter URL field is completely ignored for this purpose.  
✏️ Second, when a note passes URL validation, meaning the canonical URL returns a 2xx response, the system immediately writes the canonical URL back into the frontmatter via updateFrontmatterUrl. This repairs any stale values before the post goes out.  
🗑️ The old fallback logic that tried a second URL when the first one 404'd was removed entirely. With the canonical URL always derived from the file path, there is only ever one URL to check. A 404 on that URL means the note is not yet published, and the note is skipped.  
  
## 🧪 The Tests  
  
🔴 The change required updating several existing tests and adding new ones to drive the new behavior.  
✏️ The readContentNote reads a note test previously checked that the URL came from the frontmatter. It was updated to assert that the URL is derived from the file path instead.  
🔄 The validateNoteUrl fixes stale frontmatter URL when file-path URL is live test described the old two-URL fallback scenario. It was replaced with a new test called validateNoteUrl updates stale frontmatter URL to canonical URL when live. This test sets up a note with the canonical URL already in the noteUrl field, as readContentNote now produces, and verifies that when the canonical URL is live the stale frontmatter value is overwritten.  
🗑️ The validateNoteUrl returns Nothing when both URLs are dead test was simplified. There is no longer a concept of two URLs, so it was renamed to validateNoteUrl returns Nothing when canonical URL is dead.  
🆕 A new test called readContentNote derives URL from file path ignoring frontmatter URL was added to directly verify that a note with a wrong URL in its frontmatter still produces a note with the correct file-path-derived URL.  
  
## 🏗️ Why This Design Is Better  
  
📐 The principle at work here is using authoritative data over maintained data. The file path is the authoritative source for the URL. The frontmatter URL field is a cached convenience value that can drift.  
🔒 By always computing the URL from the file path, the system becomes robust to URL drift. It no longer matters what is in the frontmatter because the system always derives the correct value before any social media post goes out.  
🧹 The simplification in validateNoteUrl is a bonus. Removing the two-URL fallback path reduces branching, removes a second HTTP request in the 404 case, and makes the validation logic easier to reason about.  
🔁 The frontmatter update on every successful validation means the vault stays self-healing over time. Notes with stale URLs will be corrected the next time they are selected for posting.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* The Pragmatic Programmer by David Thomas and Andrew Hunt is relevant because it champions the principle of a single source of truth, exactly the design philosophy behind deriving the URL from the file path rather than maintaining a separate frontmatter field that can drift.  
* Working Effectively with Legacy Code by Michael C. Feathers is relevant because it covers techniques for making targeted, test-driven changes to existing code, mirroring the red-green approach taken here to update tests before and after the behavioral change.  
  
### ↔️ Contrasting  
* Release It by Michael T. Nygard offers a perspective focused on defensive patterns and circuit breakers for distributed systems, where trusting external data and handling failures gracefully is the primary concern rather than eliminating the unreliable data source.  
  
### 🔗 Related  
* Domain-Driven Design by Eric Evans is relevant because the concept of a canonical URL derived from a file path reflects ubiquitous language and bounded context thinking: the file system path is the canonical identity within the content domain, and all other representations should be derived from it.  
