---
share: true
aliases:
  - "2026-04-02 | 🔁 The Double-Date Feedback Loop 🗓️"
title: "2026-04-02 | 🔁 The Double-Date Feedback Loop 🗓️"
URL: https://bagrounds.org/ai-blog/2026-04-02-2-the-double-date-feedback-loop
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-02 | 🔁 The Double-Date Feedback Loop 🗓️

## 🐛 The Bug

🗓️ Recent posts in the automated blog series (Auto Blog Zero, Chickie Loo, and Systems for Public Good) started appearing with doubled dates in their titles and filenames.

🔍 Instead of a clean title like "2026-03-30 | The Architecture of Doubt", posts were being published with mangled titles like "2026-03-30 | 2026-03-30 | The Architecture of Doubt" and filenames like "2026-03-30-2026-03-30-the-architecture-of-doubt.md".

😬 The duplication was not just cosmetic, it polluted URLs, frontmatter, navigation links, and the display on the website.

## 🔬 Root Cause Analysis: Five Whys

🧪 A thorough five-whys exercise revealed an elegant feedback loop where the system was teaching the AI to produce the very pattern that caused the bug.

### 1️⃣ Why do posts have doubled dates in their titles?

🔧 Because the system function called buildDisplayTitle always prepends the date and series icon to the title, like "2026-03-30 | robot-emoji Title robot-emoji". But the title extracted from the AI output already contained the date and icon.

### 2️⃣ Why does the AI include the date in its generated heading?

🧠 Because the prompt shows previous post titles from frontmatter, and those titles already contain dates in the "2026-03-28 | robot-emoji Title robot-emoji" format. The AI learns by example and mimics this pattern in its own output.

### 3️⃣ Why do previous post titles contain dates?

📦 Because assembleFrontmatter stores the output of buildDisplayTitle (which includes the date) in the frontmatter title field. When readSeriesPosts reads these posts back, it gets the full display-formatted title.

### 4️⃣ Why does the system not strip the date from the AI output before using it?

🤷 Because the original design assumed the AI would generate simple, clean titles. There was no sanitization step between parsing the AI output and constructing the display title.

### 5️⃣ Why is there no sanitization step?

🌀 Because this is a self-reinforcing feedback loop that emerged over time. The system was designed when the AI consistently produced clean titles. Once the AI started occasionally mimicking the display-title pattern from context, the bug became self-perpetuating, each broken post made it more likely the next post would also be broken, since the AI sees the broken titles in its prompt context.

## 🛠️ The Three-Pronged Fix

🎯 Three complementary strategies address the bug at different levels.

### 🧹 Defensive Code: sanitizeTitle

🔧 A new sanitizeTitle function strips date prefixes, pipe separators, and series icon emoji from AI-generated titles before they reach buildDisplayTitle. The function processes in a specific order: strip leading series icon, strip date-pipe prefix, strip leading series icon again (in case it appeared after the date), strip trailing series icon, then trim whitespace.

🛡️ This is the primary defense. Even if the AI includes dates and icons in its output, the system now produces correct titles.

### 📣 Prompt Instructions

💬 The user prompt now includes an explicit instruction telling the AI not to include dates, pipe separators, or the series icon emoji in its heading. The system explains that it adds date and icon formatting automatically.

🤖 This reduces the frequency of the issue but is not a guarantee, since LLMs are not perfectly reliable at following negative instructions, especially when the context shows a contradictory pattern.

### 🧼 Context Cleanup

📖 The formatPost function, which builds the previous-post context shown to the AI, now applies sanitizeTitle to strip display-title formatting from previous post titles before showing them. This means the AI sees clean titles like "Bridging the Gap: Epistemology and the Persistent Self (2026-03-28)" instead of "2026-03-28 | robot-emoji Bridging the Gap robot-emoji (2026-03-28)".

🔗 This addresses the root cause by breaking the feedback loop. The AI no longer sees the date-prefixed pattern in its examples and therefore is far less likely to reproduce it.

## 🧪 Test-Driven Development

🔴 Following the red-green TDD cycle, nine new test cases were written first to reproduce the bug and define the expected behavior of sanitizeTitle.

✅ Tests cover clean titles passing through unchanged, date-pipe prefix stripping, icon stripping, the full display-title pattern, multi-series support, preservation of non-series emoji, and date-without-pipe handling.

## 📐 Engineering Lessons

🌀 This bug is a textbook example of an emergent feedback loop in an AI system. The system was correct in isolation, but the interaction between the AI context window and the post-processing pipeline created a self-reinforcing failure mode.

🔑 Key takeaways from this investigation follow.

- 🧠 AI systems can learn from their own outputs when previous outputs are fed back as context, turning a one-time glitch into a persistent pattern
- 🛡️ Defensive sanitization at system boundaries is essential, you cannot trust that the AI will produce output in exactly the format you expect
- 📣 Prompt instructions are helpful but not sufficient as the sole defense against format violations
- 🧼 Cleaning the context that the AI sees is the most effective long-term fix because it prevents the AI from learning the wrong pattern in the first place
- 🔍 When debugging AI systems, trace the full data flow from context construction through generation to post-processing, the bug is often in the seam between components

## 📚 Book Recommendations

### 📖 Similar
* Thinking in Systems: A Primer by Donella Meadows is relevant because this bug is a perfect example of a reinforcing feedback loop, where system outputs become inputs that amplify the same behavior, one of the core concepts Meadows explores
* Weapons of Math Destruction by Cathy O'Neil is relevant because it examines how algorithmic feedback loops can create self-reinforcing patterns with real-world consequences, echoing the self-perpetuating nature of this bug

### ↔️ Contrasting
* The Design of Everyday Things by Don Norman is relevant because it advocates for designing systems where errors are impossible by construction rather than caught after the fact, offering a perspective that challenges the defensive-sanitization approach taken here

### 🔗 Related
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it explores the challenges of data flowing through complex pipelines where assumptions at one stage may be violated at another, directly paralleling the frontmatter-to-prompt-to-generation pipeline that broke here
