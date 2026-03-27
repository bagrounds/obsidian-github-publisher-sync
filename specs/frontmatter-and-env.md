# 🔧 Infrastructure — Frontmatter, Environment, HTML, Timer, and Pipeline

## 🎯 Overview

📋 Shared infrastructure modules used across all automation tasks.
🧩 Provides YAML frontmatter parsing, environment configuration, HTML utilities, timing, and pipeline orchestration.

## 📦 Components

### 📄 Frontmatter (scripts/lib/frontmatter.ts)

- 🔍 parseFrontmatter extracts YAML key-value pairs from markdown content between triple-dash delimiters
- 📖 readReflection reads a daily reflection file and detects social media section presence
- 📝 readNote reads an arbitrary note file
- 🗺️ getReflectionPath constructs the file path for a dated reflection
- 🔧 Simple text-based parsing without external YAML library dependency

### 🌍 Environment (scripts/lib/env.ts)

- ✅ validateEnvironment validates and constructs configuration from environment variables
- 🚫 isPlatformDisabled checks if a platform is disabled via env var (true, 1, yes)
- 📅 getYesterdayDate returns yesterday's date in YYYY-MM-DD format
- 🔑 Requires GEMINI_API_KEY, OBSIDIAN_AUTH_TOKEN, OBSIDIAN_VAULT_NAME
- 🔧 Optionally loads Twitter, Bluesky, and Mastodon credentials

### 🏷️ HTML (scripts/lib/html.ts)

- 🔒 escapeHtml escapes ampersand, angle brackets, quotes, and single quotes
- 📝 textToHtml replaces newlines with br tags after escaping
- 📅 formatDisplayDate converts YYYY-MM-DD to human-readable format like March 10, 2026

### ⏱️ Timer (scripts/lib/timer.ts)

- 📊 PipelineTimer tracks multiple timed entries with start and end timestamps
- 🔧 timerStart, timerEnd, and timerTime control timer lifecycle
- 📈 printTimerSummary displays formatted timing with duration and percentage of total

### 🔄 Pipeline (scripts/lib/pipeline.ts)

- 📋 Pipeline data type represents a sequence of processing steps
- 🔧 runPipeline executes steps in sequence
- ➕ addStep adds a processing step to the pipeline

## 🧪 Testing

🔬 Tests cover frontmatter parsing, HTML escaping, display date formatting, environment validation, and platform disabled detection across multiple test suites.
