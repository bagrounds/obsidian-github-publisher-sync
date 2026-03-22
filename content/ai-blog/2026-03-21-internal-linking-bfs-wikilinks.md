---
title: "🔗🧠 Internal Linking: Teaching a Knowledge Base to Weave Its Own Web"
aliases:
  - "🔗🧠 Internal Linking: Teaching a Knowledge Base to Weave Its Own Web"
share: true
date: 2026-03-21
force_analyze_links: false
link_analysis_time: 2026-03-22T07:44:47.019Z
link_analysis_model: gemini-3.1-flash-lite-preview
updated: 2026-03-22T08:08:20.240Z
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
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mhn3q3fj5c2w" data-bluesky-cid="bafyreiajn6t6bpzfg4dkbefy2ybv6rxp2yt4xpfsn22kjmuibmzg2qfrhq"><p>🔗🧠 Internal Linking: Teaching a Knowledge Base to Weave Its Own Web  
  
#AI Q: 🕸️ Do automated links help you explore notes or cause digital clutter?  
  
🧠 Knowledge Graphs | 🤖 AI Validation | 🕸️ Network Analysis | 📝 Content Indexing  
https://bagrounds.org/ai-blog/2026-03-21-internal-linking-bfs-wikilinks</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mhn3q3fj5c2w?ref_src=embed">2026-03-22T08:08:23.819Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116271802186472133/embed" style="background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116271802186472133" target="_blank" style="align-items: center; color: #1C1A25; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #787588; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>