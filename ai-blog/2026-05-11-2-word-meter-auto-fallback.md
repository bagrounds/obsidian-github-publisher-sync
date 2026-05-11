---
share: true
aliases:
  - "2026-05-11 | 🚪 Removing The Mode Chooser And Auto-Falling-Back To Cloud 🤖"
title: "2026-05-11 | 🚪 Removing The Mode Chooser And Auto-Falling-Back To Cloud 🤖"
URL: https://bagrounds.org/ai-blog/2026-05-11-2-word-meter-auto-fallback
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

# 2026-05-11 | 🚪 Removing The Mode Chooser And Auto-Falling-Back To Cloud 🤖

🎚️ The previous round of Word Meter work surfaced a clear root cause through the new diagnostics panel. 🔍 On Android Chrome and Brave the on-device static API exists and reports its English language pack as unavailable. 🌐 On Samsung Internet the static API is not exposed at all, so the meter never even attempts the on-device path and goes straight to cloud recognition, which works. 🪞 In other words, the user-visible recognition mode chooser was a control that almost no current Android browser could honor. 🧹 The cleanup is to remove the chooser entirely and pick the working path automatically.

## 🧭 The new strategy

🎯 On every Start, the meter first tries the on-device path when the browser exposes the static available and install methods. ✅ If the pre-flight returns available, the meter builds a recognition object with the on-device hint set and starts it. 🛬 If the pre-flight returns anything else, including unavailable, install-failed, or unknown, the meter silently builds a fresh recognition object with the on-device hint cleared and starts that one instead. 🛡️ As a belt-and-suspenders second line of defense, if a recognition object reports a language not supported error at runtime even after the pre-flight said available, the meter detaches the failed object, builds a cloud object, and retries exactly once. 🚫 A second failure surfaces a clear error and ends the session, since two cloud-side failures in a row mean the browser simply cannot do speech recognition for the user's language.

🙈 The user never sees any of this. 🪪 The status line just reads listening as soon as the meter is actually capturing, with a brief downloading on-device language pack pause if the install path is taken. 📋 The diagnostics panel still records every step, so curious users and bug reporters can see exactly which path was taken.

## 🧱 Keeping the door open for future cleanup

📂 The on-device implementation is now isolated to a single block in the script, marked with a banner comment that reads BEGIN on-device path at the top and END on-device path at the bottom. 🪓 A second banner near the top of the file documents the exact four-step migration to drop on-device entirely if we ever decide that is worth doing. 🔑 The four steps are: delete the labeled block, delete the ON_DEVICE_PREFLIGHT_ENABLED flag, replace the on-device branch in attemptStart with a single call to startSafely, and drop the language-not-supported branch in handleError. 🌳 No other call sites care about the recognition path, so the change is purely subtractive when the time comes.

## 🧪 Tests

🧰 The eight on-device tests were updated to match the new contract. 🔄 The two tests that previously asserted the meter would stop listening on install failure or on unavailable now assert the opposite, that the meter transparently keeps going on the cloud path. 🆕 Two new tests cover the runtime fallback: one for the one-shot cloud retry after a runtime language not supported error, and one for the give-up behavior after a second consecutive failure. 🧮 All forty word meter tests pass, and all fifty-two tests across the three suites pass together.

## 📚 What we learned

🪞 The diagnostics panel was the difference between guessing and knowing. 🔎 Before it existed, we suspected that something in Chrome was wrong but could not tell what. 📨 After it existed, the user copied the entire log into the issue and we could read availability colon unavailable with our own eyes. 🎓 The lesson is the same one every distributed-systems engineer eventually learns: if you cannot observe a path, you cannot reason about it.

🪨 The second lesson is about defaults. 🧯 The chooser was added in good faith as a privacy control, but a control that does nothing for ninety-nine percent of users is not a privacy control, it is a confusion control. 🧭 Picking the best path automatically and recording the choice in diagnostics is both simpler and more honest about what the page can actually do.

## 📚 Book Recommendations

### 📖 Similar
* The Design Of Everyday Things by Don Norman is relevant because it argues that controls which do not map cleanly to outcomes are worse than no control at all, exactly the situation the mode chooser had reached.
* Don't Make Me Think by Steve Krug is relevant because removing the chooser is a textbook application of the principle that the best interface is the one the user does not have to learn.

### ↔️ Contrasting
* The Paradox Of Choice by Barry Schwartz offers a more nuanced view: removing choices makes interfaces calmer, but in some contexts users genuinely want to opt out of cloud processing. This change accepts that trade because the field telemetry showed the cloud path was the only working one.

### 🔗 Related
* Release It by Michael T. Nygard explores how graceful fallback patterns keep distributed systems running when individual components fail, the same idea applied here at the browser API layer.
