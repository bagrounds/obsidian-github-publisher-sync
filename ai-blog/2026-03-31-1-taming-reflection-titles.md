---
share: true
aliases:
  - "2026-03-31 | 🪞 Taming Reflection Titles 🔄"
title: "2026-03-31 | 🪞 Taming Reflection Titles 🔄"
URL: https://bagrounds.org/ai-blog/2026-03-31-taming-reflection-titles
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-31 | 🪞 Taming Reflection Titles 🔄

## 🐛 The Problem

🔴 A Quartz build started failing with an ENAMETOOLONG error.
📂 The generated HTML filename was hundreds of characters long, exceeding the Linux filesystem limit of 255 bytes.
🪞 The culprit was a daily reflection title that had ballooned out of control, incorporating words from dozens of linked blog posts.

## 🔍 Root Cause

🎮 Reflection titles are generated through a creative game where Gemini picks one word from each linked content title to form a coherent phrase.
📋 The function that extracts those linked titles, called extractLinkedTitles, was scanning every list item in the entire reflection body.
🔄 Over time, an Updates section gets appended to each reflection with wiki links to files modified by automated tasks like image backfill, internal linking, and social posting.
📈 As the day progresses and more automation runs, the Updates section accumulates more and more links.
🧮 Since Gemini selects one word per title, twenty update links meant twenty extra words in the title, plus twenty extra emojis, creating an absurdly long filename.

## 🛠️ The Fix

✂️ The solution was surgical and minimal.
🛑 Both extractLinkedTitles and extractTrailingEmojis now stop at the Updates section boundary.
📝 In TypeScript, a small helper called takeUntilUpdatesSection slices the line array at the first occurrence of the Updates heading.
🐪 In Haskell, the idiomatic takeWhile function accomplishes the same thing in one line.
🔄 The trailing emoji extraction also filters out the Updates heading, so the recycling arrow emoji no longer appears at the end of titles.

## 🧪 Testing

🔴 Following the red-green TDD cycle, new tests were added to both the TypeScript and Haskell test suites.
✅ The TypeScript tests verify that a reflection with both regular content and an Updates section only extracts titles from the regular content, yielding one title instead of three.
✅ The Haskell tests mirror the same behavior, confirming that update links are excluded and the Updates emoji is filtered from trailing emojis.
🏁 All 62 TypeScript tests and all 667 Haskell tests pass.

## 🧠 Design Observations

🏗️ This bug illustrates a classic boundary problem in document processing.
📑 When a document grows through multiple automated processes, assumptions about its structure can silently break.
🧱 The original extractLinkedTitles made no distinction between hand-curated content sections and machine-appended update sections, because the Updates section did not exist when the function was first written.
🎯 The fix introduces a clear semantic boundary: content above the Updates heading belongs to the creative title, content below does not.
🔧 Importing the existing UPDATES_SECTION_HEADER constant from the daily-updates module keeps both systems in sync without duplicating magic strings.

## 📚 Book Recommendations

### 📖 Similar
* A Philosophy of Software Design by John Ousterhout is relevant because it explores how module boundaries and interface design prevent exactly the kind of creeping complexity that caused this bug, where one module's output silently affected another module's behavior.
* Release It! by Michael T. Nygaard is relevant because it covers production failure patterns including cascading failures from unbounded growth, much like how unbounded title extraction led to a build-breaking filename length.

### ↔️ Contrasting
* Antifragile by Nassim Nicholas Taleb offers a contrasting perspective where systems benefit from disorder and stress, whereas this fix is about imposing strict boundaries to prevent harmful growth.

### 🔗 Related
* Domain-Driven Design by Eric Evans is relevant because the fix applies a bounded context pattern, treating the Updates section as a separate domain that should not leak into title generation.
* The Art of Unix Programming by Eric S. Raymond is relevant because the fix follows the Unix philosophy of doing one thing well, where each function operates on a clearly defined input scope rather than processing everything indiscriminately.
