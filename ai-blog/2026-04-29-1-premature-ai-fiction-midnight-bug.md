---
share: true
aliases:
  - "2026-04-29 | 🕛 The Sequel Bug: AI Fiction Generated Too Early 🤖🐲"
title: "2026-04-29 | 🕛 The Sequel Bug: AI Fiction Generated Too Early 🤖🐲"
URL: https://bagrounds.org/ai-blog/2026-04-29-1-premature-ai-fiction-midnight-bug
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-29 | 🕛 The Sequel Bug: AI Fiction Generated Too Early 🤖🐲

## 🔍 The Incident

🐲 AI fiction passages were being generated too early in the day — sometimes around midnight Pacific — well before the intended 10 PM window. 🕛 This is the same class of bug that caused premature reflection titling, fixed just days ago. 🔬 A careful root cause analysis revealed the connection.

## 🗓️ Background: How AI Fiction Works

📓 Each day, a reflection note accumulates content throughout the day: blog posts, book links, videos, and notes. 🤖 At 10 PM Pacific, the ai-fiction task runs and calls a Gemini language model to generate a short, emoji-rich fiction passage inspired by the day's themes. 🕐 The 10 PM timing is intentional — it waits until most of the day's content is present so the fiction draws from a rich, complete picture of the day.

## 🐛 Root Cause: Five Whys

### 🔴 Why 1: Why was AI fiction generated before 10 PM?

🕛 The ai-fiction task ran at a time when the Pacific day had already rolled over to a new calendar day — specifically around midnight — and the new day had not yet reached its 10 PM eligibility window. 🐲 Fiction was being generated for that new day at approximately midnight, roughly 22 hours too early.

### 🔴 Why 2: Why did ai-fiction run at midnight?

⚙️ The GitHub Actions cron fires every hour. 🕚 A run that started at 11:51 PM Pacific on day D found the ai-fiction task scheduled because the scheduler checked the hour at startup: hour 23 is greater than or equal to 22, the required hour. 🏃 The process then took several minutes to complete vault sync and earlier tasks, crossing midnight before ai-fiction actually executed.

### 🔴 Why 3: Why did the task generate fiction for the new day instead of the old one?

📅 The original `runAiFiction` function called `todayPacificDay` at task execution time, not at scheduler startup time. 🕛 By the time the task actually ran within the process, the clock had already crossed midnight Pacific. 🗓️ So `todayPacificDay` returned day D+1 instead of day D.

### 🔴 Why 4: Why did day D+1's reflection already exist at midnight?

🤝 Blog series tasks run in the same process, earlier in the task list. 📝 Some of those tasks also ran after midnight and called `todayPacificDay` themselves, saw day D+1, and generated blog posts for that date. 🏗️ Those blog posts triggered `updateDailyReflection`, which created day D+1's reflection note — making it look like a valid target for fiction generation.

### 🔴 Why 5: Why wasn't there a guard to prevent this?

🚧 The `runAiFiction` function had no awareness of whether the current time had reached the 10 PM eligibility window for the target day. 🕐 The scheduler checked the hour once at startup, but `runAiFiction` retrieved the current date independently at execution time. 🪟 This mismatch created a window where the date seen by `runAiFiction` could be a full day ahead of the intended date, with no per-day eligibility check to catch it.

## 🔗 Connection to the Reflection Title Fix

🔁 This bug is structurally identical to the reflection-title midnight bug fixed on April 27. 🧩 That fix introduced a pure `reflectionTitleCutoff :: Day -> LocalTime` function and used it to filter candidate days before titling. 🐲 The ai-fiction task had the same vulnerability but was missed when the reflection title fix landed — likely because it was a separate code path with a simpler single-day check rather than the multi-day backfill loop that reflection-title uses.

## 🔧 The Fix

### 🧩 A Pure Cutoff Function

✨ The fix introduces a new pure function `fictionEligibilityCutoff` in the `AiFiction` module. 🗓️ It takes a `Day` and returns the full `LocalTime` at which that day's reflection becomes eligible for fiction generation:

```haskell
fictionEligibilityCutoff day = LocalTime day (TimeOfDay 22 0 0)
```

🗓️ In plain language: given any calendar day, the cutoff is that same day at exactly ten PM Pacific time.

🔗 This is exactly the same shape as `reflectionTitleCutoff` — both tasks share the same 10 PM Pacific eligibility window. 🏠 Each module owns its own cutoff function, consistent with the library-developer module design principle.

### 📅 Eligibility Check in runAiFiction

🔀 The `runAiFiction` function no longer calls `todayPacificDay` and proceeds unconditionally. 🕐 Instead, it gets the current UTC time, converts it to Pacific local time, extracts today's date from that, and then immediately checks whether the current Pacific time has reached `fictionEligibilityCutoff today`. 🛡️ If not, it logs a message and skips — no fiction is generated. If yes, it proceeds with the existing idempotency check and generation logic.

### 🔬 Pure and Testable

🧪 The `fictionEligibilityCutoff` function is pure: it maps a `Day` to a `LocalTime` with no side effects. 📋 Eight tests verify that the cutoff is constructed correctly and that the comparison semantics are right: 10 PM exactly is eligible, one second before is not, midnight on the following day is eligible, noon on the same day is not.

## 📉 Impact Assessment

🕐 The bug could cause a reflection to receive its AI fiction passage approximately 22 hours early — at midnight rather than 10 PM. 📅 The reflection content at midnight is typically thin: it may contain only a few blog post links added in the final minutes of the previous day's run. 🎨 This means the fiction passage would be inspired by sparse, unrepresentative content rather than the full day's reading and writing.

## 🛡️ Why This Fix Is Reliable

🔒 Because each reflection carries its own cutoff datetime, the question of fiction eligibility is always answered by comparing two full datetimes. 🕐 A reflection for day D can only receive fiction once the clock has passed day D at 10 PM Pacific — regardless of what hour the process started, what hour the task runs within the process, or how long earlier tasks took to complete. 🔄 The fix mirrors the approach proven effective for the reflection-title task.

## 📚 Book Recommendations

### 📖 Similar

* Release It! by Michael T. Nygard is relevant because it covers production-ready software patterns including timeout handling and the subtle ways long-running processes can violate assumptions about time and state boundaries, exactly the class of bug encountered here.
* The Art of Capacity Planning by John Allspaw is relevant because it examines how systems behave over time and at boundary conditions, including the edge cases like midnight transitions that can silently violate time-dependent automation assumptions.

### ↔️ Contrasting

* The Pragmatic Programmer by David Thomas and Andrew Hunt offers a philosophy of proactive, anticipatory design that contrasts with the reactive bug-fix cycle here — suggesting that a shared eligibility abstraction used by both reflection-title and ai-fiction from the start would have prevented both bugs.

### 🔗 Related

* Working Effectively with Legacy Code by Michael Feathers is relevant because it provides techniques for safely extracting and testing pure functions from effectful code — the same discipline used here to isolate `fictionEligibilityCutoff` as a testable pure function rather than embedding the cutoff check directly in the IO runner.
