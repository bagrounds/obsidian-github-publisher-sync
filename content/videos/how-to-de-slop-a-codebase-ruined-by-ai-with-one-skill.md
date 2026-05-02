---
share: true
aliases:
  - 🤖🧹💻 How To De-Slop A Codebase Ruined By AI (with one skill)
title: 🤖🧹💻 How To De-Slop A Codebase Ruined By AI (with one skill)
URL: https://bagrounds.org/videos/how-to-de-slop-a-codebase-ruined-by-ai-with-one-skill
Author:
Platform:
Channel: Matt Pocock
tags:
youtube: https://youtu.be/3MP8D-mdheA
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-01T00:00:00Z
force_analyze_links: false
---
[Home](../index.md) > [Videos](./index.md)  
# 🤖🧹💻 How To De-Slop A Codebase Ruined By AI (with one skill)  
![How To De-Slop A Codebase Ruined By AI (with one skill)](https://youtu.be/3MP8D-mdheA)  
  
## 🤖 AI Summary  
* 📉 AI acceleration increases software entropy by generating sloppy code that degrades maintainability over time.  
* 🧩 Prioritize deep modules which hide significant internal complexity behind a simple and stable interface.  
* 🧱 Avoid shallow modules where the interface is as complex as the implementation they wrap.  
* 🧵 Identify seams at module boundaries to create ideal points for unit testing and dependency injection.  
* 🔌 Use adapters to satisfy interfaces allowing for interchangeable components like fake clocks or mock services.  
* 🏗️ Aim for high locality where related changes stay grouped together to reduce cognitive load.  
* 🚀 Seek high leverage by providing callers with maximum capability for every unit of interface learned.  
* 🧠 Act as a strategic programmer focusing on long term design while AI handles tactical execution.  
* 🛡️ Establish a testing harness around deep modules before attempting to refactor legacy systems.  
  
## 🤔 Evaluation  
* ⚖️ The advocacy for deep modules aligns with A Philosophy of Software Design by John Ousterhout from Stanford University.  
* 🧪 Contrast this with Clean Code principles by Robert Martin through Pearson Education which often favors smaller classes that some critics argue lead to shallow modules.  
* 🔄 Test Driven Development by Kent Beck through Addison Wesley Professional suggests interfaces emerge from tests rather than upfront architectural planning.  
* 🔍 Research the trade offs between modularity and premature abstraction to avoid unnecessary architectural overhead.  
  
## ❓ Frequently Asked Questions (FAQ)  
  
### 🧩 Q: What defines a deep module in software architecture?  
✅ A: A deep module provides powerful functionality through a simple interface while concealing complex internal logic from the rest of the system.  
  
### 📉 Q: How does AI impact software entropy?  
✅ A: AI tools speed up code production but often result in disorganized or redundant logic that increases the overall complexity and messiness of a codebase.  
  
### 🧵 Q: Why are seams important for legacy code refactoring?  
✅ A: Seams provide specific locations in the code where behavior can be isolated or swapped allowing developers to insert tests without modifying core logic.  
  
### 🧠 Q: What is the difference between tactical and strategic programming?  
✅ A: Tactical programming focuses on finishing tasks quickly while strategic programming prioritizes the long term design and health of the system.  
  
## 📚 Book Recommendations  
  
### ↔️ Similar  
* 📘 A Philosophy of Software Design by John Ousterhout explains the core concepts of deep and shallow modules to manage system complexity.  
* 📘 Working Effectively with Legacy Code by Michael Feathers provides practical techniques for identifying seams and adding tests to older systems.  
  
### 🆚 Contrasting  
* 📘 Clean Code A Handbook of Agile Software Craftsmanship by Robert C. Martin focuses on small functions and classes which can lead to a more fragmented and shallow architecture.  
* 📘 Refactoring Improving the Design of Existing Code by Martin Fowler emphasizes incremental changes to code structure rather than starting with high level architectural deep modules.  
  
### 🎨 Creatively Related  
* 📘 Thinking in Systems by Donella Meadows explores how feedback loops and boundaries in any system relate to the modularity found in software.  
* 📘 The Goal A Process of Ongoing Improvement by Eliyahu Goldratt introduces the theory of constraints which helps identify bottlenecks in development workflows similar to identifying messy code modules.