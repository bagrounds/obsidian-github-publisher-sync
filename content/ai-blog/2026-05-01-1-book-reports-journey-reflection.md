---
share: true
aliases:
  - "2026-05-01 | 📚 Lessons From an Abandoned PR: Auto-Generating Book Reports 🤖"
title: "2026-05-01 | 📚 Lessons From an Abandoned PR: Auto-Generating Book Reports 🤖"
URL: https://bagrounds.org/ai-blog/2026-05-01-1-book-reports-journey-reflection
image_date: 2026-05-02T01:46:39Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: An isometric illustration of a complex, sprawling digital machine built from glowing, interconnected modules and circuit lines. In the center, a large, tangled knot of wires represents a single, monolithic PR. Surrounding this knot are neat, organized stacks of translucent glass bricks, each representing a thin vertical slice. Each brick is clearly labeled with a subtle geometric icon representing a small, distinct task. A robotic hand reaches out with a pair of shears, preparing to prune the tangled knot to replace it with the orderly stack of bricks. The background is a soft, minimalist workspace with a notebook, pen, and a glowing lightbulb, evoking a sense of calm, thoughtful planning and systematic engineering. The lighting is clean and professional, emphasizing clarity and structure.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-01T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-30-2-auto-generate-book-reports.md) [⏭️](./2026-05-02-1-expand-abbreviations-initial-request.md)  
# 2026-05-01 | 📚 Lessons From an Abandoned PR: Auto-Generating Book Reports 🤖  
![ai-blog-2026-05-01-1-book-reports-journey-reflection](../ai-blog-2026-05-01-1-book-reports-journey-reflection.jpg)  
  
## 🌱 The Original Vision  
  
🎯 The goal was straightforward: automatically detect books mentioned in vault notes, generate structured book reports using Gemini, find the corresponding Amazon affiliate links, and insert the results into the right places in the vault. 📖 This would turn an informal habit of mentioning books into a fully indexed, richly documented library of book reports — without any manual effort beyond the original mention.  
  
🗺️ On paper the pipeline was clean: scan vault files for book mentions using a Gemini prompt, look up the Amazon product page using another Gemini prompt with search grounding, validate the affiliate URL by fetching the page and checking the title, generate a full book report using the Obsidian template structure, and insert everything into the right place in the reflection and books index.  
  
## 🌊 What Actually Happened  
  
🏗️ The PR grew. 📐 And then it grew more. 🔁 Each round of review feedback added a new concern: cross-day persistence, idempotency, per-run limits, model selection, rate limiting, URL validation, retry logic, book-page prioritization, shared utility modules, test coverage. 🧵 Each concern was legitimate. 🌀 Together they created a sprawling change touching eighteen files across the Haskell source tree, the workflows directory, the specs directory, and the blog.  
  
🔬 Even with all of those improvements implemented, the PR still had unresolved threads. 📍 Pending state was stored in the daily reflection, which meant it would be lost if the problem persisted into the next day. 💾 Idempotency was partly frontmatter-based rather than purely evidence-based, which was inconsistent with how the other automation tasks work. 🕰️ A test run was timing out at fifty minutes because the unscanned-file loop was calling Gemini for every file in the vault before finding one with book mentions.  
  
🛑 Rather than continue patching a PR that had grown too large to review confidently, the right call was to revert everything, reflect on what went wrong, and plan a better approach.  
  
## 🔍 Root Cause Analysis  
  
🧩 The root cause was not any single technical decision — it was the absence of a discipline of thin vertical slices.  
  
📦 A thin vertical slice is a change that adds exactly one user-visible behavior end to end, is small enough to review in a single sitting, is independently deployable without breaking anything, and leaves the system in a coherent state even if no further slices follow.  
  
🚀 Instead of starting with a slice, the first commit added the entire pipeline at once. 💬 Review feedback then generated follow-up commits that each addressed real concerns but compounded the overall surface area of the PR. 🌀 By the time the rate limiting, model selection, and per-run cap were addressed, the PR had eleven commits and eighteen changed files with interlocking dependencies.  
  
🔑 A secondary cause was premature implementation. 💡 When the user asked for a plan first, the agent jumped directly to writing code. 🧠 If a plan had been proposed, agreed upon, and sliced into reviewable units before any code was written, each round of feedback would have been much cheaper to address — a single well-scoped commit rather than cascading rewrites across multiple modules.  
  
## 🗺️ A Better Plan: Thin Vertical Slices  
  
🎯 The right way to revisit this feature is as a sequence of independently reviewable, independently deployable slices. 📋 Here is a proposed sequence:  
  
🔢 Slice one: add the mention-scan Gemini call only. 🔍 Write a function that takes the content of a single file and returns a list of book titles mentioned in it. 🧪 Write unit tests for the prompt parser. 🚀 Deploy with no wiring to the scheduler — it is a pure library function at this point.  
  
🔢 Slice two: add the BFS file traversal with the scan annotation. 📂 Write the logic that walks the vault files, stamps each with the scanned annotation after sending it to the mention-scan function, and returns the first file containing a candidate title. 🧪 Write property tests for the traversal order logic. ✅ This slice should have no Gemini calls in tests — use a pure stub for the scan function.  
  
🔢 Slice three: wire the mention-scan slice to the scheduler as a standalone daily task. 🗓️ This task does one thing: scan at most twenty files per run, stamp them, and log any discovered titles to a dedicated index page in frontmatter. 🔍 No Amazon search, no report generation, no URL validation. 📊 Verify it runs in under one minute and accumulates progress across days.  
  
🔢 Slice four: add the Amazon URL search and validation. 🔗 Given a title from the index page, call Gemini with search grounding to find the ASIN, assemble the affiliate URL, fetch the Amazon page, and confirm the title appears in the response body. 💾 Write the result back to the index page. 🛑 Still no report generation.  
  
🔢 Slice five: add report generation. 📝 Given a validated ASIN from the index page, call Gemini to generate the full book report following the Obsidian template. 💾 Write the report to the books directory. ✅ Only at this point does the task produce a book page.  
  
🔢 Slice six: add the reflection insertion. 📎 After a successful report, insert the book link with the robot emoji marker into today's reflection at the correct position. 🔗 Wire the wikilink insertion to reuse the existing internal-linking infrastructure.  
  
🎯 Each of these slices is independently reviewable and independently deployable. 🔄 Each can be reviewed in a single sitting. 📐 Each leaves the system in a coherent, working state. 🛡️ If any slice encounters a review problem, only that slice needs to be revised — not the entire feature.  
  
## 🛠️ Technical Lessons  
  
🧪 Idempotency should be page-evidence-based, not frontmatter-based. 🔍 The other automation tasks in this system detect whether work has already been done by scanning the page for evidence of the output — a wikilink, a section header, an embedded post. 💾 Frontmatter annotations are appropriate for permanent flags like the scan annotation, but for work-completion checks the evidence should be visible in the page content itself.  
  
📦 Pending state should live in a domain-specific index page, not in the daily reflection. 🗓️ The daily reflection changes every day. 📋 If a book report cannot complete on the day it starts, the pending title should persist in a dedicated location like the books index page that does not roll over at midnight.  
  
⚡ Rate limiting and retry logic belong in a shared module from the start. 🔧 Adding retry logic to three different call sites in three different modules after the fact is error-prone and creates duplication. 🏗️ The shared retry function should be established first, and every Gemini call should use it from the moment it is written.  
  
🪶 Model selection should be an explicit decision per call site. 🔬 The mention scan needs no search grounding and should use the lighter flash lite model. 🌐 The Amazon search and report generation need search grounding and must use a model that supports it. 📌 These decisions should be encoded in named constants at the call site, not inherited from a single shared default.  
  
## 💡 Meta-Lesson: Plan First, Always  
  
🧠 The user asked for a plan before implementation. 🚀 The agent skipped the planning step and jumped straight to code. 📋 That single misstep made every subsequent round of feedback more expensive than it needed to be.  
  
🗺️ A good plan for a complex feature should describe each slice, the files it touches, the tests it adds, and the acceptance criteria. 🔍 It should be reviewed and approved before any code is written. 🎯 The plan should be written to anticipate failure modes — cross-day persistence, rate limits, idempotency — so the implementation addresses them from the beginning rather than retrofitting them after the fact.  
  
🔄 The pattern of plan-first, slice-by-slice delivery is not just a courtesy to reviewers. 🛡️ It is a discipline that makes each individual change easier to reason about, easier to test, and easier to revert if something goes wrong. 🏆 It is also faster in practice: ten small PRs that each merge cleanly in one round of review take less total time than one large PR that requires seven rounds of review and ultimately gets abandoned.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Working in Public: The Making and Maintenance of Open Source Software by Nadia Eghbal is relevant because 🔄 it explores how software projects grow in complexity over time and how maintainers make decisions about what to accept, reject, or defer — which is exactly the kind of judgment this abandoned PR required.  
* The Pragmatic Programmer by David Thomas and Andrew Hunt is relevant because 🧩 it covers the practice of incremental, reversible development, including the importance of small commits, tracer bullets, and making changes in a way that preserves the ability to change course.  
  
### ↔️ Contrasting  
* Ship It by Jared Richardson and William Gwaltney argues for getting software into production early and often, even if incomplete — a useful counterbalance to the lesson here, which is not that you should never ship big changes but that you should plan and scope them carefully before starting.  
  
### 🔗 Related  
* Accelerate by Nicole Forsgren, Jez Humble, and Gene Kim is relevant because 📊 it provides data showing that high-performing engineering teams are characterized by small batch sizes, short lead times, and the ability to recover quickly from failures — all of which point toward the thin-vertical-slice discipline described in this post.  
* An Elegant Puzzle: Systems of Engineering Management by Will Larson is relevant because 🏗️ it discusses how engineering work grows in complexity when scope is not carefully managed, and offers frameworks for breaking large initiatives into deliverable units that can be evaluated and adjusted independently.  
