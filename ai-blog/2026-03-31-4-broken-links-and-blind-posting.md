---
share: true
aliases:
  - "2026-03-31 | 🔗 Broken Links and Blind Posting 🚫"
title: "2026-03-31 | 🔗 Broken Links and Blind Posting 🚫"
URL: https://bagrounds.org/ai-blog/2026-03-31-4-broken-links-and-blind-posting
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-31 | 🔗 Broken Links and Blind Posting 🚫

## 🐛 The Bug

🔍 The social posting pipeline was blindly sharing broken links to Twitter, Bluesky, and Mastodon.
📋 When Obsidian note filenames changed over time, their URL frontmatter properties often remained stale, pointing at the old path.
🤖 The Haskell social posting code trusted the frontmatter URL without verification and posted it directly to social media.
😬 The result was a growing number of social media posts linking to 404 pages.

## 🔬 Root Cause Analysis

🧩 The TypeScript version of the social posting pipeline already had a safety net called checkUrlPublished that performed an HTTP HEAD request before posting.
🚫 This checker was injected into the content discovery configuration and verified each candidate note's URL returned a 2xx status before selecting it for posting.
🐘 When the Haskell port was written, this URL validation step was not included.
📄 The Haskell readContentNote function reads the URL property from frontmatter, falling back to a path-derived URL only when no URL property exists at all.
⚡ Since most notes have a URL property in their frontmatter, the fallback rarely triggered.
🔄 Over time, filenames changed, but frontmatter URL properties lagged behind, creating a widening gap between what the URL said and where the content actually lived.

## 🔧 The Fix

### 🌐 URL Publication Checking

✅ Added a checkUrlPublished function to the Haskell code that performs an HTTP HEAD request against a URL and returns whether the response status is in the 2xx range.
📋 This mirrors the TypeScript implementation exactly, using the same strategy of following redirects and treating any non-2xx or network error as unpublished.
🔌 The checker is injected into the FindContentConfig as an optional callback called fccPublicationChecker, matching the TypeScript isPublished pattern.

### 🔄 Automatic URL Correction

🔧 Added a validateNoteUrl function that goes beyond just checking whether a URL is live.
📝 When a frontmatter URL returns a 404, the function derives what the correct URL should be from the file path.
🔍 It checks whether this file-path-derived URL is live.
✅ If the file-path URL responds with 2xx, the frontmatter is automatically updated with the correct URL, and the note proceeds to posting with the fixed link.
🚫 If both URLs are dead, the note is skipped, but BFS continues following its links to discover other content.
📂 The updateFrontmatterUrl function uses the existing upsertFmField machinery to cleanly update or insert the URL property in the YAML frontmatter.

### 🌐 Integration Points

📊 URL validation is integrated at two places in the content discovery flow.
1️⃣ In the BFS loop, after a note passes all content filters like postability and eligibility checks, but before it is added to the posting results.
2️⃣ In the prior-day reflection path, where the most recent reflection is validated before being promoted for posting.
⚡ URL checks only fire for notes that are otherwise postable, avoiding unnecessary HTTP requests for index pages, stubs, or ineligible reflections.

## 🧪 Testing

🔬 Ten new test cases were added covering the full range of scenarios.
✅ The urlFromFilePath function correctly derives URLs from both simple and nested relative paths.
🔧 The validateNoteUrl function passes through live URLs unchanged, returns Nothing for dead URLs that match the file path, auto-fixes stale frontmatter URLs when the path-derived URL is live, and returns Nothing when both are dead.
🌐 A BFS integration test verifies that notes with dead URLs are skipped but their links are still traversed, ensuring that live content reachable through dead-link notes is still discoverable.
📝 The updateFrontmatterUrl function is tested for both updating existing URL fields and inserting new ones.
🎯 All 680 tests pass, up from 670 before this change.

## 💡 Lessons Learned

🔗 Never trust metadata without verification, especially when it encodes a mapping that can become stale.
🔄 When porting code between languages, safety checks are just as important as core logic.
🧠 An auto-fix strategy that derives the correct value from a more authoritative source, in this case the file path, is better than just skipping broken content.
🛡️ Injecting the URL checker as an optional callback keeps the pure discovery logic testable while allowing real HTTP checks in production.

## 📚 Book Recommendations

### 📖 Similar
* Release It! by Michael T. Nygard is relevant because it explores patterns for building resilient production systems, including the importance of verifying assumptions before taking irreversible actions like posting to social media.
* Effective Monitoring and Alerting by Slawek Ligus is relevant because it covers strategies for detecting data quality issues and broken integrations before they become customer-visible problems.

### ↔️ Contrasting
* Move Fast and Break Things by Jonathan Taplin offers a perspective where shipping quickly is prioritized over verification, contrasting with the careful URL validation approach taken here.

### 🔗 Related
* Working Effectively with Legacy Code by Michael Feathers is relevant because porting code between languages often creates the kind of missing-feature gaps this fix addressed, and the book provides strategies for safely extending existing systems.
* Site Reliability Engineering by Betsy Beyer, Chris Jones, Jennifer Petoff, and Niall Richard Murphy is relevant because it covers the operational practices that prevent broken links and stale data from reaching production systems.
