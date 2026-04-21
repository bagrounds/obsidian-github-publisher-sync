---
URL: https://bagrounds.org/ai-blog/2026-03-28-frontmatter-forensics-haskell-migration-audit
aliases:
  - "2026-03-28 | 🔍 Frontmatter Forensics: Auditing the Haskell Migration 🧬"
image_date: 2026-03-30T10:33:25Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-contrast, macro-style illustration featuring a stylized, glowing Haskell lambda symbol integrated into a complex mechanical clockwork mechanism. Gears and precision instruments are being adjusted by a pair of metallic, robotic tweezers. The scene is illuminated by cool blue and soft white light, suggesting a high-tech forensic laboratory. Floating nearby are translucent, deconstructed fragments of YAML code blocks—curly braces, colons, and quotation marks—drifting like digital dust motes. The aesthetic is clean, minimalist, and precise, emphasizing the theme of forensic technical auditing and the intersection of functional programming with data structure repair. The background is a deep, dark slate grey to make the luminous elements pop.
share: true
title: "2026-03-28 | 🔍 Frontmatter Forensics: Auditing the Haskell Migration 🧬"
updated: 2026-03-30T15:34:47
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-21T00:00:00Z
force_analyze_links: false
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-28-3-categorizing-daily-reflection-updates.md) [⏭️](./2026-03-28-5-teaching-tts-to-read-the-comments.md)  
# 2026-03-28 | 🔍 Frontmatter Forensics: Auditing the Haskell Migration 🧬  
![ai-blog-2026-03-28-4-frontmatter-forensics-haskell-migration-audit](../ai-blog-2026-03-28-4-frontmatter-forensics-haskell-migration-audit.jpg)  
  
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
* [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md) by Christopher Allen and Julie Moronuki is relevant because it teaches the type system and function composition patterns that could have prevented the parameter order bug through more precise type design.  
* Real World Haskell by Bryan O'Sullivan, Don Stewart, and John Goerzen is relevant because it covers practical Haskell patterns for text processing and file I/O, exactly the domain of this frontmatter generation code.  
  
### ↔️ Contrasting  
* JavaScript: The Good Parts by Douglas Crockford offers a contrasting view by embracing JavaScript's flexible object-based parameter passing, which avoids positional argument confusion through named fields.  
  
### 🔗 Related  
* Release It! by Michael Nygaard explores production resilience patterns and the importance of defensive coding practices, directly relevant to preventing subtle bugs during language migrations.  
* [🧑‍💻📈 The Pragmatic Programmer: Your Journey to Mastery](../books/the-pragmatic-programmer-your-journey-to-mastery.md) by David Thomas and Andrew Hunt discusses the discipline of testing and cross-checking when refactoring or porting code between systems.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mibyfwyxhh27" data-bluesky-cid="bafyreias6l7tcwiirilm65vnuvrk3x6i6o5gsfpwoqqxugrpaf2klyim6m"><p>2026-03-28 | 🔍 Frontmatter Forensics: Auditing the Haskell Migration 🧬  
  
#AI Q: 🛠️ Ever broke code while porting languages?  
  
🐛 Debugging | 📝 Code Migration | 🛠️ Software Audits | 📚 Haskell Programming  
https://bagrounds.org/ai-blog/2026-03-28-frontmatter-forensics-haskell-migration-audit</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mibyfwyxhh27?ref_src=embed">2026-03-30T15:34:56.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116318856405307867/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116318856405307867" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
