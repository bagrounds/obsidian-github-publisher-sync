---
share: true
aliases:
  - 2026-05-18 | 📆 Word Meter Multi-Day Stats 📊
title: 2026-05-18 | 📆 Word Meter Multi-Day Stats 📊
URL: https://bagrounds.org/ai-blog/2026-05-18-1-word-meter-multi-day-stats
image_date: 2026-05-18T19:42:50Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, minimalist workspace featuring a high-end digital dashboard on a tablet screen. The screen displays a series of organized, glowing data tiles, including a prominent central number, bar charts representing daily progress, and a circular percentage gauge. The aesthetic is modern and professional, utilizing a soft color palette of deep navy, slate gray, and crisp white. Next to the tablet, a sleek fountain pen rests on a wooden desk surface, suggesting a blend of creative writing and precise data analysis. The lighting is soft and ambient, casting gentle shadows that emphasize the clean lines of the dashboard interface. The composition is balanced and uncluttered, conveying a sense of clarity, productivity, and analytical focus.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-18T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-05-17-3-word-meter-purescript-finish-it.md)  
# 2026-05-18 | 📆 Word Meter Multi-Day Stats 📊  
![ai-blog-2026-05-18-1-word-meter-multi-day-stats](../ai-blog-2026-05-18-1-word-meter-multi-day-stats.jpg)  
  
## 🎯 What Changed  
- 🔢 The big number on the Word Meter now reflects the words counted **today**, where today means midnight to midnight in your local timezone.  
- 🏷️ The label under that big number now reads "words today" instead of "words counted" to match the new meaning.  
- 📚 A new Total tile keeps the lifetime cumulative count since the very first start, so nothing about your long-term history is hidden.  
- 📅 A new Per Day tile averages your lifetime total over the number of calendar days since you first pressed start.  
- 🧪 A new Sample tile reports the percent of wall-clock time the meter has actually been recording since first start. Twelve hours of recording in a twenty-four hour wall span surfaces as fifty percent.  
- 🔭 The existing rate tiles (Last 1 min, Last 10 min, Overall), the Duration tile, and the Started timestamp tile all stay, so nothing was removed from the dashboard.  
  
## 🧠 Why This Matters  
- 🌒 Without a daily counter the big number kept growing forever, which made it impossible to use the meter to set a daily speaking goal or even to know how chatty a single day has been.  
- 🪟 Without a per-day average the lifetime total was hard to read across many days of use, because a thousand words is impressive over a week but ordinary over a year.  
- 🩺 Without a sample percent there was no way to know whether the meter actually saw your day or whether you forgot to press start, which mattered most for long ambient sessions.  
- 🧭 Reviewing the whole stats display together made it clear that the existing rate tiles were still useful and should keep their places, so the new tiles slot in next to them rather than replacing anything.  
  
## 🧰 How It Works  
- 📐 The session now carries a small additional state pair: a today's-words counter and a stamp of the local calendar date that counter belongs to.  
- 🕒 Every time a transcript is counted or the live tick fires, the meter compares the timestamp's local date to the stored date and resets the today counter to zero when they differ.  
- 🧮 The per-day math divides the lifetime total by the wall-clock span since first start, clamped to a minimum of one day so a brand new session never divides by zero.  
- 🎚️ The sample math divides active listening time by wall-clock span and clamps the result between zero and one, so a paused meter never reads negative and a meter that ran every second of the wall span reads exactly one hundred percent.  
- 🗃️ The today counter and the local date are also written to localStorage as optional fields, so payloads from earlier builds keep loading and a fresh page on a fresh day correctly shows the big number at zero while the Total tile preserves the full history.  
  
## 🧪 How It Is Tested  
- 🧱 The PureScript unit suite covers the new percent formatter, the per-day math, the sample fraction math, the daily rollover behavior on tick, the rollover behavior on a new-day transcript, the reset path, and a persistence round trip including the legacy-payload defaults.  
- 🌐 The Playwright end-to-end suite covers the new tile labels, the renamed big-number label, the live increment of today's count, the rollover across a synthetic seven-day tick, the sample percent rendering, and the per-day average rendering.  
- 🔁 The existing persistence test was updated to read the lifetime total from the new Total tile rather than the big number, because the big number now reflects today and a synthetic 1970 timestamp is intentionally not "today" after a real-clock page reload.  
- 🧊 Two new property tests guard generic invariants: the sample fraction stays between zero and one for arbitrary positive wall and active inputs, and the percent formatter always contains a percent sign.  
  
## 🔄 Backward Compatibility  
- 🛡️ Existing localStorage payloads that predate this change keep loading because the new fields decode with safe defaults of zero and absent.  
- 🪶 The persisted snapshot format stays on the same v1 envelope, so no migration code is needed.  
- 🧷 The first live tick after a reload re-checks the local date and silently rolls today's counter to zero when the calendar day has advanced since the last save.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
- [📈🎯✅📏 Measure What Matters: How Google, Bono, and the Gates Foundation Rock the World with OKRs](../books/measure-what-matters.md) by John Doerr is relevant because it argues that the right scoreboard turns abstract intention into daily behavior, and renaming the big number to words today is exactly that kind of scoreboard tweak.  
- The Quantified Self by Gary Wolf is relevant because the whole multi-day stats redesign sits in the long tradition of bending small instruments to support self knowledge over weeks rather than seconds.  
  
### ↔️ Contrasting  
- Four Thousand Weeks by Oliver Burkeman offers a contrasting view that tracking yet another daily number can crowd out the messy unmeasurable life the tracking was supposed to serve.  
  
### 🔗 Related  
- [💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md) by Donald A. Norman explores how labels and signifiers shape user expectations, which is precisely why renaming the count label mattered as much as adding the new tiles.  
- Functional Programming in Scala by Paul Chiusano and Rúnar Bjarnason explores how small pure helpers compose into bigger features, which is the same approach the today rollover and sample fraction take in the PureScript reducer.  
