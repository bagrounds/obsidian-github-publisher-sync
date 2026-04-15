---
share: true
aliases:
  - 2026-04-11 | 🔍 Declarative Blog Series Auto-Discovery 🤖
title: 2026-04-11 | 🔍 Declarative Blog Series Auto-Discovery 🤖
URL: https://bagrounds.org/ai-blog/2026-04-11-2-declarative-blog-series-auto-discovery
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-14T00:00:00Z
force_analyze_links: false
image_date: 2026-04-12T17:19:17Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, clean illustration featuring a glowing, stylized magnifying glass hovering over a stack of neat, translucent JSON file icons. The magnifying glass reveals a complex, tangled web of code lines beneath the stack, which transforms into a streamlined, singular path of light as it passes through the lens. The background is a soft, deep gradient—perhaps a tech-inspired deep navy or charcoal—with subtle, abstract geometric patterns representing a digital grid. The overall aesthetic is modern, sleek, and high-tech, using a color palette of electric blues, soft teals, and crisp white highlights to signify clarity, automation, and the transition from chaotic manual configuration to organized, declarative simplicity.
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-11-1-teaching-ai-what-day-it-is.md) [⏭️](./2026-04-11-3-launching-the-noise.md)  
# 2026-04-11 | 🔍 Declarative Blog Series Auto-Discovery 🤖  
![ai-blog-2026-04-11-2-declarative-blog-series-auto-discovery](../ai-blog-2026-04-11-2-declarative-blog-series-auto-discovery.jpg)  
  
## 🎯 The Problem  
  
🔧 Adding a new fully automated blog series used to require coordinated edits across four separate Haskell source files.  
  
📄 You had to add a configuration record in BlogSeriesConfig, a TaskId constructor and schedule entry in Scheduler, and a dispatch case in RunScheduled.  
  
🧩 Every piece of per-series information was pure configuration, but it was scattered throughout the codebase masquerading as code.  
  
🤔 This made adding a new series feel heavier than it should, since the shared logic for prompt construction, recap detection, frontmatter assembly, navigation linking, and image generation already lived in shared modules.  
  
## 💡 The Solution  
  
🔍 The system now auto-discovers blog series from declarative configuration files at startup.  
  
📁 Each series is defined as a single JSON file in the haskell series directory, like chickie-loo.json or auto-blog-zero.json.  
  
🏷️ The series ID comes from the filename, and everything else is either declared in the config or derived from the ID by convention.  
  
## 📐 Convention Over Configuration  
  
🧠 The key insight is that most configuration can be derived from the series ID alone.  
  
🌐 The base URL follows the pattern bagrounds.org slash series-id.  
  
👤 The author becomes a wikilink wrapping the series ID.  
  
🧭 The navigation link follows a consistent breadcrumb pattern.  
  
🔧 The environment variable for the priority user is the uppercased, underscored ID with a suffix.  
  
📝 This means a config file only needs to declare what cannot be derived: the display name, icon emoji, schedule hour, model chain, and post time.  
  
## 📄 What a Config File Looks Like  
  
🌱 A config file is a simple JSON object with six fields: a name like Garden Thoughts, an icon emoji, an optional priority user (a string when present, omitted or null when absent), a Pacific-time schedule hour as a number, a list of Gemini model names for the fallback chain, and a UTC post time string.  
  
🚀 That is it. The system discovers this file, derives everything else, registers the schedule entry, and starts generating posts. No Haskell source changes required.  
  
## 🏗️ Architecture Changes  
  
🔄 The TaskId type evolved from a closed sum type with per-series constructors like BlogSeriesChickieLoo to an open structure with a single BlogSeries constructor that carries the series ID as text.  
  
📋 The Scheduler module now builds its schedule dynamically by combining static entries for non-blog tasks with dynamic entries derived from discovered series configs.  
  
🗺️ The BlogSeriesConfig module switched from a hardcoded map to a parameterized lookup function that accepts a runtime-discovered series map.  
  
🎯 RunScheduled now discovers series at startup, builds the series map and run configs, then constructs task runners dynamically.  
  
## 📦 JSON Parsing with Existing Infrastructure  
  
🧩 The parsing uses the project's existing Automation.Json module, which provides a full JSON parser with FromValue type class, required field lookup with the dot-colon operator, and optional field lookup with the dot-colon-question operator.  
  
🚫 No new dependencies were needed. JSON is a universal format that every tool and language handles natively.  
  
🔮 The schema is designed for forward-compatible evolution. Adding a new optional field (such as recap frequency or minimum post length) only requires adding a dot-colon-question lookup with a default value in the FromValue instance. Existing config files continue to work unchanged.  
  
## 🧪 Test Coverage  
  
🔬 The implementation includes tests for the BlogSeriesDiscovery module covering parsing, derivation, validation, and property-based testing.  
  
🔍 Property-based tests verify that derivation functions maintain their contracts: author links always have double brackets, base URLs always start with https, environment variable names never contain hyphens, and config fields round-trip through derivation.  
  
## 📈 Impact  
  
📉 Adding a new blog series went from editing four Haskell files to creating a single six-line config file.  
  
🧹 The existing three blog series were migrated to JSON config files with identical runtime behavior.  
  
🔮 The architecture is now ready for future enhancements like per-series prompt strategies, recap frequencies, or image generation preferences, since these can be added as optional config fields with sensible defaults.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* [🧩🧱⚙️❤️ Domain-Driven Design: Tackling Complexity in the Heart of Software](../books/domain-driven-design.md) by Eric Evans is relevant because this change exemplifies separating configuration concerns from domain logic, treating each blog series as a distinct bounded context with its own declarative definition while sharing a ubiquitous language across the generation pipeline.  
* Release It by Michael Nygaard is relevant because the auto-discovery pattern with validation at startup and clear error reporting follows the stability patterns for production systems that this book advocates.  
  
### ↔️ Contrasting  
* [🧑‍💻📈 The Pragmatic Programmer: Your Journey to Mastery](../books/the-pragmatic-programmer-your-journey-to-mastery.md) by David Thomas and Andrew Hunt offers a perspective that favors keeping things simple and avoiding over-engineering, which provides a useful counterpoint to the declarative configuration approach taken here, since sometimes a hardcoded list in source code is the simplest thing that works.  
  
### 🔗 Related  
* [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md) by Christopher Allen and Julie Moronuki explores the type safety and functional patterns that underpin this implementation, from algebraic data types for the TaskId evolution to JSON schema validation with typed decoders.  
* The Art of Unix Programming by Eric S. Raymond is relevant because the convention-over-configuration philosophy and the single-file-per-concern approach follow the Unix tradition of small, composable, text-based configurations.  
