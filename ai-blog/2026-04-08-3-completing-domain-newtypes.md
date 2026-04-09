---
share: true
aliases:
  - "2026-04-08 | 🏷️ Completing Domain Newtypes: Url, Title, and RelativePath 🔒"
title: "2026-04-08 | 🏷️ Completing Domain Newtypes: Url, Title, and RelativePath 🔒"
URL: https://bagrounds.org/ai-blog/2026-04-08-3-completing-domain-newtypes
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-08 | 🏷️ Completing Domain Newtypes: Url, Title, and RelativePath 🔒

## 🎯 The Mission

🔒 This is step 3 in the Haskell architecture improvement saga. The goal: eliminate raw Text usage for domain concepts that deserve their own types.

🏷️ Three new newtypes join the family: Url, Title, and RelativePath. Together with the previously completed Secret, PlatformLimits, SocialPost, and Day, this completes the entire domain newtypes phase of the architecture plan.

## 🧱 The Three New Types

### 🌐 Url

🔗 A newtype wrapping Text, with a smart constructor that validates the value starts with either the http or https protocol prefix. The accessor function unUrl recovers the raw Text when needed at library boundaries.

📍 Applied to record fields across the codebase: rdUrl in ReflectionData, mprUrl in MastodonPostResult, mcInstanceUrl in MastodonCredentials, lcUri in LinkCard.

### 📝 Title

🏷️ A newtype wrapping Text, with a smart constructor that rejects empty and whitespace-only values. The accessor function unTitle recovers the raw Text.

📍 Applied to: rdTitle in ReflectionData, ogTitle in OgMetadata (as Maybe Title), lcTitle in LinkCard, cnTitle in ContentNote, ceTitle and cePlainTitle in ContentEntry, ulTitle in UpdateLink.

### 📂 RelativePath

🗂️ A newtype wrapping Text, with a smart constructor that rejects empty strings and absolute paths starting with a forward slash. The accessor function unRelativePath recovers the raw Text.

📍 Applied to: cnRelativePath and cnLinkedNotePaths in ContentNote, ceRelativePath in ContentEntry, frRelativePath in FileResult, ulRelativePath in UpdateLink.

## 🌊 The Ripple Effect

📐 Changing a record field from Text to a newtype is a small declaration, but its effects ripple outward through every file that constructs or consumes that record. This migration touched about 15 source files and 4 test files.

🏗️ At construction sites, raw Text values needed wrapping with constructors. Where code previously wrote cnTitle equal to some text value, it now writes cnTitle equal to Title of that text value.

📤 At usage sites where Text was expected, the newtype wrapper needed unwrapping with an accessor. String concatenation, Aeson serialization, HTTP request construction, and logging all required explicit unwrapping.

🔍 The compiler was the migration guide. Every type mismatch pointed directly to a site that needed attention. The cascade was mechanical but required careful reading of each error context to choose the right fix: wrap or unwrap.

## 🧪 New Property Tests

✅ Twenty-four new property-based and unit tests verify the invariants of each type.

🌐 For Url: constructed values always start with http, the smart constructor round-trips for valid input, and non-http input is rejected.

📝 For Title: the smart constructor round-trips for non-empty input, all-whitespace input is rejected.

📂 For RelativePath: the smart constructor round-trips for valid input, absolute paths are rejected, and constructed values never start with a forward slash.

🎉 All 897 tests pass: 873 original plus 24 new.

## 🗺️ Roadmap Update

✅ Phase 2 of the architecture plan is now complete. All seven domain newtypes are delivered: Secret, PlatformLimits, SocialPost, Day (replacing DateStr), Url, Title, and RelativePath.

📋 A new roadmap item was added: breaking up the monolithic Types module into domain-specific modules. The Types module currently holds credentials, embed types, platform constants, section headers, and more in a single 212-line file. Each group belongs in the module that owns its domain concept.

🔜 The next phases are the AppContext record, explicit error types, separating data from behavior in ImageProviderConfig, and breaking up RunScheduled.

## 💡 Design Decisions

⚖️ The Url smart constructor accepts both http and https, not just https. Some internal URLs and development URLs may use http, and being overly restrictive would force workarounds.

🧩 Each newtype lives in its own module (Automation.Url, Automation.Title, Automation.RelativePath) and is re-exported from Automation.Types for backward compatibility. This follows the same pattern established by Automation.Secret.

🔓 The constructors are exported (not hidden behind smart constructors only) because many internal construction sites have already-validated data. The smart constructors exist for boundary validation where raw user input enters the system.

## 📚 Book Recommendations

### 📖 Similar
- 🏗️ Domain-Driven Design by Eric Evans is relevant because this entire exercise embodies the core DDD principle of making implicit domain concepts explicit through the type system, giving each concept its own language and boundaries
- 🎯 Type-Driven Development with Idris by Edwin Brady is relevant because it demonstrates how strong types can guide program construction and catch errors at compile time, exactly the workflow experienced during this migration

### ↔️ Contrasting
- 🐍 Fluent Python by Luciano Ramalho offers a perspective from a dynamically typed language where this kind of migration would be invisible to the compiler, relying instead on convention and runtime checks to prevent field misuse

### 🔗 Related
- 🧠 Haskell Programming from First Principles by Christopher Allen and Julie Moronuki is relevant because it thoroughly covers newtypes and their role in providing type safety without runtime cost, the exact technique used here
- 🔧 Algebra of Programming by Richard Bird and Oege de Moor is relevant because it explores the mathematical foundations behind the functional abstractions and type-driven design patterns used throughout this codebase
