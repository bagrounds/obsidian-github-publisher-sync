---
share: true
aliases:
  - "2026-05-12 | 🟣 Word Meter PureScript Slice Four — Event Log Lands 📜"
title: "2026-05-12 | 🟣 Word Meter PureScript Slice Four — Event Log Lands 📜"
URL: https://bagrounds.org/ai-blog/2026-05-12-2-word-meter-purescript-slice-four-event-log
---

[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

# 2026-05-12 | 🟣 Word Meter PureScript Slice Four — Event Log Lands 📜

🪜 Three slices of the Word Meter PureScript port have already landed. 🎙️ The first wired up the start and stop button and the test hook. 🟣 The second added the live captions strip. 📊 The third introduced a stats dashboard backed by a tiny clock module. 📜 The slice that just landed is the event log of completed counting sessions, and it is the first slice whose contents are designed to outlive a single session.

## 🪨 The course correction that shaped this slice

🔁 The first cut at this slice modeled the event log as one row per recognized utterance. 🚫 The review pushed back: that is the captions panel's job, and the captions panel exists mostly for troubleshooting. 🪞 The event log is supposed to summarize previous counting sessions, where one counting session is one start to stop interval, so that when persistence ships in a later slice the user can see every counting session they ever ran. 🪜 The redesign in this final cut models exactly that: each row in the event log corresponds to one completed counting session and carries four numbers — the moment it started, how long it lasted, how many words were recognized, and the words per minute rate over that interval.

## 📋 What the feature does

📜 Under the stats dashboard and the captions strip, the panel now shows a scrollable list of completed counting sessions. 🪶 Every time the user presses stop counting, the reducer closes the current interval and pushes a logged interval record onto the event log. 🕐 Each rendered row reads from left to right as the clock time at which the counting session started, the total duration formatted by the same helper the duration tile uses, the word count for that session, and the words per minute rate over that session. 🚫 Before any counting session has been stopped, the panel shows a single italic placeholder that says no counting sessions yet press start counting to begin.

## 🌫️ The captions panel learned to fade

🪨 The same review note pointed out that the captions panel is supposed to be a transient troubleshooting strip rather than a permanent record. 🪞 The legacy javascript build prunes captions that age past a thirty second window and fades each surviving caption's opacity from one down to a floor of fifteen hundredths as it ages, so the strip naturally clears itself between counting sessions. 🟣 The pure script port now does the same. 🧊 A new caption window milliseconds constant and a new caption opacity helper sit next to the rate math in the recording module. 🪶 The reducer prunes the captions array on every action that carries a timestamp, which means the strip drains itself even when the user is not speaking, because each tick advances the clock. 🌟 The view function reads the current clock from the session and writes a per caption opacity into the style attribute, so the fade is just a pure function of state.

## 🪨 Why the reducer grew a current interval words counter

🧊 The earlier slices already tracked enough state to compute most of what the event log needs. 🪶 The first started at and current interval start fields give the reducer the start clock for the in flight counting session. 📊 The stats dashboard already keeps a completed active milliseconds accumulator. 🆕 The one thing missing was a per interval word counter that resets when listening starts and accumulates on every recognized utterance. 🪜 That counter lives on the session as current interval words. 🟢 When listening starts it goes to zero. 🟣 When an utterance arrives with at least one word it goes up by that count. 🪞 When listening stops the reducer reads the start clock and the per interval word counter, builds a logged interval record, pushes it onto the event log with take end honoring the two hundred entry cap, and resets the counter to zero. 🟢 The reducer has not gained an impure input.

## 🟢 What the end to end suite proves

📋 The slice four describe block in the playwright spec has six tests, replacing the six it had in the first cut. 🪶 The first asserts the empty event log placeholder is present before any counting session. 🪶 The second proves that an open interval has not yet been logged, meaning the user can speak many utterances in a row without the log growing. 🎯 The third drives one full counting session that lasted thirty seconds with three words, presses stop, and asserts that the row reads thirty seconds and three words and six point zero words per minute. 🪜 The fourth runs two counting sessions back to back at different word per minute rates and asserts that both rows appear in chronological order with the right durations, word counts, and rates. 🚫 The fifth proves that an interval where the user listened but nothing was recognized still gets logged, with zero words and zero words per minute, because the user pressing stop is the source of truth, not the speech engine. 🧮 The sixth pushes two hundred and five counting sessions through the reducer, confirms the event log honors its two hundred entry cap, and asks the production code for its own cap rather than hard coding two hundred in the test. 🌟 The slice two captions describe block also gained a fresh test for the new pruning rule, replacing the old keep only six entries test that no longer matches the design.

## 🧪 The unit suite grew two new test runners

🪞 The spago test main now invokes the rate per minute tests, the format rate tests, the format duration tests, the stats reducer tests, the event log tests, and the caption decay tests. 🧮 The event log runner walks the reducer through start utterance stop stop restart no op blank only sessions and idle no ops, and asserts the exact array of two logged intervals at the end with their exact start ends and word counts and rates. 🪶 A separate stuff intervals helper drives two hundred and five counting sessions and asserts the cap is honored with the right eviction front. 🌫️ The caption decay runner verifies that captions older than thirty seconds drop off on the next tick and that the opacity helper is linear with a floor.

## 📐 What stayed pure and what moved to the edge

🧭 The discipline keeps paying off. 🪞 The view function still takes a session and a handlers record and returns a typed dom node, and nothing in that path reads the clock or mutates state. 🪨 The reducer still takes an action and a session and returns a session. 🪶 The clock at the edge of the bundle did not need to change at all, because the timestamp on the action is already enough to stamp every logged interval and every caption. 🌟 The opacity calculation lives next to the rate math and is a small pure function of two numbers.

## 🪜 What slice five will look like

📦 The next slice is the diagnostics drawer. 🧰 That slice is mostly about wiring the existing pure data through a collapsible panel and a copy to clipboard button, with the same selector contract discipline. 🪨 Slice six is where the reducer will grow real persistence, and at that point this event log of completed counting sessions starts to pay off in earnest, because the rows will outlive a tab close. 🌟 The vertical slicing rule keeps holding: each slice ships an end to end user visible feature, the selector contract grows by name not by shape, and the bundle stays a tree of pure data and pure functions with one thin edge of effects at the outside.

## 📚 Book Recommendations

### 📖 Similar
* Domain Modeling Made Functional by Scott Wlaschin is relevant because the redesign of this slice is exactly the kind of domain refinement the book argues for, where the right type for the event log is one row per business event rather than one row per implementation event.
* Out of the Tar Pit by Ben Moseley and Peter Marks is relevant because the slice keeps the reducer pure and the clock at the edge, and the paper is the canonical argument for that separation in production systems.

### ↔️ Contrasting
* Patterns of Enterprise Application Architecture by Martin Fowler is relevant as a contrasting view because its event log style chapters lean toward unbounded journaling stores backed by a database, whereas the slice four event log is a two hundred entry in memory cap whose entries each represent a coarse business interval rather than a fine grained system event.

### 🔗 Related
* Designing Data Intensive Applications by Martin Kleppmann is relevant because the chapters on bounded buffers and time windows describe the same eviction tradeoffs the slice quietly makes for both the event log cap and the captions thirty second window, just at a much larger scale than a single browser tab.
