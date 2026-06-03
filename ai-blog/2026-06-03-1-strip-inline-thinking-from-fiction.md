---
share: true
aliases:
  - "2026-06-03 | 🧠 Strip Inline Thinking from AI Fiction 🤖🐲"
title: "2026-06-03 | 🧠 Strip Inline Thinking from AI Fiction 🤖🐲"
URL: https://bagrounds.org/ai-blog/2026-06-03-1-strip-inline-thinking-from-fiction
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-06-03 | 🧠 Strip Inline Thinking from AI Fiction 🤖🐲

## 🎙️ What This Pull Request Does

🐛 This pull request fixes a recurring bug where Gemma models leaked their entire chain-of-thought reasoning into the published AI Fiction section. 🤖 The previous fix filtered out thought-tagged parts at the Gemini API response level, but Gemma models also stream their planning as plain output text that the API does not tag. 🧹 A new extraction step in the fiction response parser now strips that inline thinking and keeps only the final fiction.

## 🔍 The Root Cause

🧩 Gemma models produce two kinds of thinking output. 📦 The first kind uses the Gemini API thought flag on response parts, which the previous fix already filters with extractNonThoughtText. 📝 The second kind is plain text reasoning that appears as regular output: bullet-pointed theme analysis, multiple draft attempts, self-correction notes like Wait, let us refine, word count checks, and formatting verification. 🎯 The old parseFictionResponse function stripped code fences, quotation marks, and whitespace but had no way to separate this inline thinking from the final fiction.

## 🔧 The Fix

🛠️ A new extractFinalFiction function scans the response text for the last contiguous block of lines that start with an emoji character. 📋 The fiction prompt requires every sentence to begin with an emoji, so genuine fiction lines follow this pattern while thinking lines start with bullets, asterisks, or regular text. ⚖️ The function only activates when the last emoji block contains at least two lines and the response also has non-emoji lines, so clean responses from well-behaved models pass through unchanged. 🔗 The existing parseFictionResponse pipeline now runs extractFinalFiction after quote removal and before the final whitespace strip.

## 🧪 Testing

✅ Six new test cases cover the extraction logic directly through extractFinalFiction. 🔬 Tests verify that clean fiction passes through unchanged, that inline thinking with multiple drafts is stripped to just the final block, that single emoji lines do not trigger false extraction, and that blank lines interspersed within the final fiction block are preserved. 📋 An integration test on parseFictionResponse confirms the full pipeline strips thinking from a realistic Gemma-style response. 🎯 All 2043 tests in the suite continue to pass.

## 🧠 Why Both Layers Matter

🛡️ The API-level extractNonThoughtText filter catches models that use the official thought flag. 🧱 The new text-level extractFinalFiction catches models that dump reasoning as plain text. 🔒 Together they form a defense-in-depth strategy: even if a model outputs its reasoning through an unexpected channel, the fiction parser will extract only the final emoji-formatted story.

## 📚 Book Recommendations

* Thinking, Fast and Slow by Daniel Kahneman
* Godel, Escher, Bach: An Eternal Golden Braid by Douglas Hofstadter
* The Design of Everyday Things by Don Norman
