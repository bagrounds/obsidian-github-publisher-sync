---
title: "🔗🧠 Internal Linking: Teaching a Knowledge Base to Weave Its Own Web"
aliases:
  - "🔗🧠 Internal Linking: Teaching a Knowledge Base to Weave Its Own Web"
share: true
date: 2026-03-21
force_analyze_links: false
link_analysis_time: 2026-03-22T07:44:47.019Z
link_analysis_model: gemini-3.1-flash-lite-preview
---
[Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-20-building-valence-game.md) [⏭️](./2026-03-21-book-only-internal-linking.md)  
# 🔗🧠 Internal Linking: Teaching a Knowledge Base to Weave Its Own Web  
  
## 🎯 The Problem  
  
🤔 Imagine you have a personal knowledge base with thousands of notes — book reports, topic summaries, software docs, people profiles — and your daily reflections reference these concepts constantly.  
  
📝 Sometimes you mention "Thinking, Fast and Slow" in a book review, but forget to link it to your actual book report page.  
  
🕸️ These missed connections mean readers (and your future self) lose the opportunity to discover related content through the natural web of your writing.  
  
## 🏗️ The Architecture  
  
🎨 We designed a **hybrid approach** combining deterministic text matching with AI validation:  
  
| 🔧 Phase | 📋 Description | 🎯 Goal |  
|-----------|-----------------|---------|  
| 📇 Index Building | 🔍 Scan all content directories for pages with titles | 📊 Build the knowledge graph vocabulary |  
| 🌊 BFS Traversal | 🚶 Walk the link graph from the most recent reflection | 🗺️ Prioritize recently-relevant content |  
| 🎭 Masking | 🛡️ Replace protected regions (frontmatter, code, existing links, headings) with spaces | 🚫 Prevent false matches in structured content |  
| 🔎 Candidate Discovery | ✨ Word-boundary regex matching of plain titles against masked content | 📋 Find potential link insertion points |  
| 🤖 AI Validation | 🧪 Gemini reviews each candidate in context | ✅ Ensure every link is correct |  
| 🔗 Replacement | 📝 Insert wikilinks with emoji-rich aliases | 🎀 Maintain the knowledge base aesthetic |  
  
## 🧩 Key Design Decisions  
  
### 🛡️ Correctness Over Coverage  
  
🏆 The most important principle: **it's better to miss link opportunities than to insert broken or nonsensical links.**  
  
🔒 Every safeguard serves this principle:  
  
- 📏 Minimum title length of 8 characters filters out short false positives  
- 🔤 Word boundary matching prevents partial title matches  
- 🎭 Protected region masking prevents matches inside existing links, code blocks, headings, and frontmatter  
- 📖 Only first match per target per file (conservative linking)  
- 🤖 Gemini validates every candidate before insertion  
- ❌ If Gemini fails or errors, the entire file is skipped (no unvalidated changes)  
  
### 🌊 BFS Strategy  
  
🧭 Starting from the most recent daily reflection and following links breadth-first means:  
  
- 📅 The freshest content gets processed first  
- 🔗 Content reachable from reflections (the core of the knowledge graph) is prioritized  
- 🌐 The entire connected component is eventually reachable through the reflection doubly-linked list  
  
### 🤖 AI as Validator, Not Discoverer  
  
🧪 Gemini doesn't search for links — it only validates candidates found deterministically.  
  
💡 This gives us:  
  
- 🎯 Precise control over what gets proposed (no hallucinated links)  
- ⚡ Efficient API usage (small prompts with just the candidates + context)  
- 🔄 Reproducible behavior (deterministic discovery, AI only says yes/no)  
  
### 🔍 Single-Word Title Safety  
  
⚠️ Without AI validation, single-word titles like "Engineering" or "Philosophy" match too broadly.  
  
🛡️ Solution: when running without Gemini, only multi-word titles are eligible for matching.  
  
📊 With Gemini, even single-word matches are considered — the AI validates whether "engineering" in "biological engineering" actually refers to the Engineering topic page (it doesn't).  
  
## 🔧 The Implementation  
  
### 📇 Content Index  
  
🏗️ The index scans 10 content directories (books, articles, topics, software, people, products, games, videos, presentations, tools) and extracts:  
  
- 📁 Relative file path  
- 🏷️ Full emoji title from frontmatter  
- 📝 Plain title with emojis stripped  
  
### 🎭 Protected Region Masking  
  
🛡️ A clever technique: replace protected regions with equal-length space strings.  
  
✨ This preserves character positions so that match indices map directly back to the original content — no complex offset tracking needed.  
  
### 📝 Wikilink Format  
  
🔗 Links use the Obsidian wikilink format with path aliases:  
  
```  
[[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]]  
```  
  
🎀 The emoji-rich alias ensures the link displays beautifully in both Obsidian and the published site.  
  
## ⚙️ The Workflow  
  
🕐 The GitHub Action runs daily at approximately 11:30 PM Pacific time.  
  
🎛️ It's also manually triggerable with configurable parameters:  
  
- 📊 `max_files` — Maximum number of files to process (default: 10)  
- 🔍 `dry_run` — Preview mode that logs candidates without writing changes  
  
🔄 After making changes, modified files are synced to the Obsidian vault via the headless sync mechanism.  
  
## 📊 Results  
  
🧪 Running a dry-run across 30 files found candidates like:  
  
- ✅ "Large Language Models" → `topics/large-language-models.md`  
- ✅ "Jonathan Haidt" → `people/jonathan-haidt.md`  
- ✅ "Cal Newport" → `people/cal-newport.md`  
- ✅ "software engineering" → `topics/software-engineering.md`  
- ✅ "Deep Learning" → `books/deep-learning.md`  
  
🎯 All high-confidence matches that would enrich the knowledge graph.  
  
## 🧪 Testing  
  
📊 89 new tests across 19 test suites covering:  
  
- 😀 Emoji stripping (ZWJ sequences, skin tones, flags)  
- 🔤 Regex escaping  
- 🔗 Wikilink formatting  
- 📇 Content index building  
- 🌊 BFS traversal  
- 🎭 Protected region masking  
- 🔎 Candidate discovery with overlap prevention  
- 📝 Replacement application with position preservation  
- 🤖 AI validation prompt building  
- 🔒 Single-word title safety filtering  
  
## 🌟 What's Next  
  
🚀 Potential enhancements for future iterations:  
  
- 📈 Fuzzy matching for titles that don't appear verbatim  
- 🔄 Bidirectional link detection (if A mentions B, should B link to A?)  
- 📊 Link density analysis to avoid over-linking  
- 🧪 A/B testing of link insertion strategies  
