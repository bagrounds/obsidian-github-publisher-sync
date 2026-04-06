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

🕵️ Comparing the Haskell implementation against the TypeScript reference and the social posting spec revealed several distinct bugs, each contributing to the broken behavior.

### ❓ Missing Questions

🤖 The Haskell function called only the tags prompt, never the question prompt. 📝 The TypeScript implementation makes two sequential Gemini API calls, one for generating a discussion question and another for generating emoji topic tags, then combines them into a single post. 🐛 The Haskell code was calling only the tags prompt and passing the tags output to the assembler function, which expected a combined question-plus-tags format. 🏷️ This caused the tags line to be misinterpreted as a question, and the actual question was simply absent.

### ⏳ No Reflection Eligibility Check in BFS

🔍 The breadth-first search content discovery was missing a critical timing check. 📅 In the TypeScript implementation, reflections from date D are not eligible for posting until the posting hour on D plus 1. 🐛 The Haskell BFS loop had no such check, so it would greedily post today's reflection immediately, filling all platform slots before any linked content could be discovered. 📊 This single bug caused three of the four reported symptoms: only posting once per day, only posting reflections, and not waiting until the correct time. 🔗 Crucially, BFS must always follow links from every node it visits, even non-postable ones like index pages, short stubs, or notes marked no_social, so it can reach postable content beyond them.

### 🧩 Wiki Link Extraction

🔍 The original Obsidian wiki link extraction used a regular expression, but wiki link syntax with its nested brackets sits above the regular language level on Chomsky's hierarchy. 🛠️ The fix replaced the regex with a proper recursive descent parser that handles the three wiki link variants: plain links, links with section anchors, and links with display text.

### 🔄 Reversed Path Normalization

📂 The file path normalization function used a left fold to build a stack of path segments, handling dot-dot parent references by popping from the stack. 🐛 The fold produced a reversed list, but the result was never reversed before joining back into a path string. 🔀 This caused paths to come out in reverse order. 🛠️ Adding a reverse call before the join step fixed the issue.

## ✅ The Fixes

### 🤖 Two-Step Sequential Gemini Calls

🔧 The post text generation function now builds both a tags prompt and a question prompt. 📡 Both prompts are sent to the Gemini API sequentially to avoid rate limits. 🏷️ The tags model defaults to gemma-3-27b-it while the question model defaults to gemini-3.1-flash-lite-preview. 📝 Results are combined in the expected question-newline-tags format before assembly. ✂️ If the assembled post exceeds the Bluesky character limit, a follow-up LLM call shortens the question with a safety buffer of 10 extra characters.

### ⏰ BFS Eligibility Gate

🔍 A new helper function checks whether a note is eligible for BFS posting. 📄 Non-reflection, non-index content is always eligible. 📅 Reflections are checked against the posting hour constraint, where a reflection from date D must wait until the posting hour on D plus 1. 🚫 Index pages are never eligible for posting. 🔗 The BFS still follows links from ineligible content, allowing it to discover linked books, topics, and other content even through non-postable nodes.

### 🧩 Recursive Descent Wiki Link Parser

📐 The wiki link regex was replaced with a proper recursive descent parser. 🔍 The parser handles all three Obsidian wiki link formats: plain links, links with section anchors using hash, and links with display text using pipe. 🧪 Eleven tests cover the parser, including a QuickCheck property that ensures it never crashes on arbitrary input.

### 📂 Path Normalization Fix

🔄 A single reverse call was added to the path normalization pipeline between the fold resolution and the slash joining step. 🧪 Five tests verify correct normalization including parent directory resolution, current directory removal, and complex nested paths.

## 🧪 Testing

✅ Twenty-four new tests were added covering the wiki link parser, path normalization, index page eligibility, and BFS traversal through non-postable content. 📊 The full test suite grew from 608 to 636 tests, all passing. 🔍 Three BFS traversal tests verify that the search correctly passes through index pages, no_social flagged content, and short-body stubs to discover postable content linked beyond them.

## 📚 Book Recommendations

### 📖 Similar
* Haskell Programming from First Principles by Christopher Allen and Julie Moronuki is relevant because it covers the functional programming patterns and type-safe design used throughout this Haskell codebase
* Introduction to Automata Theory, Languages, and Computation by John Hopcroft, Rajeev Motwani, and Jeffrey Ullman is relevant because it defines Chomsky's hierarchy and explains why nested bracket grammars require more than regular expressions

### ↔️ Contrasting
* Programming Perl by Larry Wall, Tom Christiansen, and Jon Orwant offers a contrasting perspective where regular expressions are deeply integrated into the language with rich escape sequences and backtracking, making regex a natural first choice for text parsing

### 🔗 Related
* Algorithms by Robert Sedgewick and Kevin Wayne is relevant because breadth-first search is the core algorithm in the content discovery system
* Test Driven Development by Kent Beck is relevant because this PR highlights the importance of writing failing tests before fixes, a practice now codified in the project's engineering guidelines
