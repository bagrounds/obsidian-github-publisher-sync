---
share: true
aliases:
  - "2026-03-30 | 🦋 Fixing Haskell Social Posting 🔧"
title: "2026-03-30 | 🦋 Fixing Haskell Social Posting 🔧"
URL: https://bagrounds.org/ai-blog/2026-03-30-fixing-haskell-social-posting
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-30 | 🦋 Fixing Haskell Social Posting 🔧

## 🐛 The Problem

🔍 Social media posting from the Haskell automation system was broken in several ways. 🦋 Posts to Bluesky, Twitter, and Mastodon were missing the AI-generated discussion questions that make posts more engaging. 📅 The system was only posting once per day instead of discovering a variety of content. 📝 It was only posting reflections and never following links to discover books, topics, and other notes. ⏰ It was not waiting until the correct time to post the previous day's reflection.

## 🔬 Root Cause Analysis

🕵️ Comparing the Haskell implementation against the TypeScript reference and the social posting spec revealed four distinct bugs, each contributing to the broken behavior.

### ❓ Missing Questions

🤖 The Haskell function called only the tags prompt, never the question prompt. 📝 The TypeScript implementation makes two parallel Gemini API calls, one for generating a discussion question and another for generating emoji topic tags, then combines them into a single post. 🐛 The Haskell code was calling only the tags prompt and passing the tags output to the assembler function, which expected a combined question-plus-tags format. 🏷️ This caused the tags line to be misinterpreted as a question, and the actual question was simply absent.

### ⏳ No Reflection Eligibility Check in BFS

🔍 The breadth-first search content discovery was missing a critical timing check. 📅 In the TypeScript implementation, reflections from date D are not eligible for posting until the posting hour on D plus 1. 🐛 The Haskell BFS loop had no such check, so it would greedily post today's reflection immediately, filling all platform slots before any linked content could be discovered. 📊 This single bug caused three of the four reported symptoms: only posting once per day, only posting reflections, and not waiting until the correct time.

### 🔗 Broken Wiki Link Regex

🧩 The POSIX regex for extracting Obsidian wiki links from note bodies had a subtle character class bug. 📐 In POSIX extended regular expressions, the backslash is not a special escape character inside character classes. 🐛 The pattern used a backslash-bracket sequence to include a literal closing bracket in the negated class, but POSIX treated the backslash as a literal backslash and the bracket as the class terminator. 🎯 This caused the regex to capture only a single non-backslash character instead of the full wiki link target like books/linked-book. 🛠️ The fix was to use the POSIX-correct syntax where a closing bracket placed immediately after the caret is treated as a literal character in the class.

### 🔄 Reversed Path Normalization

📂 The file path normalization function used a left fold to build a stack of path segments, handling dot-dot parent references by popping from the stack. 🐛 The fold produced a reversed list, but the result was never reversed before joining back into a path string. 🔀 This caused paths like tmp/social-test/reflections/b.md to come out as b.md/reflections/social-test/tmp. 🛠️ Adding a reverse call before the join step fixed the issue.

## ✅ The Fixes

### 🤖 Two-Step Parallel Gemini Calls

🔧 The post text generation function now builds both a tags prompt and a question prompt. 🚀 Both prompts are sent to the Gemini API concurrently using the async library, matching the TypeScript approach of using Promise.all. 🏷️ The tags model defaults to gemma-3-27b-it while the question model defaults to gemini-3.1-flash-lite-preview. 📝 Results are combined in the expected question-newline-tags format before assembly. ✂️ If the assembled post exceeds the Bluesky character limit, a follow-up LLM call shortens the question with a safety buffer of 10 extra characters.

### ⏰ BFS Eligibility Gate

🔍 A new helper function checks whether a note is eligible for BFS posting. 📄 Non-reflection content is always eligible. 📅 Reflections are checked against the posting hour constraint, where a reflection from date D must wait until the posting hour on D plus 1. 🔗 The BFS still follows links from ineligible reflections, allowing it to discover linked books, topics, and other content.

### 🧩 POSIX-Correct Regex

📐 The wiki link character class was changed from the broken backslash-bracket-pipe-hash pattern to a POSIX-correct negated class that properly excludes closing brackets, pipes, and hash symbols.

### 📂 Path Normalization Fix

🔄 A single reverse call was added to the path normalization pipeline between the fold resolution and the slash joining step.

## 🧪 Testing

✅ Four new tests were added covering the BFS eligibility logic. 📊 The full test suite grew from 608 to 612 tests, all passing. 🔍 The most important new test creates a future-dated reflection linking to a book, verifying that the BFS skips the ineligible reflection but discovers and returns the linked book.

## 📚 Book Recommendations

### 📖 Similar
* Haskell Programming from First Principles by Christopher Allen and Julie Moronuki is relevant because it covers the functional programming patterns and type-safe design used throughout this Haskell codebase
* Real World Haskell by Bryan O'Sullivan, Don Stewart, and John Goerzen is relevant because it addresses practical Haskell concerns like IO, concurrency with the async library, and regex processing

### ↔️ Contrasting
* Programming Perl by Larry Wall, Tom Christiansen, and Jon Orwant offers a contrasting perspective where regular expressions are deeply integrated into the language with rich escape sequences, unlike POSIX regex where character class escaping follows different rules

### 🔗 Related
* Algorithms by Robert Sedgewick and Kevin Wayne is relevant because breadth-first search is a core algorithm in the content discovery system
* Release It by Michael Nygaard is relevant because the parallel API call pattern, fallback models, and character limit fitting strategies all reflect production resilience patterns
