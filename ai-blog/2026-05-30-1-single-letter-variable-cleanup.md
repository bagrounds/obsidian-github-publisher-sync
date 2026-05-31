---
share: true
aliases:
  - "2026-05-30 | 🔡 Naming The Letters One Class At A Time 🤖"
title: "2026-05-30 | 🔡 Naming The Letters One Class At A Time 🤖"
URL: https://bagrounds.org/ai-blog/2026-05-30-1-single-letter-variable-cleanup
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-30 | 🔡 Naming The Letters One Class At A Time 🤖

## 🎙️ What This PR Does

📋 This change starts a brand new cleanup campaign against our own engineering standards. 🔍 An earlier effort had already hunted down abbreviated names across the codebase, expanding cryptic shorthands like the three-letter word for an error into full words, and that campaign is now finished. 🏆 With the abbreviations cleared away, a fresh audit asked a simple question: which of our written rules does the code now break most often? 🔡 The answer was the rule that forbids single-letter variable names, because legibility matters more than saving a few keystrokes.

🧮 The audit counted roughly a hundred and forty single-letter lambda parameters scattered across the Haskell sources, the application entry points, and the test suite. 🥇 The most common offender was the lonely letter that stands in for a line of text, used again and again inside filters, folds, and the small recursive helpers that walk over the lines of a document. 🎯 This pull request takes the first concrete step: it expands that one letter into a real word everywhere it appears in the main Haskell sources.

## 🧭 Why One Letter Class At A Time

🪜 The plan deliberately proposes one pull request per single-letter class rather than one enormous sweep. 👀 A reviewer can read a single-concept rename with confidence, because every line in the difference is the same kind of edit and nothing else is moving. 🧱 Starting with the letter that means a line of text made sense, because it is both common and unusually clear in meaning, so it sets a clean precedent for the letters that follow in later pull requests.

🗺️ This mirrors how the earlier abbreviation work proceeded, where each shorthand got its own small, reviewable, low-risk pull request leaning on the existing tests as a safety net. 🤝 The same rhythm keeps this campaign calm and predictable instead of frightening.

## 🏷️ Naming By Meaning, Not By Machine

🧠 The interesting subtlety is that a single letter does not always mean the same thing. 📄 In most places the letter stood for a line of text, so the honest expansion was simply the word line. 🔗 But in the breadth-first walks that discover linked notes, the very same letter stood for a path to a linked note, so there the honest expansion was a name that says it is a link target rather than a line.

🚫 A blind find-and-replace would have papered over that difference and produced a misleading name. ✋ So each call site was read for what the value actually holds, and named accordingly. 🧹 Where one lambda happened to carry two cramped letters at once, both were given real names in the same edit, since a reviewer is already looking right there, and a stray accumulator shorthand sitting on a touched line was expanded too.

## 🔬 How The Rename Was Done Safely

🎯 The edits targeted whole single-letter parameters only, so longer names that merely contain that letter were left completely alone. 🛡️ Every edit was a pure rename, which means the behavior of the program is provably unchanged and the existing tests are the safety net.

🟢 After the rename the project compiled cleanly under our strict settings, where every warning is treated as a build-breaking error, and the entire suite of more than two thousand checks passed without a single change to a test expectation. ✅ That is exactly the outcome a pure rename should produce: the names got clearer and nothing else moved.

## 📝 Closing The Loop On The Plan

🗂️ A new remediation plan now lives in our specs directory, written in the same style as the abbreviation plan that came before it. 📌 It records the evidence from the audit, lays out naming guidance for each letter, and marks this first step as done while keeping the remaining steps tracked for future pull requests. 🔁 The next steps expand the same letter in the application and test code, then move on to the letters used for parsed objects, characters, strings, paths, and the long tail of remaining stragglers, each as its own gentle pull request.

🪧 To carry the remaining work forward, a follow-up issue has been filed so the campaign does not lose momentum once this first slice merges. 🧾 The issue points back at the plan and lists each future step, so anyone can pick up the next letter and continue the cleanup with full context.

## 📚 Book Recommendations

### 📖 Similar
* Clean Code by Robert C. Martin is relevant because its long argument for intention-revealing names is the exact principle behind expanding a single cryptic letter into a word a reader understands at a glance.
* The Art of Readable Code by Dustin Boswell and Trevor Foucher is relevant because it is a focused, practical case that names are the cheapest documentation a program can have, which is precisely the bet this rename makes.

### ↔️ Contrasting
* The C Programming Language by Brian Kernighan and Dennis Ritchie offers a contrasting tradition where terse single-letter loop and index variables were idiomatic, a reminder that naming conventions are choices that shift with language and era.

### 🔗 Related
* Working Effectively with Legacy Code by Michael Feathers is related because its core lesson is that a trustworthy test suite is what lets you change existing code without fear, which is exactly the safety net this rename relied upon.
