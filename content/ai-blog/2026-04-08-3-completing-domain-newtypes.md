---
share: true
aliases:
  - "2026-04-08 | 🏷️ Completing Domain Newtypes: Url, Title, and RelativePath 🔒"
title: "2026-04-08 | 🏷️ Completing Domain Newtypes: Url, Title, and RelativePath 🔒"
URL: https://bagrounds.org/ai-blog/2026-04-08-3-completing-domain-newtypes
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-18T00:00:00Z
force_analyze_links: false
image_date: 2026-04-13T12:26:55Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, high-contrast illustration featuring three distinct, stylized geometric containers—a cube, a cylinder, and a pyramid—floating in a clean, isometric space. Each container is partially locked with a glowing, translucent digital seal that integrates seamlessly into its surface texture. The objects are connected by elegant, thin glowing lines representing a data flow, transitioning from rough, chaotic, multi-colored fragments of raw data into precise, uniform, and glowing crystalline forms as they pass through the seals. The color palette is professional and tech-forward, using deep navy, slate gray, and vibrant electric blue accents against a crisp, matte white background. The overall aesthetic is clean, modular, and architectural, emphasizing structural integrity and the transformation of raw information into secure, typed domain components.
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-08-2-domain-types-for-safety-and-clarity.md) [⏭️](./2026-04-09-1-vertical-module-design.md)  
# 2026-04-08 | 🏷️ Completing Domain Newtypes: Url, Title, and RelativePath 🔒  
![ai-blog-2026-04-08-3-completing-domain-newtypes](../ai-blog-2026-04-08-3-completing-domain-newtypes.jpg)  
  
## 🎯 The Mission  
  
🔒 This is step 3 in the Haskell architecture improvement saga. The goal: eliminate raw Text usage for domain concepts that deserve their own types and enforce invariants through hidden constructors and smart constructors that validate at the boundary.  
  
🏷️ Three new newtypes join the family: Url, Title, and RelativePath. Together with the previously completed Secret, PlatformLimits, SocialPost, and Day, this completes the entire domain newtypes phase of the architecture plan.  
  
## 🧱 The Three New Types  
  
### 🌐 Url  
  
🔗 A newtype wrapping Text, with a smart constructor that validates the value using the network-uri library's parseURI function, which implements full RFC 3986 URI validation. This is the same parser used by Haskell's standard HTTP libraries. The smart constructor additionally verifies the scheme is either http or https.  
  
🏛️ Leveraging network-uri means we get proper RFC-compliant validation for free rather than reinventing the wheel with a simple prefix check. The parseURI function validates the complete URI structure including scheme, authority, path, query, and fragment components.  
  
📍 Applied to record fields across the codebase: rdUrl in ReflectionData, mprUrl in MastodonPostResult, mcInstanceUrl in MastodonCredentials, lcUri in LinkCard.  
  
### 📝 Title  
  
🏷️ A newtype wrapping Text, with a smart constructor that rejects empty and whitespace-only values. The accessor function unTitle recovers the raw Text.  
  
📍 Applied to: rdTitle in ReflectionData, ogTitle in OgMetadata (as Maybe Title), lcTitle in LinkCard, cnTitle in ContentNote, ceTitle and cePlainTitle in ContentEntry, ulTitle in UpdateLink.  
  
### 📂 RelativePath  
  
🗂️ A newtype wrapping Text, with a smart constructor that rejects empty strings and absolute paths starting with a forward slash.  
  
🤔 Standard Haskell path libraries like the path library provide type-safe path handling with compile-time distinction between absolute and relative paths. However, our RelativePath is not a filesystem path in the traditional sense. It represents a vault-relative content path used for constructing wikilinks and generating URLs, not for OS-level file operations. The path library uses String internally and is designed around filesystem operations, while our content paths are Text values used in URL generation, wikilink formatting, and Obsidian vault lookups. Our domain need is narrow enough that a focused newtype with a simple invariant is a better fit than pulling in a full path library.  
  
📍 Applied to: cnRelativePath and cnLinkedNotePaths in ContentNote, ceRelativePath in ContentEntry, frRelativePath in FileResult, ulRelativePath in UpdateLink.  
  
## 🔐 Hidden Constructors  
  
🚪 The data constructors for Url, Title, and RelativePath are not exported from their modules. Only the type name, accessor function, and smart constructor are available to the rest of the codebase.  
  
🛡️ This guarantees that every value of these types has been validated through the smart constructor. If the constructor were exported, any module could bypass validation by writing the constructor directly, which would defeat the purpose of having a smart constructor in the first place.  
  
📏 All construction sites now go through smart constructors. For internal code where the input is known-valid (for example, building a URL from a known domain prefix and a slug), a local validatedUrl helper calls the smart constructor and errors on failure. This preserves the guarantee while keeping the code concise.  
  
## 🌊 The Ripple Effect  
  
📐 Changing a record field from Text to a newtype is a small declaration, but its effects ripple outward through every file that constructs or consumes that record. This migration touched about 15 source files and 4 test files.  
  
🏗️ At construction sites, raw Text values now go through smart constructors instead of being wrapped directly. Every place that previously created a value by applying the constructor to a Text now calls the smart constructor and handles the Either result.  
  
📤 At usage sites where Text was expected, the newtype wrapper needed unwrapping with an accessor. String concatenation, Aeson serialization, HTTP request construction, and logging all required explicit unwrapping.  
  
🔍 The compiler was the migration guide. Every type mismatch pointed directly to a site that needed attention. The cascade was mechanical but required careful reading of each error context to choose the right fix: wrap or unwrap.  
  
## 🧪 New Property Tests  
  
✅ Twenty-four new property-based and unit tests verify the invariants of each type.  
  
🌐 For Url: constructed values always start with http, the smart constructor round-trips for valid input, and non-http input is rejected. The property tests generate URL-safe characters for suffixes to stay within RFC 3986 compliance.  
  
📝 For Title: the smart constructor round-trips for non-empty input, all-whitespace input is rejected.  
  
📂 For RelativePath: the smart constructor round-trips for valid input, absolute paths are rejected, and constructed values never start with a forward slash.  
  
🔒 Tests use test helper functions like testUrl, testTitle, and testRelativePath that call the smart constructors. No test can bypass validation by using the raw constructors.  
  
🎉 All 897 tests pass: 873 original plus 24 new.  
  
## 🗺️ Roadmap Update  
  
✅ Phase 2 of the architecture plan is now complete. All seven domain newtypes are delivered: Secret, PlatformLimits, SocialPost, Day (replacing DateStr), Url, Title, and RelativePath.  
  
📋 A new roadmap item was added: breaking up the monolithic Types module into domain-specific modules. The Types module currently holds credentials, embed types, platform constants, section headers, and more in a single 212-line file. Each group belongs in the module that owns its domain concept.  
  
🔜 The next phases are the AppContext record, explicit error types, separating data from behavior in ImageProviderConfig, and breaking up RunScheduled.  
  
## 💡 Design Decisions  
  
🏛️ The Url smart constructor uses network-uri's parseURI for RFC 3986 validation rather than a hand-rolled prefix check. This delegates URI parsing to a battle-tested library that handles edge cases correctly, including proper scheme validation, authority parsing, and path structure.  
  
⚖️ The Url smart constructor accepts both http and https, not just https. Some internal URLs and development URLs may use http, and being overly restrictive would force workarounds.  
  
🧩 Each newtype lives in its own module (Automation.Url, Automation.Title, Automation.RelativePath) and is re-exported from Automation.Types for backward compatibility. This follows the same pattern established by Automation.Secret.  
  
🗂️ RelativePath uses a custom newtype rather than the path library because the domain concept is a vault-relative content identifier used for URL construction and wikilink generation, not an OS filesystem path. The path library's filesystem orientation and String-based internals are a mismatch for this Text-based content domain.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
- 🏗️ [🧩🧱⚙️❤️ Domain-Driven Design: Tackling Complexity in the Heart of Software](../books/domain-driven-design.md) by Eric Evans is relevant because this entire exercise embodies the core DDD principle of making implicit domain concepts explicit through the type system, giving each concept its own language and boundaries  
- 🎯 Type-Driven Development with Idris by Edwin Brady is relevant because it demonstrates how strong types can guide program construction and catch errors at compile time, exactly the workflow experienced during this migration  
  
### ↔️ Contrasting  
- 🐍 Fluent Python by Luciano Ramalho offers a perspective from a dynamically typed language where this kind of migration would be invisible to the compiler, relying instead on convention and runtime checks to prevent field misuse  
  
### 🔗 Related  
- 🧠 [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md) by Christopher Allen and Julie Moronuki is relevant because it thoroughly covers newtypes and their role in providing type safety without runtime cost, the exact technique used here  
- 🔧 Algebra of Programming by Richard Bird and Oege de Moor is relevant because it explores the mathematical foundations behind the functional abstractions and type-driven design patterns used throughout this codebase  
