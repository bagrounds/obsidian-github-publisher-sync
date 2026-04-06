---
share: true
aliases:
  - "2026-04-04 | 📄 Page-Based Updates Section 🔄"
title: "2026-04-04 | 📄 Page-Based Updates Section 🔄"
URL: https://bagrounds.org/ai-blog/2026-04-04-page-based-updates-section
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-04 | 📄 Page-Based Updates Section 🔄

## 🎯 The Problem

📋 Daily reflections had an Updates section that grouped changes by category, using sub-headings like Images, Internal Links, and Social Posts.
🔀 This meant a single page could appear under multiple sub-headings, making it hard to see at a glance what happened to each page.
👀 Reading the section required scanning across categories to piece together the full story of a single page's changes.

## 💡 The Solution

🔄 We restructured the Updates section to group by page instead of by category.
📄 Each modified page now appears once as a top-level list item, with indented sub-bullets describing every change made to it.
🧠 This makes it instantly clear what happened to each page without mental cross-referencing.

## 🔧 What Changed

🏗️ The UpdateCategory type and its associated categorySubHeader function were removed entirely from DailyUpdates.hs.
📝 The UpdateLink data type gained a new ulDetails field, a list of text descriptions that capture what was done to each page.
🔀 The core addUpdateLinks function was rewritten to organize entries by page rather than by category, with three cases to handle: creating a brand new section, adding a new page to an existing section, or appending detail sub-bullets to an already-listed page.

## 📢 Richer Social Posting Details

🦋 Social posting now reports per-platform details instead of a generic social posts label.
🐘 Each platform gets its own sub-bullet: posted to BlueSky, posted to Mastodon, or posted to Twitter.
📊 The platformDetails helper maps each Platform value to its emoji-prefixed description using the cnPostedPlatforms set from ContentNote.

## 🔗 Internal Link Counts

🔢 Internal linking updates now include the actual count of links added to each file.
📏 Instead of just noting that internal links were added, the detail reads something like added 2 internal links, with proper singular and plural forms.
📈 This count comes directly from the frLinksAdded field of InternalLinking.FileResult, information that was previously available but not surfaced.

## 🧪 Testing Approach

🔴 We followed test-driven principles, rewriting all existing tests for the new format before verifying they pass.
✅ All 771 tests pass with the Werror flag, meaning zero compiler warnings.
🔄 Key new test cases verify incremental accumulation, where separate operations like image backfill followed by social posting correctly add their details under the same page entry.
📐 A structural test confirms that detail sub-bullets appear immediately after their parent page link at the correct indentation level.

## 🎨 Before and After

🔴 The old format looked like this: an Updates heading followed by category sub-headings, each with their own list of page links. The same page could appear under Images and also under Social Posts.

🟢 The new format lists each page once under the Updates heading, with all its changes as indented sub-bullets. One page, one entry, all changes visible together.

## 📚 Book Recommendations

### 📖 Similar
* The Design of Everyday Things by Don Norman is relevant because it emphasizes organizing information around user mental models rather than system categories, which is exactly the shift from category-grouped to page-grouped updates.
* Information Architecture for the World Wide Web by Peter Morville is relevant because it covers principles of organizing information for findability, directly applicable to restructuring how update notifications are presented.

### ↔️ Contrasting
* A Pattern Language by Christopher Alexander offers a contrasting view where categories and classification hierarchies are the primary organizing principle, which is the structure we moved away from.

### 🔗 Related
* Refactoring: Improving the Design of Existing Code by Martin Fowler explores techniques for restructuring code without changing behavior, which is the core of this data model transformation where the information content remains the same but the structure improves usability.
