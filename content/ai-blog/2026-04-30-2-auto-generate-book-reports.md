---
share: true
aliases:
  - 2026-04-30 | 📚 Auto-Generating Book Reports 🤖
title: 2026-04-30 | 📚 Auto-Generating Book Reports 🤖
URL: https://bagrounds.org/ai-blog/2026-04-30-2-auto-generate-book-reports
image_date: 2026-05-01T20:27:30Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: "A clean, isometric-style illustration featuring a glowing, translucent digital brain integrated with the spine of an open leather-bound book. Floating in the air above the book are holographic, colorful icons representing knowledge: a magnifying glass, a robot head, a barcode, and small floating index cards. A soft, warm light emanates from the center of the book, casting gentle shadows on a minimalist desk surface. In the background, a subtle, ethereal network of lines and nodes suggests a knowledge graph connecting the pages of the book to the digital realm. The color palette consists of soft teals, warm paper-whites, and vibrant digital purples, creating a sense of sophisticated automation and academic discovery."
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-01T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-30-1-deploy-main-branch-only.md)  
# 2026-04-30 | 📚 Auto-Generating Book Reports 🤖  
![ai-blog-2026-04-30-2-auto-generate-book-reports](../ai-blog-2026-04-30-2-auto-generate-book-reports.jpg)  
  
## 🎯 What We Built  
  
📚 This work adds a scheduled automation task that discovers book references in the personal knowledge base, finds the corresponding Amazon product pages, generates a full book report using Gemini, and wires everything back into the daily reflection.  
  
🤖 The pipeline combines BFS graph traversal, structured Gemini inference, Google Search grounding, and HTTP URL validation to produce rich book pages that follow the same Obsidian Templater format used for manually created book notes.  
  
⏰ The task runs once per day at 1 AM Pacific time and generates at most one new book report per run. Idempotency is detected by scanning the reflection page for evidence rather than relying on a frontmatter flag.  
  
## 🧩 How It Works  
  
### 🔍 Step One: Discovering Book Mentions  
  
🌐 A BFS traversal walks the vault's content graph starting from the most recently linked notes. For each file visited, we ask Gemini to identify plain-text book mentions, meaning titles that appear in the body but are not already wrapped in double-bracket wikilinks.  
  
🗂️ Those mentions are cross-referenced against the existing book index. Comparison is case-insensitive and emoji-stripped so a mention of "Sapiens" correctly matches an existing page titled "🧬 [📜🌍⏳ Sapiens: A Brief History of Humankind](../books/sapiens-a-brief-history-of-humankind.md)."  
  
🔗 If a mentioned title already has a book page, we immediately insert a wikilink for it in the scanned file using the same infrastructure the internal-linking task uses, specifically the candidate-discovery and replacement engine. This closes the gap without a new book page needing to be generated.  
  
💾 After scanning each file, the task writes a book-mention-scanned field with today's date to that file's frontmatter. On a retry within the same day, the task sees this field and skips the file entirely, avoiding a redundant Gemini inference call.  
  
📌 Newly discovered titles that do not yet have pages become candidates for full report generation. Only one book report is generated per run.  
  
### 🔄 Step Two: Idempotency and Crash Recovery  
  
🔎 Idempotency is detected by scanning today's reflection body for evidence: a list item starting with the books wikilink prefix and ending with the robot-emoji marker. If any such line is found, the task exits immediately. This mirrors how other content automation tasks detect prior work — by looking at what is on the page, not at a separately maintained frontmatter flag.  
  
📚 When a new candidate is identified, the task immediately writes a book-report-pending field to the books index frontmatter. Unlike the daily reflection, the books index is not tied to a specific date, so this pending state survives across day boundaries. If Gemini is unavailable all day on Monday, the Tuesday run can resume from the same title without repeating the BFS scan.  
  
🔑 Once Amazon search succeeds, the extracted ASIN is written to the books index as book-report-asin. If the process exits before generating the report, the next run reads the cached ASIN and skips the Amazon search step entirely, going straight to report generation.  
  
🧹 After a report is successfully written and the reflection is updated, both book-report-pending and book-report-asin are cleared from the books index frontmatter, leaving it in a clean state for the next run.  
  
🚫 If the environment variable AMAZON_ASSOCIATE_TAG is not set, the task refuses to run entirely. Generating book pages without affiliate links would require manual cleanup later, so we fail fast rather than produce incomplete output.  
  
### 🛒 Step Three: Finding and Validating the Amazon Product URL  
  
🔗 For each candidate title we send a Gemini request with Google Search grounding asking for the Amazon.com product page URL for the most popular print version.  
  
🔎 The response is inspected at two levels. First, the grounding source URLs are checked for Amazon product pages containing the slash-dp-slash ASIN pattern. Second, if no grounding source qualifies, the raw response text is checked for a valid Amazon URL.  
  
📦 The ASIN extraction is careful to verify the segment is exactly ten alphanumeric characters. The affiliate URL is assembled as the Amazon dp path followed by the tag query parameter using the AMAZON_ASSOCIATE_TAG environment variable.  
  
🔍 Once the affiliate URL is assembled, it is validated by fetching the page over HTTP. A 404 response means the URL does not exist and the candidate is skipped immediately. A 200 response confirms the page exists; the response body is also scanned for the book title as a best-effort check that the URL points to the right book. Transient errors such as connection failures, 429 responses, and 5xx server errors are retried up to three times with exponential back-off starting at two seconds. If the URL cannot be confirmed after all retries are exhausted, the candidate is skipped so the task never blindly accepts an unverified URL.  
  
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
  
🤖 Every automatically inserted book link is annotated with a robot emoji at the end. This makes it easy to distinguish links the automation added from links added manually, and it is precisely what the idempotency check looks for on the next run.  
  
## 🏗️ Architecture Decisions  
  
### 🧊 Pure Core, IO at the Edges  
  
🔬 All slug generation, ASIN extraction, affiliate URL construction, frontmatter assembly, body building, and reflection insertion are pure functions with no IO. The IO boundary is at the run function which handles file reads, HTTP fetches, Gemini calls, and writes.  
  
🧪 This design makes every component testable with unit tests and property-based tests. The property tests verify that the kebab-case slug function never produces consecutive hyphens, never leaves leading or trailing hyphens, and only outputs lowercase alphanumeric characters and hyphens.  
  
### ♻️ Reusing Shared Infrastructure  
  
🧩 The implementation reuses existing modules rather than duplicating logic. The JSON array extraction and code-fence stripping utilities were already duplicated across the internal-linking Gemini module and the book-report Gemini module. These are now consolidated into the shared Gemini module and exported for use by both.  
  
🔧 The frontmatter update function used internally by the internal-linking task is now in the Frontmatter module where it semantically belongs, making it available to the book-report task without any circular imports.  
  
🔗 When inserting wikilinks for books that already have pages, the implementation calls directly into the candidate-discovery and replacement engine from the internal-linking module, avoiding any duplicate matching logic.  
  
### 💾 Caching at Every Partial Stop Point  
  
🗓️ The pipeline has three natural checkpoint positions where partial progress can be lost if the process exits unexpectedly. Each is now cached durably.  
  
📁 The first checkpoint is the file scan. Once Gemini has analyzed a file for book mentions, the result is recorded permanently in the file's own frontmatter under the key book_mention_scanned. Any future run skips that file without a second Gemini call. This annotation is never reset: the design assumes one scan per file for the lifetime of the vault, with a version-two pass to be designed separately if ever needed.  
  
🔑 The second checkpoint is candidate discovery. When a new title is identified, it is written to the books index frontmatter as book_report_pending before any further API calls. The books index is not date-scoped, so this persists even if the task cannot complete until the next day. On any run, if a pending title is found and no book file exists yet, the task resumes directly from that title.  
  
🛒 The third checkpoint is the Amazon search. After the ASIN is extracted and the URL is validated, the ASIN is written to the books index as book_report_asin. If report generation fails, the next run reuses the cached ASIN and skips the Amazon search step entirely.  
  
### 📐 ASIN Extraction Safety  
  
🔒 The ASIN extraction function stops at the first non-alphanumeric character, then verifies the segment is exactly ten characters. The property-based roundtrip test confirms that building an affiliate URL from a valid ASIN and then extracting the ASIN from that URL always returns the original.  
  
🌐 After assembling the affiliate URL, the task fetches the page to confirm it exists. A confirmed 404 causes the candidate to be skipped immediately. Connection errors and transient server errors such as 5xx and 429 are retried up to three times with exponential back-off so that a momentary outage or rate-limit does not silently bypass validation. If the URL still cannot be confirmed after all retries the candidate is skipped. The task also checks whether the title appears anywhere in the full response body as a best-effort signal that the URL points to the correct book.  
  
## 🧪 Testing  
  
✅ The implementation adds tests across two modules covering the full pipeline.  
  
📋 The BookReport module tests cover title-to-kebab-case conversion with property tests for slug invariants, ASIN extraction with the roundtrip property, affiliate URL construction, frontmatter assembly including the emojified-title override, body building with and without affiliate links, the hasAutoGeneratedBookLink function (which is the page-evidence idempotency check), reflection section insertion before blog series sections and social sections, idempotency, and the auto-generated robot-emoji marker.  
  
📋 The BookReport.Gemini module tests cover the find-mentions prompt structure, JSON array parsing with code-fence stripping, the seven-section report prompt structure including the AI Summary and FAQ sections, and the Amazon search prompt.  
  
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
  
