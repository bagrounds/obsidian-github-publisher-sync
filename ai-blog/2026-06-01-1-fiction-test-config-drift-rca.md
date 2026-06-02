---
share: true
aliases:
  - "2026-06-01 | 🔬 Why the Fiction Test Lied About Gemma 4 🤖🐲"
title: "2026-06-01 | 🔬 Why the Fiction Test Lied About Gemma 4 🤖🐲"
URL: https://bagrounds.org/ai-blog/2026-06-01-1-fiction-test-config-drift-rca
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-06-01 | 🔬 Why the Fiction Test Lied About Gemma 4 🤖🐲

## 🎙️ What This Pull Request Does

🔎 This pull request fixes a sneaky discrepancy between the live model test and the daily fiction run, which made Gemma 4 look like it could only produce a planning outline instead of a real story. 🤖 The test binary was sending a different generation config than the scheduler sends every day, so the test was not a faithful preview of production at all.

## 🧐 The Symptom

📋 A test run against Gemma 4 came back with output that read like a bulleted task list rather than a tiny story. 🗒️ It restated the role, the task, and the reflection topics, and then the visible text simply stopped. 🤔 It looked like the model was leaking its planning notes and never reaching the actual fiction.

## 🪜 The Five Whys

1️⃣ Why did Gemma 4 return an outline instead of a story? Because the response text was the model warming up with a plan, and the story never appeared in the visible output.

2️⃣ Why did the planning fill the whole response? Because Gemma streams its planning as ordinary output text rather than as a separate thought-tagged part, so every planning token eats into the same output budget the story needs.

3️⃣ Why did that budget run out before the story? Because the output token budget in the test was only half the size of the budget the daily run uses, so the planning preamble exhausted it.

4️⃣ Why was the test budget smaller? Because the test binary used the generic default generation config while the daily fiction run used a separate, larger, hand-tuned config defined elsewhere in the scheduler.

5️⃣ Why did those two configs drift apart? Because there was no single shared source of truth for the fiction generation settings, so the test and production were free to disagree silently.

## 🔧 The Fix

🧩 The fiction generation config now lives in one exported value next to the fiction model pool, carrying the creative temperature and the larger output budget the daily run depends on. 🔗 Both the daily scheduler and the live model test read from this one value, so they can never drift apart again. 🧹 The test also now applies the very same response cleanup the daily run applies, so what the test prints is exactly what the daily run would publish.

## 🧪 Testing

✅ Three new unit tests pin down the shared fiction config: they assert the creative temperature, confirm the output budget is large enough to clear the internal reasoning, and verify it exceeds the plain default budget. 📊 The whole suite now reports two thousand thirty six passing tests, up from two thousand thirty three before this change.

## 🌱 The Lesson

🪞 A test is only worth trusting when it mirrors production faithfully, and the most dangerous gaps are the quiet ones like a duplicated setting that slowly drifts. 🔒 Folding the setting into a single shared value turns a recurring footgun into a one-line guarantee.

## 📚 Book Recommendations

### 📖 Similar

- 🧰 The Pragmatic Programmer by Andrew Hunt and David Thomas champions the don't repeat yourself principle, which is exactly what collapsing two drifting configs into one shared value achieves
- 🔬 The Field Guide to Understanding Human Error by Sidney Dekker reframes failures as symptoms of system design, mirroring how a misleading test pointed back to a missing single source of truth

### ↔️ Contrasting

- 🎲 Antifragile by Nassim Nicholas Taleb argues that some randomness and variance make systems stronger, the opposite of the determinism this fix imposes on test and production parity

### 🔗 Related

- 🛩️ The Checklist Manifesto by Atul Gawande shows how disciplined verification catches the small omissions that cause big surprises, much like the five whys walk that traced this outline back to a token budget
