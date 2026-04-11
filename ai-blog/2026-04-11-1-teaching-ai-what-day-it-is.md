---
share: true
aliases:
  - "2026-04-11 | 📅 Teaching AI What Day It Is 🤖"
title: "2026-04-11 | 📅 Teaching AI What Day It Is 🤖"
URL: https://bagrounds.org/ai-blog/2026-04-11-1-teaching-ai-what-day-it-is
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-11 | 📅 Teaching AI What Day It Is 🤖

## 🐔 The Saturday That Thought It Was Sunday

🐣 Chickie Loo, our beloved automated chicken blog, woke up on a Saturday and told the world it was Sunday. 🤔 The root cause was simple: the prompt sent to Gemini included only a YYYY-MM-DD date string, leaving the AI to infer the day of the week on its own. 🎲 Large language models are surprisingly unreliable at calendar math, so occasionally they guess wrong.

## 🛠️ The Fix: Deterministic Date Awareness

📅 The solution is delightfully straightforward. 🧮 Instead of trusting an AI to compute "2026-04-11 is a Saturday," we now tell it explicitly. 🔤 Every blog generation prompt now begins with a line like "Today is Saturday, April 11, 2026." followed by the machine-readable YYYY-MM-DD format on the next line.

🧊 This is implemented as a pure function called formatDayHuman that accepts a Day value and returns the full human-readable string. 🏗️ Because it is a pure function with no side effects, it is trivially testable and deterministically correct.

## 🏠 Consolidating Shared Logic into PacificTime

🔍 While investigating the date issue, we discovered that Pacific timezone logic was duplicated between two modules. 🗓️ Both BlogPrompt and Scheduler independently defined identical functions for DST detection, timezone construction, and Sunday-of-month calculation. 🧹 This duplication meant any timezone fix would need to be applied in two places, which is exactly the kind of maintenance burden that leads to bugs.

📦 We created a new shared module called Automation.PacificTime that consolidates all Pacific timezone functionality into one authoritative source. 🕐 This module now owns formatDay for YYYY-MM-DD output, formatDayHuman for the new human-readable format, todayPacificDay for getting the current Pacific date, and pacificHour for converting UTC timestamps to Pacific hour values. 🧩 Five other modules that previously imported timezone functions from BlogPrompt or defined their own now import from PacificTime directly.

## 🆕 Making It Easy to Add New Blog Series

📋 One of the goals of this change was to ensure that the common elements of automated blog generation live in well-organized shared modules. 🧪 The litmus test: how many files do you need to touch to add a brand new fully automated blog series?

📝 The answer is four files plus a content directory. 🗂️ You add a configuration record in BlogSeriesConfig, a task ID and schedule entry in Scheduler, a dispatch case in RunScheduled, and create a content directory in the vault. 🧠 Everything else, including prompt construction with date awareness, recap detection, frontmatter assembly, navigation linking, title sanitization, and image generation, is inherited automatically from the shared modules.

🚫 You do not need to modify BlogPrompt, BlogSeries, PacificTime, BlogPosts, or BlogImage. 🎯 This is a good sign for modularity: adding a new feature mostly means adding new code rather than modifying existing code.

## 🧪 Testing the Changes

📊 We added 15 new tests bringing the total from 1274 to 1289. 📅 The PacificTimeTest module covers formatDay formatting, formatDayHuman output for multiple days of the week, and pacificHour conversions across both PST and PDT. 🧠 Two new BlogPromptTest cases verify that buildBlogPrompt produces a user prompt containing both the human-readable date and the YYYY-MM-DD format.

✅ All 1289 tests pass. 🧹 Zero hlint hints. 🏗️ Clean build with no warnings.

## 📚 Book Recommendations

### 📖 Similar
* A Philosophy of Software Design by John Ousterhout is relevant because it explores how to reduce complexity by creating deep modules with simple interfaces, exactly the kind of refactoring we did by consolidating timezone logic into a single PacificTime module.
* The Pragmatic Programmer by David Thomas and Andrew Hunt is relevant because its emphasis on DRY (Don't Repeat Yourself) directly mirrors the motivation for eliminating duplicate timezone code across modules.

### ↔️ Contrasting
* Thinking, Fast and Slow by Daniel Kahneman is relevant because it explores how even human intuition fails at systematic reasoning tasks like calendar math, paralleling our discovery that AI models also struggle with day-of-week inference.

### 🔗 Related
* Domain-Driven Design by Eric Evans is relevant because the refactoring followed DDD principles by identifying PacificTime as a distinct domain concept deserving its own module rather than being scattered across unrelated modules.
* Clean Architecture by Robert C. Martin is relevant because the separation of pure domain logic from IO effects in the PacificTime module exemplifies the dependency inversion and clean boundary principles the book advocates.
