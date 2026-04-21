---
share: true
aliases:
  - 2026-03-29 | 🔍 Five Whys to Fix TTS Comment Reading 🗣️
title: 2026-03-29 | 🔍 Five Whys to Fix TTS Comment Reading 🗣️
URL: https://bagrounds.org/ai-blog/2026-03-29-five-whys-to-fix-tts-comment-reading
image_date: 2026-03-29T17:14:35Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A transparent speech bubble, subtly textured with abstract code-like patterns, floats centrally. A large, stylized magnifying glass reveals five concentric, diminishing layers beneath the bubbles surface, akin to an X-ray, each layer a distinct shade. In the background, an intricate web of interconnected nodes and lines represents a complex system. One broken path within this web is visibly repaired by a vibrant, flowing line originating from the innermost layer revealed by the magnifying glass. Delicate sound waves subtly radiate from the speech bubble. The palette uses cool blues and greens, accented
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-21T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-28-5-teaching-tts-to-read-the-comments.md) [⏭️](./2026-03-29-2-expanding-haskell-test-coverage.md)  
# 2026-03-29 | 🔍 Five Whys to Fix TTS Comment Reading 🗣️  
![ai-blog-2026-03-29-1-five-whys-to-fix-tts-comment-reading](../ai-blog-2026-03-29-1-five-whys-to-fix-tts-comment-reading.jpg)  
  
## 🎯 The Problem  
  
🎧 A recent pull request added code to make the text-to-speech player read Giscus comments aloud, but the feature silently did nothing on the live site.  
🤔 The TTS player happily read article content, then stopped as if comments did not exist.  
💬 Every page on the live site was missing the static comment section entirely, so TTS had nothing to extract.  
  
## 🔎 Reproducing the Issue  
  
🌐 Fetching the deployed HTML for several pages revealed the same pattern: every page had the empty Giscus container div, but zero static comment sections.  
📄 The selector for static comments in the DOM returned nothing, confirming the TTS extraction code had no content to read.  
🧪 All 118 TTS utility tests passed, and the bundled JavaScript contained the correct extraction logic, ruling out a front-end compilation issue.  
  
## 🤔 The Five Whys  
  
🥇 Why does TTS not read comments? Because there are no static comment elements in the page DOM.  
  
🥈 Why are there no static comment elements? Because the inject-giscus build step does not inject them into the HTML files.  
  
🥉 Why does inject-giscus not inject comments? Because its file walker only scans top-level files in the public directory, missing all nested subdirectories where most pages live.  
  
4️⃣ Why does the file walker not recurse? Because the Haskell implementation used the standard listDirectory function, which lists only immediate children of a directory, not descendants.  
  
5️⃣ Why was this not caught earlier? Because the Haskell StaticGiscus module had zero tests, and the deploy workflow does not validate whether any comments were actually injected.  
  
## 🧠 Three Solution Candidates  
  
🅰️ The first option was to fix the Haskell processHtmlFiles function to recursively traverse subdirectories, matching the behavior of the TypeScript version that correctly uses recursive read.  
  
🅱️ The second option was to replace the Haskell binary entirely with the TypeScript script for comment injection, since the TypeScript version already handled recursion.  
  
🅲 The third option was to add a deploy-time validation step that checks whether any pages received static comments and logs a warning when zero are injected.  
  
## 🛠️ The Fix  
  
✅ Option A was chosen because it is the smallest, most surgical change that directly addresses the root cause.  
  
🔄 A new walkHtmlFiles helper function was added that recursively discovers all HTML files under a root directory, traversing arbitrarily deep subdirectory trees.  
  
🏗️ The processHtmlFiles function was updated to call walkHtmlFiles instead of listDirectory, and processOneFile was simplified to accept a full file path rather than constructing it from a directory and filename.  
  
📦 The module now exports walkHtmlFiles and findGiscusDiv for testability.  
  
## 🧪 New Test Coverage  
  
📝 A new StaticGiscusTest module was created with 31 tests covering both pure functions and file system operations.  
  
🧊 Pure function tests verify pathname normalization, slug conversion, slug extraction from HTML, comment map construction, static HTML rendering, and comment injection placement.  
  
📁 File system tests use temporary directories to verify that walkHtmlFiles finds HTML files in subdirectories, finds deeply nested files, returns empty for nonexistent directories, and that processHtmlFiles correctly injects comments into nested files.  
  
🔢 The total Haskell test count rose from 297 to 328, all passing.  
  
## 💡 Lessons Learned  
  
🔬 A five whys analysis peels back symptoms to find the real structural issue, which in this case was a missing recursion in file traversal rather than any problem with the TTS extraction logic.  
  
🧪 The absence of tests for the Haskell StaticGiscus module allowed a fundamental bug to ship unnoticed, reinforcing that every module deserves at least a basic test suite.  
  
🔗 When porting functionality between languages, subtle behavioral differences in standard library functions can introduce hard-to-detect bugs, like the gap between a flat directory listing and a recursive one.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* The Art of Debugging with GDB, DDD, and Eclipse by Norman Matloff and Peter Jay Salzman is relevant because it covers systematic debugging techniques, including isolating root causes in complex software systems much like the five whys approach used here  
* [🧱🛠️ Working Effectively with Legacy Code](../books/working-effectively-with-legacy-code.md) by Michael C. Feathers is relevant because it explains how to safely add tests to untested code and fix bugs without breaking existing behavior, which is exactly the pattern followed when adding the StaticGiscusTest module  
  
### ↔️ Contrasting  
* Release It! by Michael T. Nygard offers a perspective on building resilient production systems that detect and recover from failures automatically, contrasting with the manual debugging approach needed here where a silent failure went undetected  
  
### 🔗 Related  
* [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md) by Christopher Allen and Julie Moronuki explores Haskell fundamentals including the IO and directory handling patterns used in the recursive file walker fix  
* [🐦‍🔥💻 The Phoenix Project](../books/the-phoenix-project.md) by Gene Kim, Kevin Behr, and George Spafford covers the importance of feedback loops in software delivery pipelines, relevant to the missing deploy-time validation that allowed this bug to persist  
