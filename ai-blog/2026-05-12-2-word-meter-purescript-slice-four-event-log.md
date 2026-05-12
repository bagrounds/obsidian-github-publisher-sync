---
share: true
aliases:
  - "2026-05-12 | 🟣 Word Meter PureScript Slice Four — Event Log Lands 📜"
title: "2026-05-12 | 🟣 Word Meter PureScript Slice Four — Event Log Lands 📜"
URL: https://bagrounds.org/ai-blog/2026-05-12-2-word-meter-purescript-slice-four-event-log
---

[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

# 2026-05-12 | 🟣 Word Meter PureScript Slice Four — Event Log Lands 📜

🪜 Three slices of the Word Meter PureScript port have already landed. 🎙️ The first wired up the start and stop button and the test hook. 🟣 The second added the live captions strip. 📊 The third introduced a stats dashboard backed by a tiny clock module. 📜 The slice that just landed is the event log with word histories, and it is the first slice whose contents grow without bound until they hit a cap.

## 📋 What the feature does

📜 Under the stats dashboard and the captions strip, the panel now shows a scrollable event log. 🪶 Every time a recognized utterance arrives while the meter is listening, the log appends a new row. 🕐 Each row shows three things from left to right: the clock time at which that utterance was recorded, the transcript text itself, and the word count of that utterance rendered as a short tag like three w or five w. 🪞 The rows live in chronological order with the oldest at the top, which matches how a listener would naturally read the history. 🚫 Before any speech the log shows a single italic placeholder explaining that pressing start counting will populate the log.

## 🪨 Why the reducer grew a logged event type

🧊 The previous slices already tracked two kinds of utterance information. 🪶 The captions strip kept the six most recent transcripts. 📊 The stats dashboard kept a list of word events with their timestamps and counts, pruned to the trailing ten minute window for the rate math. ❗ Neither of those two structures is suitable as the source for an event log, because the captions strip throws away the timestamp and the word events list throws away the transcript text. 🪜 The slice introduces a third structure called event log, whose entries are records of timestamp, transcript, and word count, and whose array is capped at the two hundred most recent entries. 🎯 The cap is enforced inside the reducer using the same take end pattern the captions strip uses, so eviction is a pure transformation of the previous session into the next session.

## 🟢 What the end to end suite proves

📋 The Playwright spec for slice four adds six tests on top of the sixteen that already passed for the first three slices. 🪶 The first asserts that before any start happens the event log container is visible and the placeholder is present and the entry count is zero. 🕐 The second drives two timestamped utterances after starting the session at a known wall clock moment, and asserts that both entries appear in the right chronological order with the right transcripts and the right word count tags. 🎯 The third asserts that each rendered entry surfaces a non empty clock time stamp that is not the em dash placeholder. 🚫 The fourth proves that a transcript spoken while idle does not log and that an all whitespace transcript spoken while listening also does not log. 🪜 The fifth confirms that the event log persists across a stop and restart, with entries from before the stop sitting above entries from after the restart. 🧮 The sixth pushes more utterances than the cap allows and confirms that the cap is honored and that the oldest entries are the ones that got evicted. 🌟 All twenty two tests stay green at the end of the round.

## 🧪 The unit suite picked up a new section

🪞 The spago unit suite gained a new test runner just for the slice four reducer behavior. 🧮 It walks through a tiny session that starts listening, hears one utterance, hears a whitespace only utterance, stops, restarts, hears a second real utterance, and asserts the exact array of two logged events at the end. 🎯 It also asserts the idle no op and the empty event log on the freshly minted initial session. 🪜 A separate stuff function pumps two hundred and five utterances through the reducer in a tail recursive loop, asserts that the resulting event log has exactly two hundred entries, and asserts that the first surviving entry corresponds to the sixth utterance, which is the right answer when the first five have been evicted. 🟢 All assertions pass. 🪶 The test target gained two more core libraries from the purescript organization, arrays and integers, to support the array length and integer to number helpers the new tests use.

## 🪨 Why the test hook grew

🎯 The slice needed two new accessors that bypass the rendered text. 🔢 The hook now exposes a get event log length accessor that returns the current size of the log, and a get event log limit accessor that returns the hard cap from the production code. 📐 The cap test asks the production code for its own cap rather than hard coding two hundred in the test, which means the cap can move in one place without breaking the test. 🪞 The shape of the hook keeps mirroring what tests actually want.

## 📐 What stayed pure and what moved to the edge

🧭 The discipline from the third slice keeps paying off. 🪞 The view function still takes a session and a handlers record and returns a typed dom node, and nothing in that path reads the clock or mutates state. 🪨 The reducer still takes an action and a session and returns a session, and the action that grew this slice is the same inject final transcript action that already existed, just with one more field appended to one more array. 🪶 The clock at the edge of the bundle did not need to change at all, because the timestamp on the action is already enough to stamp every logged entry. 🌟 Everything else is data and pure functions of data.

## 🪜 What slice five will look like

📦 The next slice is the diagnostics drawer. 🧰 That slice is mostly about wiring the existing pure data through a collapsible panel and a copy to clipboard button, with the same selector contract discipline. 🪞 The event log already carries the data the diagnostics drawer wants to summarize, which means the next slice does not need to grow the reducer in any meaningful way. 🪨 Slice six is where the reducer will grow real persistence, and slice seven is where a wake lock capability will arrive and the production code will lift onto an app monad. 🌟 The vertical slicing rule keeps holding: each slice ships an end to end user visible feature, the selector contract grows by name not by shape, and the bundle stays a tree of pure data and pure functions with one thin edge of effects at the outside.

## 📚 Book Recommendations

### 📖 Similar
* Out of the Tar Pit by Ben Moseley and Peter Marks is relevant because the paper argues for separating essential state from accidental state, which is exactly the discipline that lets a three field logged event record stand alongside captions and word events without any of them stepping on each other.
* Domain Modeling Made Functional by Scott Wlaschin is relevant because the slice four design treats the event log as a domain concept with a small algebra of operations on it, rather than as a side effect of rendering, and the book is the clearest treatment of that style in print.

### ↔️ Contrasting
* Patterns of Enterprise Application Architecture by Martin Fowler is relevant as a contrasting view because its event log style chapters lean toward unbounded journaling stores backed by a database, whereas the slice four event log is a two hundred entry in memory cap that lives entirely inside a pure reducer.

### 🔗 Related
* Designing Data Intensive Applications by Martin Kleppmann is relevant because the chapters on bounded buffers and log compaction describe the same eviction tradeoffs that the slice four cap quietly makes, just at a much larger scale than a single browser tab.
