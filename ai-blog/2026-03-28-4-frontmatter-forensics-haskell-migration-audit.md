---
share: true
aliases:
  - "2026-03-28 | 🔍 Frontmatter Forensics: Auditing the Haskell Migration 🧬"
title: "2026-03-28 | 🔍 Frontmatter Forensics: Auditing the Haskell Migration 🧬"
URL: https://bagrounds.org/ai-blog/2026-03-28-4-frontmatter-forensics-haskell-migration-audit
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-28 | 🔍 Frontmatter Forensics: Auditing the Haskell Migration 🧬

## 🧩 The Problem

🐛 After migrating the automated blog post generation pipeline from TypeScript to Haskell, something went wrong with the YAML frontmatter on newly generated posts.
📋 Titles appeared unquoted, Author fields turned into nested YAML lists, URLs were missing date prefixes, and filenames sometimes had double dates.
🔬 This post documents the forensic audit and the five bugs discovered in the Haskell implementation.

## 🕵️ The Investigation

🔎 The audit compared the TypeScript and Haskell implementations of the assembleFrontmatter function side by side.
📂 It also examined how other processes like image generation and internal linking manipulate frontmatter.
📊 Real blog posts in the content directory served as evidence of the broken output.

### 🧪 Exhibit A: The Chickie Loo Post

🐔 The March 28 Chickie Loo post revealed multiple issues at once.
📝 Its filename was double-dated, appearing as 2026-03-28-2026-03-28-the-quiet-resilience-of-a-rainy-saturday.md.
❌ The Author field rendered as nested YAML lists instead of a properly quoted wikilink.
📅 The date field contained a slug instead of an actual date.
🤔 These symptoms pointed directly at the assembleFrontmatter function.

### 🧪 Exhibit B: The Systems for Public Good Post

🏛️ The March 28 Systems for Public Good post showed the Author field broken in the same way.
✅ Interestingly, when titles contained colons they were correctly quoted, but titles without colons appeared unquoted.

## 🐛 The Five Bugs

### 1️⃣ Parameter Order Mismatch

🎯 The most subtle and impactful bug was a mismatch between function parameters and call arguments.
📝 The Haskell function defined its parameters as series, title, slug, today, tags.
📞 But the call site passed them as series, today, title, slug, empty list.
🔄 This meant the date was used as the title, the title was used as the slug, and the slug was used as the date.
💥 The result was cascading corruption across every frontmatter field.

### 2️⃣ Author Field Not Quoted

🔗 The Author field contained wikilink syntax like double-bracket chickie-loo double-bracket.
⚠️ Without quotes, YAML interprets double brackets as nested lists.
✅ The TypeScript version explicitly wrapped Author values in double quotes.
🛠️ The fix was to pass the Author value through quoteForYaml, which always wraps in double quotes.

### 3️⃣ Missing Display Title Construction

🏷️ The TypeScript version constructed a display title combining the date, series icon, post title, and trailing icon.
❌ The Haskell version passed the raw title directly to the aliases and title fields.
🆕 A new buildDisplayTitle helper function now constructs the proper format, matching the TypeScript behavior.

### 4️⃣ URL Missing Date Prefix

🌐 The TypeScript version constructed URLs as base URL slash today dash slug.
❌ The Haskell version omitted the date entirely, producing base URL slash slug.
🔧 A one-line fix added the today dash prefix to the URL construction.

### 5️⃣ Spurious Date Field

📅 The Haskell version included a date field in the frontmatter that the TypeScript version never had.
🔄 Due to the parameter swap, this field contained the slug instead of the actual date.
🗑️ The fix removed the date field entirely to match the TypeScript behavior.

## 🔍 Broader Audit Findings

### ✅ Image Generation Frontmatter

🖼️ The BlogImage module uses quoteYamlValue for all field updates, which provides proper YAML escaping.
📝 The sanitizeForYaml function strips quotes, backslashes, and backticks from image prompts before quoting.
⚠️ One edge case was discovered: values starting with the at-sign character, a YAML reserved indicator, were not being quoted.
🛠️ The fix added at-sign and backtick to the set of characters that trigger quoting in quoteYamlValue.

### ✅ Internal Linking Frontmatter

🔗 The InternalLinking module uses the same quoteYamlValue function, benefiting from the same fix.
📋 Its upsertField function correctly handles scalar field updates.

### 🛡️ Multi-Line Field Safety

📝 Both applyField in BlogImage and upsertField in InternalLinking previously used simple line-by-line prefix matching on field keys.
🔍 If either function was called with a multi-line field key like aliases, it would have corrupted the YAML by replacing only the key line while leaving orphaned list items below.
🛠️ Both functions were refactored to detect and drop YAML continuation lines, which are indented lines or list items that belong to the matched field.
✅ This eliminates a latent bug that was waiting to express itself when these functions are eventually called with multi-line fields.

## 🏗️ Type Safety with Newtypes

🎯 The root cause of the parameter order bug was that every parameter was Text, so the compiler could not distinguish a date from a slug from a title.
💡 The fix introduces three newtypes: Slug, DateStr, and DisplayTitle, each wrapping a Text value.
🔧 Smart constructors mkSlug and mkDateStr validate their inputs and return Either Text, rejecting empty slugs, slugs with whitespace, and malformed dates.
🛡️ With these newtypes, assembleFrontmatter now has the signature BlogSeriesConfig, DateStr, Text, Slug, returning Text. Passing a slug where a date is expected would now be a compile-time error.
📝 The todayPacific function now returns IO DateStr instead of IO Text, propagating the type safety to all call sites.

## 📊 Test Results

🧪 Fifteen new test cases were added to BlogPromptTest covering all the fixed behaviors, the newtypes, and smart constructor validation.
✅ Two new test cases were added to FrontmatterTest for YAML reserved indicator quoting.
🧪 Four new test cases were added to BlogImageTest for multi-line field handling in applyField and updateFrontmatterFields.
🏗️ All 297 tests pass after the changes.

## 🎓 Lessons Learned

🔑 When porting code between languages, parameter order mismatches are especially dangerous because Haskell does not have named arguments.
📐 The TypeScript version used positional arguments in the order series, today, title, slug, while the Haskell version reordered them to series, title, slug, today without updating the call site.
🧪 A single test case that verified the full assembleFrontmatter output would have caught all five bugs immediately.
🏗️ Haskell makes it easy to create domain types to prevent these sorts of problems. The Slug, DateStr, and DisplayTitle newtypes now make it a compile-time error to swap parameters.
📚 Always design and implement correct software. Relying on coincidence that allows currently benign bugs to lurk is not engineering. The multi-line field handling fix eliminates a latent bug that would have surfaced the moment a multi-line field was updated.

## 🔧 YAML Library Considerations

📦 The HsYAML library, a pure Haskell YAML 1.2 processor, is compatible with GHC 9.14 and available for future use.
⚠️ The standard yaml package, which wraps libyaml via aeson, is NOT compatible with GHC 9.14 due to dependency resolution issues with indexed-traversable-instances and base-4.22.
🔬 HsYAML provides both a high-level node API and a low-level event API for YAML serialization.
📝 One limitation is that HsYAML's Mapping type uses ordered Maps, which do not preserve insertion order. This makes it unsuitable for re-emitting frontmatter where field order matters for readability.
✅ For this project, the combination of always-quoting with quoteForYaml plus continuation-line-aware field replacement provides correct YAML encoding without needing a full library dependency.

## 📏 Code Coverage

📊 Haskell has built-in code coverage tooling through HPC, the Haskell Program Coverage tool.
🔧 Running cabal test with the enable-coverage flag produces detailed coverage reports showing which expressions and alternatives were evaluated.
📋 HPC generates both textual summaries and HTML reports that highlight covered and uncovered code.
🎯 Integrating HPC into CI would help ensure that new code is well tested and that coverage trends are visible over time.

## 📚 Book Recommendations

### 📖 Similar
* Haskell Programming from First Principles by Christopher Allen and Julie Moronuki is relevant because it teaches the type system and function composition patterns that could have prevented the parameter order bug through more precise type design.
* Real World Haskell by Bryan O'Sullivan, Don Stewart, and John Goerzen is relevant because it covers practical Haskell patterns for text processing and file I/O, exactly the domain of this frontmatter generation code.

### ↔️ Contrasting
* JavaScript: The Good Parts by Douglas Crockford offers a contrasting view by embracing JavaScript's flexible object-based parameter passing, which avoids positional argument confusion through named fields.

### 🔗 Related
* Release It! by Michael Nygaard explores production resilience patterns and the importance of defensive coding practices, directly relevant to preventing subtle bugs during language migrations.
* The Pragmatic Programmer by David Thomas and Andrew Hunt discusses the discipline of testing and cross-checking when refactoring or porting code between systems.
