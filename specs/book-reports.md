# 📚 Book Report Auto-Generation

## 🎯 Overview

This spec describes the automated book report generation pipeline. The system performs a BFS scan of recent content to discover references to books that don't yet have a book page, searches Amazon for a product link, generates a book report using Gemini, creates the book file in the vault, and adds a wikilink to the current day's reflection.

## 🏗️ Architecture

The feature is implemented as a scheduled Haskell task (`book-reports`) that runs four times per day at 4 AM, 8 AM, 12 PM, and 4 PM Pacific time. Each run generates at most one new book report.

### 🔄 Data Flow

1. **Book Index** — Build an index of all existing book pages in `content/books/`
2. **BFS Scan** — Traverse content files (up to `maxFilesScanned = 5`) in BFS order starting from the most recently-linked content
3. **Mention Discovery** — Use Gemini to find plain-text book mentions in each file that are not already wrapped in `[[wikilinks]]`
4. **Deduplication** — Filter out any mentioned books that already have a page in the index (by normalized title comparison)
5. **Amazon Search** — Use Gemini with Google Search grounding to find the Amazon.com product URL; extract ASIN and construct affiliate URL
6. **Report Generation** — Use Gemini to generate a markdown book report following the standard template
7. **File Creation** — Write the book file to `content/books/<slug>.md`
8. **Reflection Linking** — Insert a wikilink to the new book under a `## [[/books/index|📚 Books]]` section in today's reflection

## ⚙️ Configuration

| 🏷️ Environment Variable | 📝 Description |
|---|---|
| `GEMINI_API_KEY` | Required. Gemini API key for all inference calls |
| `AMAZON_ASSOCIATE_TAG` | Optional. Amazon Associates tag (e.g. `mysite-20`). If absent, book pages are created without affiliate links |

## 📐 Schedule

Scheduled four times daily at 4 AM, 8 AM, 12 PM, and 4 PM Pacific time using `atOrAfter = False` (runs at the exact hour only, no catch-up).

## 📝 Book File Format

Each generated book file follows this structure:

```
---
share: true
aliases:
  - "<title>"
title: "<title>"
URL: https://bagrounds.org/books/<slug>
Author:
tags:
affiliate link: <affiliate-url>   (omitted if no associate tag)
---
[[index|🏡 Home]] > [[/books/index|📚 Books]]
# <title>
[🛒 <plain-title>. As an Amazon Associate I earn from qualifying purchases.](<affiliate-url>)

<generated book report>

## 💬 [Gemini](https://gemini.google.com) Prompt (<model>)
> <prompt text>
```

## 🔤 Slug Generation

Book title → kebab-case slug using the same rules as the Obsidian Templater:

1. Lowercase
2. Remove apostrophes
3. Replace non-alphanumeric character runs with a single hyphen
4. Trim leading and trailing hyphens

Example: `"The Hitchhiker's Guide to the Galaxy"` → `the-hitchhikers-guide-to-the-galaxy`

## 🛒 Amazon Affiliate Links

1. Gemini with Google Search grounding searches for the book's Amazon.com product page
2. ASIN is extracted from the `/dp/ASIN` URL path segment
3. Affiliate URL is constructed as `https://www.amazon.com/dp/<ASIN>?tag=<ASSOCIATE_TAG>`

If no Amazon URL is found, the task skips the book and tries the next candidate.

## 📓 Reflection Integration

A `## [[/books/index|📚 Books]]` section is inserted into today's reflection with a wikilink:

```
## [[/books/index|📚 Books]]
- [[books/<slug>|<title>]]
```

The section is inserted before any trailing social-embed sections (Updates, Changes, Twitter, Bluesky, Mastodon), or appended at the end if no such sections exist.

## 🧪 Testing

Pure function tests cover:

- `titleToKebabCase` — kebab-case conversion including property-based tests
- `extractAsin` — ASIN extraction from various Amazon URL formats
- `buildAffiliateUrl` — affiliate URL construction with roundtrip property test
- `buildBookFrontmatter` — YAML frontmatter assembly
- `buildBookBody` — body content with nav links, affiliate lines, report content, attribution
- `buildBookFileContent` — full file content including frontmatter and body
- `booksSectionHeading` — reflection section heading format
- `insertBookLink` — idempotency, new section creation, insertion before trailing sections
- Gemini prompt builders — `buildFindMentionsPrompt`, `buildReportPrompt`, `buildAmazonSearchPrompt`
- `parseMentionsList` — JSON array parsing including code fence handling

## 📂 Files

| 📄 File | 📝 Description |
|---|---|
| `haskell/src/Automation/BookReport.hs` | Core module: title-to-slug, ASIN extraction, affiliate URL, file assembly, reflection linking, orchestration |
| `haskell/src/Automation/BookReport/Gemini.hs` | Gemini prompts: book mention discovery, report generation, Amazon search |
| `haskell/test/Automation/BookReportTest.hs` | Unit and property tests for all pure functions |
| `haskell/test/Automation/BookReport/GeminiTest.hs` | Tests for prompt builders and response parsers |
