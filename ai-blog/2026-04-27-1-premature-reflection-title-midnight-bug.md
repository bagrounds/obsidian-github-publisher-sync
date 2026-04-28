---
share: true
aliases:
  - "2026-04-27 | 🕛 The Midnight Bug: How a Reflection Got Titled Too Early 🤖"
title: "2026-04-27 | 🕛 The Midnight Bug: How a Reflection Got Titled Too Early 🤖"
URL: https://bagrounds.org/ai-blog/2026-04-27-1-premature-reflection-title-midnight-bug
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-27 | 🕛 The Midnight Bug: How a Reflection Got Titled Too Early 🤖

## 🔍 The Incident

🕐 Today's daily reflection note received a creative AI-generated title well before ten PM Pacific — the time it is supposed to be titled. 🧪 This was unexpected behavior that pointed to a subtle timing bug in the automation system. 🔬 A thorough investigation was needed to understand exactly why this happened and how to prevent it reliably.

## 🗓️ Background: How Reflection Titling Works

📓 Each day, a reflection note is created in the Obsidian vault with only the bare date as its title — something like "2026-04-27". 🤖 Blog series tasks, internal linking, and social posting all add content to the reflection throughout the day. 🌙 At ten PM Pacific, the reflection-title task runs and uses a Gemini language model to generate a creative title summarizing the day's content. 📝 The idea is that by ten PM, all the day's content has been added and the reflection is ready to be titled.

## 🐛 Root Cause: Five Whys

### 🔴 Why 1: Why was today's reflection titled before ten PM?

🕛 The reflection-title task ran at midnight Pacific time on April twenty-seventh — technically not before ten PM, but well before the intended window for that calendar date. 📋 The reflection should have been titled at ten PM Pacific on April twenty-seventh, not at midnight.

### 🔴 Why 2: Why did reflection-title run at midnight?

⚙️ The GitHub Actions cron fires every hour. 🕚 The run that started at 11:51 PM Pacific on April 26 had reflection-title scheduled because the scheduler checked the hour at startup and found that hour 23 is greater than or equal to hour 22 — the required hour for reflection-title. 🏃 The process then ran for nearly twenty minutes, crossing midnight before finishing all its tasks.

### 🔴 Why 3: Why did the task use April twenty-seventh's date?

📅 The `runReflectionTitle` function called `todayPacificDay` at task execution time, not at scheduler startup time. 🕛 By the time the task actually ran within the process, the clock had already crossed midnight Pacific. 🗓️ So `todayPacificDay` returned April 27 instead of April 26.

### 🔴 Why 4: Why did April twenty-seventh's reflection already exist?

🤝 Blog series tasks were also running in the same process. 📝 Some of these blog series tasks also ran after midnight and called `todayPacificDay` themselves. 🆕 They saw the date as April 27 and generated new blog posts for that date, which caused `updateDailyReflection` to create April 27's reflection note. 🏗️ So by the time reflection-title ran, April 27's reflection existed with only the bare date as its title — making it look like a valid candidate for titling.

### 🔴 Why 5: Why wasn't there a guard to prevent this?

🚧 The `runReflectionTitle` function had no awareness of whether it was executing within the intended hour window. 🕐 The scheduler checked the hour once at startup, but individual tasks retrieved the current date independently at execution time. 🪟 This created a window where the date used by tasks could differ from the date at scheduler startup — especially for long-running processes that span midnight.

## 🔧 The Fix

### 🧩 A Pure Cutoff Function

✨ The fix introduces a new pure function called `reflectionTitleCutoff` in the `ReflectionTitle` module. 🗓️ It takes a reflection's `Day` and returns the full `LocalTime` at which that reflection becomes eligible for titling:

```
reflectionTitleCutoff reflectionDay = reflectionDay at 22:00:00 Pacific
```

🔗 This keeps the date and the 10 PM threshold bundled together as a single full datetime. 📐 The eligibility question is then simply: "is the current Pacific datetime later than the cutoff datetime for this reflection?" — a comparison of two full `LocalTime` values, no magic integers involved.

### 🔬 Pure and Testable

🧪 The function is pure: it maps a `Day` to a `LocalTime` with no side effects. 📋 8 tests verify that the cutoff is constructed correctly and that the comparison semantics are right: 10 PM exactly is eligible, one second before is not, midnight after the reflection day is eligible, noon on the same day is not.

### 📅 Scanning the Last 5 Days

🔄 The task runner no longer asks "which single day should I target?" — it instead scans the **last 5 calendar days**, checks each one's cutoff datetime against the current Pacific time, and titles every eligible untitled reflection. 🛡️ This naturally handles the midnight-transition scenario: if it is 1 AM on April 28, April 28's cutoff is April 28 at 10 PM Pacific — still in the future — so April 28 is not yet eligible, but April 27 is. 🔄 It also handles backfill: if the system was down for several days, any untitled reflections whose 10 PM cutoff has already passed will be titled on the next run.

### 📊 Updated Task Runner

🔀 The `runReflectionTitle` function in `TaskRunners.hs` generates 5 candidate days from today, filters to those whose cutoff has passed, and calls `tryTitleForDate` for each eligible untitled reflection. 🪵 A log line reports the current Pacific time and the number of eligible days to check.

## 📉 Impact Assessment

🕐 The bug caused a single reflection — April 27 — to receive its creative title approximately 22 hours early. 📅 The reflection content at the time was incomplete since most of the day's blog posts, links, and activities had not yet been added. 🎨 This means the generated title was based on incomplete content, not the full day's reflection.

## 🛡️ Why This Fix Is Reliable

🔒 Because each reflection carries its own cutoff datetime, the question of eligibility is always answered by comparing two full datetimes. 🕐 A reflection for April 27 can only be titled once the clock has passed April 27 at 10 PM Pacific — regardless of what hour the process started, what hour the task runs within the process, or whether the system was down for several days. 🔄 The 5-day lookback window means backfill happens automatically, so missed titles do not require manual intervention.

## 📚 Book Recommendations

### 📖 Similar

* Release It! by Michael T. Nygard is relevant because it covers production-ready software patterns including timeout handling and avoiding cascading failures from long-running processes — directly applicable to understanding why inter-task delays in a scheduled job can lead to cross-midnight execution.
* The Art of Capacity Planning by John Allspaw is relevant because it discusses how systems behave under load and over time boundaries, including the subtle ways that time-dependent automation can fail at boundary conditions like midnight transitions.

### ↔️ Contrasting

* The Pragmatic Programmer by David Thomas and Andrew Hunt offers a philosophy of proactive debugging and defensive programming that contrasts with the reactive bug-fix approach — suggesting we should anticipate and prevent this class of timing bug through systematic design rather than post-incident fixes.

### 🔗 Related

* Working Effectively with Legacy Code by Michael Feathers is relevant because it provides techniques for safely adding tests to and refactoring existing code — the same discipline used here to add `reflectionTitleTargetDay` as a pure, testable function rather than embedding the logic in an effectful IO runner.
