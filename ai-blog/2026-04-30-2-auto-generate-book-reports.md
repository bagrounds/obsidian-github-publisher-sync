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

📚 Today's work adds a new scheduled automation task that discovers book references in your personal knowledge base, finds the corresponding Amazon product pages, generates a full book report using Gemini, and wires everything back into your daily reflection.

🤖 The entire pipeline is driven by Gemini, using both standard inference for report generation and Google Search grounding to find Amazon product pages. 

🔄 The task runs four times per day at 4 AM, 8 AM, 12 PM, and 4 PM Pacific time, generating at most one new book report per run.

## 🧩 How It Works

### 🔍 Step One: Discovering Missing Books

🔎 The first step is finding book titles mentioned in your content that don't yet have dedicated book pages.

🌐 A BFS traversal walks the vault's content graph starting from the most recently linked notes. For each file visited, we ask Gemini to identify plain-text book mentions — titles that appear in the body but are not already wrapped in double-bracket wikilinks.

🗂️ We then cross-reference those mentions against the existing book index, filtering out titles that already have a page. The comparison is case-insensitive and emoji-stripped so a reference to "Sapiens" won't miss the existing page titled "🧬 Sapiens: A Brief History of Humankind."

### 🛒 Step Two: Finding the Amazon Product URL

🔗 For each book candidate we find, we send a Gemini request with Google Search grounding asking for the Amazon.com product page URL for the most popular print version of that book.

🔁 The response is inspected at two levels: first, the grounding source URLs are filtered for Amazon product pages containing the slash-dp-slash ASIN pattern; second, if no grounding source qualifies, the raw response text is checked for a valid Amazon URL.

📦 Once we have an Amazon URL, we extract the ASIN from the slash-dp-slash path segment. The ASIN extraction is careful to verify the segment is exactly ten alphanumeric characters, rejecting longer slugs that happen to start with ten valid characters.

💰 The affiliate URL is then assembled as the Amazon dp path followed by the tag query parameter using your Amazon Associates ID from the environment variable called AMAZON_ASSOCIATE_TAG. If the variable is not set, the book page is created without an affiliate link rather than failing the run.

### 📝 Step Three: Generating the Book Report

✍️ With the title and affiliate link in hand, we invoke Gemini once more to write the actual book report. The prompt asks for a markdown-formatted report starting headings at level two, followed by similar, contrasting, and creatively related book recommendations. The prompt also instructs Gemini to structure the report with section headings and bulleted lists and never to quote or italicize titles.

🔖 The generated content is assembled into a full vault note with YAML frontmatter including the share flag, title, aliases, URL, Author field, tags field, and affiliate link. The body opens with a breadcrumb navigation link, the level-one heading, a callout line linking to the product with the Amazon Associate disclosure, the report body, and a Gemini prompt attribution footer.

### 📓 Step Four: Linking in the Daily Reflection

📅 Once the book file is written to the books directory, the system opens today's reflection and inserts a wikilink under a new or existing Books section that links to the books index. 

⬆️ The section is inserted before any trailing social embed sections such as Updates, Changes, Twitter, Bluesky, or Mastodon so it appears in a natural reading position. If none of those sections exist, it is appended at the end. The function is idempotent, so running the task a second time does not duplicate the link.

## 🏗️ Architecture Decisions

### 🧊 Pure Core, IO at the Edges

🔬 All slug generation, ASIN extraction, affiliate URL construction, frontmatter assembly, body building, and reflection insertion are pure functions with no IO. The IO boundary is pushed to the top-level run function which handles file reads, Gemini calls, and writes.

🧪 This design makes every component trivially testable with unit tests and property-based tests. The property tests verify, for example, that the kebab-case slug function never produces consecutive hyphens, never leaves leading or trailing hyphens, and only outputs lowercase alphanumeric characters and hyphens.

### 📐 ASIN Extraction Safety

🔒 The ASIN extraction function stops at the first character that is not alphanumeric, then checks that the resulting segment is exactly ten characters. An earlier version used T.take ten which silently accepted the first ten characters of a longer slug. The property-based roundtrip test revealed this: building an affiliate URL from a valid ASIN, then extracting the ASIN from that URL, must return the original ASIN — and it now does.

### 📅 Scheduling Strategy

⏰ Book report generation is scheduled four times per day rather than every hour. Each run can require up to five Gemini calls for file scanning, one call for Amazon search, and one call for report generation. Running hourly would exhaust the daily free-tier quota before other tasks could run.

🛑 The task uses exact-hour matching rather than at-or-after scheduling because idempotency is harder to guarantee here: we don't want to regenerate a book if one was already created earlier in the day. Since each run scans BFS-ordered content and generates one new book, subsequent runs will naturally find the same content already indexed and move on to new candidates.

### 🔄 Graceful Degradation

🛡️ The pipeline tries multiple candidates before giving up. If Amazon search fails for the first book title, the system tries the next candidate rather than aborting the run. If no Amazon URL is found for any candidate, the run exits cleanly with a skip count logged.

## 🧪 Testing

✅ The implementation adds 77 new tests across two modules.

📋 The BookReport module tests cover title-to-kebab-case conversion with property tests, ASIN extraction from various URL patterns including the roundtrip property, affiliate URL construction, frontmatter and body assembly, reflection section insertion with idempotency verification, and the books section heading format.

📋 The BookReport.Gemini module tests cover the prompt builders for mention discovery, report generation, and Amazon search, as well as the JSON array parser for Gemini responses including code fence stripping and handling of malformed output.

## 📚 Book Recommendations

### 📖 Similar

* The Personal MBA by Josh Kaufman is relevant because it is a self-education framework for learning from books, which resonates with the idea of building a personal library of book reports to capture knowledge.

* How to Take Smart Notes by Sönke Ahrens is relevant because it describes the Zettelkasten method of building a knowledge graph from reading notes, which is exactly the kind of personal knowledge base this system is designed to enrich.

* Moonwalking with Einstein by Joshua Foer is relevant because it explores techniques for remembering information from books and documents, a natural complement to automatically generating and storing book reports.

### ↔️ Contrasting

* Walden by Henry David Thoreau offers a view that the best learning comes from direct experience with nature and minimal possessions rather than from accumulating and cataloging books.

### 🔗 Related

* The Information by James Gleick explores the history of how humans have catalogued, stored, and retrieved knowledge across centuries of technological change, from clay tablets to digital archives.

* Continuous Delivery by Jez Humble and David Farley covers the engineering practices behind automating software pipelines, directly relevant to the CI and scheduled-task architecture that powers this book report generator.
