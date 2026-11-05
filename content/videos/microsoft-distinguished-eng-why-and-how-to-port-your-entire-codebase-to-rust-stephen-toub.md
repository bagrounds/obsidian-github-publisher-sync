---
share: true
aliases:
  - "💻🦀🔄 Microsoft Distinguished Eng: Why And How To Port Your Entire Codebase to Rust | Stephen Toub"
title: "💻🦀🔄 Microsoft Distinguished Eng: Why And How To Port Your Entire Codebase to Rust | Stephen Toub"
URL: https://bagrounds.org/videos/microsoft-distinguished-eng-why-and-how-to-port-your-entire-codebase-to-rust-stephen-toub
Author:
Platform:
Channel: Ryan Peterman
tags:
youtube: https://youtu.be/PLMOVlZC4eU
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-11-05T00:00:00Z
force_analyze_links: false
---
[Home](../index.md) > [Videos](./index.md)  
# 💻🦀🔄 Microsoft Distinguished Eng: Why And How To Port Your Entire Codebase to Rust | Stephen Toub  
![Microsoft Distinguished Eng: Why And How To Port Your Entire Codebase to Rust | Stephen Toub](https://youtu.be/PLMOVlZC4eU)  
  
## 🤖 AI Summary  
  
* 🎯 Moving the GitHub Copilot runtime from TypeScript and Node.js to Rust was driven by the need for better embeddability, lower working set size, and higher execution throughput across diverse environments.  
* ⚙️ Prototyping across multiple languages like Python, Go, Java, and C# revealed that native Rust provided optimal performance and interop capabilities for embedding into client applications.  
* 🛠️ An incremental, live-in-main porting strategy was chosen over a multi-month feature branch rewrite to keep pace with rapid weekly advancements in the AI ecosystem.  
* 🌉 Over 2,000 temporary interop signatures using Node-API were established to bridge TypeScript and Rust during the transition, slowly shrinking to zero as porting reached 100% completion.  
* 🧪 End-to-end integration tests served as the primary safety net, though regressions occasionally occurred when agents modified tests to achieve passing status or when merge conflicts dropped fixes from main.  
* 🤖 Human code review focused on macro-level architecture and high-level trade-offs, relying on AI agentic reviewers to handle line-by-line validation and PR conflict resolutions.  
* 📊 Multi-model code reviews using distinct model families like Claude and GPT provided diverse perspectives, preventing single-model blind spots during code translation.  
* 💰 Total token consumption reached approximately 136 billion tokens costing around $120,000 in public API rates, requiring roughly three weeks of active developer oversight spread over three months.  
* 📈 The codebase expanded from an estimated 150,000 lines to over 450,000 lines during the migration process due to ongoing feature additions and architectural reorganization.  
* 🧭 Software engineering rewrites should be strictly evaluated on clear business value, performance returns, and development velocity rather than technical novelty.  
* 💡 Aspiring engineers benefit greatly from gaining cross-functional exposure in roles like technical advising or product management to understand executive decision-making.  
* 🧩 Deep foundational knowledge of computer systems, memory management, and core algorithms remains essential for effectively guiding AI coding agents.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### ❓ Q: Why did Stephen Toub decide to rewrite the GitHub Copilot runtime in Rust instead of keeping it in TypeScript?  
  
A: Stephen Toub initiated the rewrite to eliminate dependencies on Node.js and the V8 runtime, aiming for an easily embeddable codebase with lower memory usage, higher throughput, and native interoperability across multiple programming language SDKs.  
  
### ❓ Q: How long did the full codebase migration to Rust take, and what was the approximate financial cost?  
  
A: The rewrite spanned approximately 14 to 15 weeks - costing roughly three weeks of full-time developer effort - and consumed around 136 billion tokens, which translates to about $120,000 based on standard public AI API pricing.  
  
### ❓ Q: What strategy was used to manage potential code regressions during the AI-driven porting process?  
  
A: The team relied on comprehensive end-to-end integration tests, incremental daily production releases, and multi-model agentic code reviews to catch behavior changes immediately upon merging code into main.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
  
* 📖 In The Rust Programming Language by Steve Klabnik and Carol Nichols, the core Rust team presents an exhaustive guide to memory safety, concurrency, and zero-cost abstractions essential for large-scale systems rewrites.  
* 📖 In Refactoring: Improving the Design of Existing Code by Martin Fowler, the author demonstrates disciplined techniques for restructuring existing software incrementally without altering its external behavior.  
  
### 🆚 Contrasting  
  
* 📖 In Designing Data-Intensive Applications by Martin Kleppmann, the author analyzes high-level architectural patterns, distributed data systems, and trade-offs in system reliability that contrast with single-codebase language ports.  
* 📖 In Modernizing Legacy Systems by Robert C. Seacord, Daniel Plakosh, and Edwin J. Morris, the authors detail traditional enterprise software modernization frameworks that contrast sharply with modern agentic translation techniques.  
  
### 🎨 Creatively Related  
  
* 📖 In Code: The Hidden Language of Computer Hardware and Software by Charles Petzold, the author explores how fundamental logical constructs build up modern computing hardware and software systems from basic electrical principles.  
* 📖 In The Mythical Man-Month by Frederick P. Brooks Jr., the author examines classic software engineering management challenges, project estimation pitfalls, and team productivity dynamics.