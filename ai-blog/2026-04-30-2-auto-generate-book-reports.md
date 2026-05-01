---
share: true
aliases:
  - "2026-04-30 | 📚 Auto-Generating Book Reports 🤖"
title: "2026-04-30 | 📚 Auto-Generating Book Reports 🤖"
URL: https://bagrounds.org/ai-blog/2026-04-30-2-auto-generate-book-reports
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-30 | 📚 Auto-Generating Book Reports 🤖

## 🎯 What We Built

📚 This work adds a scheduled automation task that discovers book references in the personal knowledge base, finds the corresponding Amazon product pages, generates a full book report using Gemini, and wires everything back into the daily reflection.

🤖 The pipeline combines regex matching, structured Gemini inference, and Google Search grounding to produce rich book pages that follow the same Obsidian Templater format used for manually created book notes.

⏰ The task runs once per day at 1 AM Pacific time and generates at most one new book report per run. An idempotency check prevents the task from running a second time on the same day if a report has already been generated.

## 🧩 How It Works

### 🔍 Step One: Discovering Book Mentions

🌐 A BFS traversal walks the vault's content graph starting from the most recently linked notes. For each file visited, we ask Gemini to identify plain-text book mentions, meaning titles that appear in the body but are not already wrapped in double-bracket wikilinks.

🗂️ Those mentions are cross-referenced against the existing book index. Comparison is case-insensitive and emoji-stripped so a mention of "Sapiens" correctly matches an existing page titled "🧬 Sapiens: A Brief History of Humankind."

🔗 If a mentioned title already has a book page, we immediately insert a wikilink for it in the scanned file using the same infrastructure the internal-linking task uses, specifically the candidate-discovery and replacement engine. This closes the gap without a new book page needing to be generated.

📌 Newly discovered titles that do not yet have pages become candidates for full report generation. Only one book report is generated per run.

### 🔄 Step Two: Idempotency and Crash Recovery

📓 Before any expensive API calls, the task writes a frontmatter field called book-report-pending to today's reflection file with the candidate title. If the task is interrupted by a transient error such as a 503 response, the next run reads that field and resumes from the same title without repeating the BFS scan.

✅ Once a book report is successfully written and the reflection is updated, the task writes book-reports-run to today's reflection frontmatter with today's date. On any future run the same day, this field is detected and the task exits immediately without any API calls.

🚫 If the environment variable AMAZON_ASSOCIATE_TAG is not set, the task refuses to run entirely. Generating book pages without affiliate links would require manual cleanup later, so we fail fast rather than produce incomplete output.

### 🛒 Step Three: Finding the Amazon Product URL

🔗 For each candidate title we send a Gemini request with Google Search grounding asking for the Amazon.com product page URL for the most popular print version.

🔎 The response is inspected at two levels. First, the grounding source URLs are checked for Amazon product pages containing the slash-dp-slash ASIN pattern. Second, if no grounding source qualifies, the raw response text is checked for a valid Amazon URL.

📦 The ASIN extraction is careful to verify the segment is exactly ten alphanumeric characters. The affiliate URL is assembled as the Amazon dp path followed by the tag query parameter using the AMAZON_ASSOCIATE_TAG environment variable.

### 📝 Step Four: Generating the Book Report

✍️ With the title and affiliate link confirmed, we invoke Gemini once more with Google Search grounding to write the actual book report.

📋 The prompt follows the Obsidian book template structure and asks Gemini to:
- 🏷️ Output an emojified book title on the very first line, prefixed with the smallest set of emojis that accurately capture the book's meaning
- 🔤 Begin every heading, bullet point, and line of text with a relevant emoji
- 📝 Write a one-sentence TLDR followed by seven sections: AI Summary (ultra-concise cheat sheet), Evaluation (with citations from high-quality sources), Topics for Further Understanding, a FAQ section, Book Recommendations (split into Similar, Contrasting, and Related), and a What Do You Think section with open-ended discussion questions
- 🚫 Never quote or italicize titles

🔖 The emojified title is parsed from the first non-empty line of the Gemini response and used as both the H1 heading in the note body and the title and aliases fields in YAML frontmatter. The original plain title is used to derive the kebab-case slug for the file path, so the URL is always stable regardless of emoji changes.

### 📓 Step Five: Linking in the Daily Reflection

📅 Once the book file is written, the task opens today's reflection and inserts a wikilink under a new or existing Books section that links to the books index.

⬆️ The section is inserted before any trailing sections including social embeds such as Updates, Changes, Twitter, Bluesky, or Mastodon, and also before any auto-generated blog series sections such as the daily noise digest. The detection uses both a static prefix list and a dynamic scan for headings that match the pattern of auto-generated series sections, which all take the form of a level-two heading containing a wikilink to an index page.

🤖 Every automatically inserted book link is annotated with a robot emoji at the end. This makes it easy to distinguish links the automation added from links added manually.

## 🏗️ Architecture Decisions

### 🧊 Pure Core, IO at the Edges

🔬 All slug generation, ASIN extraction, affiliate URL construction, frontmatter assembly, body building, and reflection insertion are pure functions with no IO. The IO boundary is at the run function which handles file reads, Gemini calls, and writes.

🧪 This design makes every component testable with unit tests and property-based tests. The property tests verify that the kebab-case slug function never produces consecutive hyphens, never leaves leading or trailing hyphens, and only outputs lowercase alphanumeric characters and hyphens.

### ♻️ Reusing Shared Infrastructure

🧩 The implementation reuses existing modules rather than duplicating logic. The JSON array extraction and code-fence stripping utilities were already duplicated across the internal-linking Gemini module and the book-report Gemini module. These are now consolidated into the shared Gemini module and exported for use by both.

🔧 The frontmatter update function used internally by the internal-linking task is now in the Frontmatter module where it semantically belongs, making it available to the book-report task without any circular imports.

🔗 When inserting wikilinks for books that already have pages, the implementation calls directly into the candidate-discovery and replacement engine from the internal-linking module, avoiding any duplicate matching logic.

### 💾 Minimizing Inference Calls

🔢 Each book report run uses at most three Gemini API calls: one to scan a single file for plain-text mentions, one to search Amazon for the product URL, and one to generate the report. The BFS scan visits only one file per run rather than five, which keeps the per-run token cost low.

📌 Results from partially successful runs are persisted in frontmatter before the expensive downstream calls, so a transient failure never re-triggers the discovery scan on the next attempt.

🗓️ The once-daily schedule means there is at most one book report generated per day, which keeps the total inference budget predictable and avoids quota exhaustion.

### 📐 ASIN Extraction Safety

🔒 The ASIN extraction function stops at the first non-alphanumeric character, then verifies the segment is exactly ten characters. The property-based roundtrip test confirms that building an affiliate URL from a valid ASIN and then extracting the ASIN from that URL always returns the original.

## 🧪 Testing

✅ The implementation adds tests across two modules covering the full pipeline.

📋 The BookReport module tests cover title-to-kebab-case conversion with property tests for slug invariants, ASIN extraction with the roundtrip property, affiliate URL construction, frontmatter assembly including the emojified-title override, body building with and without affiliate links, reflection section insertion before blog series sections and social sections, idempotency, and the auto-generated robot-emoji marker.

📋 The BookReport.Gemini module tests cover the find-mentions prompt structure, JSON array parsing with code-fence stripping, the new seven-section report prompt structure including the AI Summary and FAQ sections, and the Amazon search prompt.

## 📚 Book Recommendations

### 📖 Similar

* The Personal MBA by Josh Kaufman is relevant because it is a self-education framework for learning from books, which resonates with building a personal library of automatically generated book reports to capture knowledge.

* How to Take Smart Notes by Sönke Ahrens is relevant because it describes the Zettelkasten method of building a knowledge graph from reading notes, which is exactly the kind of personal knowledge base this system is designed to enrich with automated annotations.

* Moonwalking with Einstein by Joshua Foer is relevant because it explores techniques for remembering information from books, a natural complement to automatically generating structured book summaries and linking them into a daily knowledge journal.

### ↔️ Contrasting

* Walden by Henry David Thoreau offers the view that the best learning comes from direct experience with the natural world rather than from accumulating and cataloging books.

### 🔗 Related

* The Information by James Gleick explores the history of how humans have catalogued, stored, and retrieved knowledge across centuries of technological change, from clay tablets to digital archives.

* Continuous Delivery by Jez Humble and David Farley covers the engineering practices behind automating software pipelines, directly relevant to the scheduled-task architecture and crash-recovery design that powers this book report generator.

