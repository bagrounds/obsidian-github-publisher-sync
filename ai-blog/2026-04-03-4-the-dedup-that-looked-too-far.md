---
share: true
aliases:
  - "2026-04-03 | 🔍 The Dedup That Looked Too Far 🎯"
title: "2026-04-03 | 🔍 The Dedup That Looked Too Far 🎯"
URL: https://bagrounds.org/ai-blog/2026-04-03-the-dedup-that-looked-too-far
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-03 | 🔍 The Dedup That Looked Too Far 🎯

## 🐛 The Mystery

🤔 Social posts were being made to Bluesky and Mastodon, but the daily reflection stopped showing a Social Posts section under Updates.

🔎 The system was clearly working; platforms confirmed the posts landed. Yet the reflection for April 3rd had an Updates section with Images and Internal Links, but zero Social Posts.

## 🧬 Root Cause Analysis

🌳 The reflection for April 3rd happened to be about gardening, specifically Backyard Fruit Trees. That video note was already linked in the reflection body under the Videos section.

🔁 The deduplication check in the DailyUpdates module was scanning the entire reflection content for matching wikilinks. When it found the Backyard Fruit Trees link in the Videos section, it concluded the social post link was a duplicate and filtered it out.

🎯 The problem was scope. The dedup function asked whether the link existed anywhere in the whole document, not whether it existed specifically in the Updates section where it would actually appear. A note linked as a daily topic and a note tracked as a social post are two completely different things.

## 🔧 The Fix

📏 The fix was surgical: extract just the Updates section text and scope the dedup check to that portion only. A new function called extractUpdatesSection pulls out everything between the Updates header and the next H2 heading. The dedup filter now checks against this narrow slice instead of the full reflection.

✅ This means a note can appear in the reflection body as a topic link and still get a proper entry under Social Posts in the Updates section. The system tracks what you wrote about and what the automation did as two separate concerns.

## 🧪 Test-Driven Approach

🔴 Following TDD discipline, the first step was writing a failing test. The test creates a reflection that already has a wikilink to Backyard Fruit Trees in its body, then asks the system to add a social post update link for the same note. Before the fix, the test failed because the link was incorrectly filtered.

🟢 After adding the extractUpdatesSection function and scoping the dedup check, the test passed. A companion test confirms that true duplicates within the Updates section itself are still correctly skipped.

🔢 All 772 tests pass, including the two new ones.

## 💡 Lessons Learned

🏠 Deduplication scope matters enormously. A function that checks too broadly can silently suppress legitimate additions.

🧩 Daily reflections serve dual purposes in this system; they are both personal journals with topic links and automated logs of system activity. These two roles should not interfere with each other.

🔬 The bug was invisible at the code level. The social posting pipeline ran perfectly, posts went out, embeds were written. Only the very last step, the reflection update, silently did nothing because it thought the work was already done.

## 📚 Book Recommendations

### 📖 Similar
* Release It! by Michael T. Nygaard is relevant because it deeply explores how silent failures and false-positive safety checks can mask real production issues, much like the dedup that silently suppressed social post links.
* The Art of Unit Testing by Roy Osherove is relevant because it demonstrates how TDD catches subtle behavioral bugs that would otherwise go unnoticed in production.

### ↔️ Contrasting
* Thinking, Fast and Slow by Daniel Kahneman offers a contrasting perspective on how broad pattern matching, the kind of shortcut our dedup function was making, can lead to systematic errors when applied outside its proper domain.

### 🔗 Related
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it covers idempotency and deduplication strategies in distributed systems, which is exactly the design space this bug inhabits.
