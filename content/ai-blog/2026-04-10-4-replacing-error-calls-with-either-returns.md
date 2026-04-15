---
share: true
aliases:
  - 2026-04-10 | 🛡️ Replacing Error Calls with Either Returns 🧱
title: 2026-04-10 | 🛡️ Replacing Error Calls with Either Returns 🧱
URL: https://bagrounds.org/ai-blog/2026-04-10-4-replacing-error-calls-with-either-returns
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-14T00:00:00Z
force_analyze_links: false
image_date: 2026-04-12T22:19:18Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A split-screen composition featuring a sharp contrast between two states. On the left, a chaotic, jagged pile of dark, crumbling stone blocks represents Error calls, with a faint, ominous red glow emanating from the cracks. On the right, a clean, symmetrical, and perfectly interlocking structure of smooth, light-colored blocks represents Either returns. A gentle, calming blue light illuminates the right side, highlighting the stability and seamless fit of the pieces. The transition between the two sides is a clean, vertical line, symbolizing the shift from fragile runtime crashes to robust, type-safe architectural design. The background is a soft, neutral gradient, keeping the focus entirely on the transformation of the structures.
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-10-3-testing-either-error-paths.md) [⏭️](./2026-04-10-5-separating-data-from-behavior-in-image-providers.md)  
# 2026-04-10 | 🛡️ Replacing Error Calls with Either Returns 🧱  
![ai-blog-2026-04-10-4-replacing-error-calls-with-either-returns](../ai-blog-2026-04-10-4-replacing-error-calls-with-either-returns.jpg)  
  
## 💥 The Problem with Partial Functions  
  
🎯 In Haskell, calling error is like pulling a pin on a grenade and handing it to the next person down the call chain.  
  
🧨 The function compiles just fine, but when it encounters unexpected data at runtime, the whole program crashes with no opportunity for recovery.  
  
🔍 Our codebase had a pattern that looked harmless on the surface: helper functions like validatedTitle, validatedUrl, and validatedRelativePath that wrapped smart constructors with error on the Left branch.  
  
🪤 These helpers appeared in four modules across the codebase: Frontmatter, SocialPosting, InternalLinking, and BlogSeries.  
  
😱 Every time a note had an empty title, a malformed URL, or an unexpected file path, the entire automation pipeline would crash instead of gracefully skipping the problematic entry.  
  
## 🔧 The Fix: Embrace the Either  
  
🧪 The smart constructors already returned Either Text DomainType, giving us structured error information for free.  
  
🗑️ We removed all the validatedTitle, validatedUrl, and validatedRelativePath wrappers that swallowed this structured information and replaced it with a runtime crash.  
  
### 📄 File-Parsing Functions  
  
🔗 For functions like readReflection, readNote, readContentNote, and readEntry that parse data from vault files, we adopted the Either monadic bind pattern.  
  
📝 Instead of constructing each field independently with error on failure, we chain the validations using do-notation in the Either monad. If the title validation fails, the whole chain short-circuits with a descriptive error message. If the title succeeds but the URL fails, we get the URL error instead.  
  
⚠️ When the Either chain produces a Left, the function logs a warning with the specific validation failure and returns Nothing, gracefully skipping the problematic note instead of crashing the program.  
  
### 🧭 Pushing Validation to Boundaries  
  
🏷️ The findLinkCandidates function previously accepted a Text parameter for the self-path and immediately called validatedRelativePath to compare it with ContentEntry records.  
  
📐 We changed the parameter type from Text to RelativePath, pushing the validation responsibility to the caller where error handling is more natural.  
  
🎯 This makes the function's contract explicit in its type signature: you must provide a valid RelativePath, and the compiler enforces this guarantee.  
  
### 📦 Propagating Errors Upward  
  
🔄 The buildBlogContext function previously crashed with error when given an unknown blog series ID.  
  
✅ We changed its return type from IO BlogContext to IO (Either Text BlogContext), propagating the lookupSeries error to the caller.  
  
🏗️ The caller in the imperative shell (RunScheduled) still uses error for now, since that module is scheduled for its own refactoring phase. But the library function itself is now safe and composable.  
  
## 🔍 The Empty-String Returns Investigation  
  
📋 The roadmap also called for reviewing silent empty-string returns throughout the codebase.  
  
🧐 After examining every instance of equals-empty-string patterns, we found that all cases fell into one of two categories.  
  
✅ First, identity-element behavior: functions like joinSlash, buildPostHistory, and buildCommentsSection that correctly return an empty string when given an empty list, just as zero is the identity for addition.  
  
✅ Second, safe default values: the safeIdx function returns an empty string for out-of-bounds indices, which correctly causes downstream pattern matches like isPrefixOf to reject the value.  
  
🎉 No actual silent failures were found, so no changes were needed for this item.  
  
## 📊 Results  
  
🧪 Fifteen new tests were added covering the error and failure paths, bringing the total from 1075 to 1090.  
  
🛡️ Seven tests in FrontmatterTest verify that readReflection and readNote return Nothing for empty titles, whitespace-only titles, and invalid URLs, while succeeding for valid data.  
  
🔗 Four tests in SocialPostingTest confirm that readContentNote handles empty paths, empty titles, and missing files gracefully.  
  
📖 Two tests in BlogSeriesTest verify that buildBlogContext returns Left for nonexistent series IDs.  
  
🧩 Two tests in InternalLinkingTest confirm the new RelativePath-typed self-exclusion in findLinkCandidates works correctly.  
  
## 🎓 Lessons Learned  
  
🚫 Never wrap a smart constructor with error. The pattern of either (error . T.unpack) id . mkFoo is a time bomb that passes the compiler but explodes at runtime.  
  
🔗 Use Either monadic bind to chain validations. The do-notation in Either gives clean, short-circuiting validation with descriptive error messages.  
  
🏷️ Push validation to function boundaries by accepting domain types. When a function takes Text only to validate it, change the parameter to the validated type and let the caller handle errors where context is richer.  
  
🤔 Prefer Maybe over Either when callers do not distinguish error reasons. File-parsing functions that already return Maybe for "file not found" can reuse the same Nothing path for validation failures.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md) by Christopher Allen and Julie Moronuki is relevant because it teaches the foundational type system concepts that make patterns like Either-based error handling and smart constructors natural and idiomatic.  
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it demonstrates how to use type systems to make illegal states unrepresentable, which is exactly the principle behind replacing runtime errors with compile-time guarantees.  
  
### ↔️ Contrasting  
* Release It! by Michael Nygard offers a contrasting perspective focused on runtime resilience patterns like circuit breakers and bulkheads, rather than compile-time safety, showing how systems can be made robust even when individual components fail.  
  
### 🔗 Related  
* Algebra of Programming by Richard Bird and Oege de Moor explores the mathematical foundations behind functional programming patterns like monadic bind and identity elements, providing deeper understanding of why Either forms a monad and empty strings serve as identities.  
