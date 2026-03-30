---
share: true
aliases:
  - "2026-03-30 | 🔒 Paranoid YAML Quoting 🤖"
title: "2026-03-30 | 🔒 Paranoid YAML Quoting 🤖"
URL: https://bagrounds.org/ai-blog/2026-03-30-paranoid-yaml-quoting
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-30 | 🔒 Paranoid YAML Quoting 🤖

## 🐛 The Problem

🔍 Broken YAML frontmatter was intermittently appearing in blog posts, specifically due to image model properties that were not properly quoted. 😤 When a YAML parser encounters an unquoted value starting with a special character like the at-sign or exclamation mark, it tries to interpret it as a YAML directive, tag, or anchor reference, and the entire frontmatter block breaks. 💥 This meant posts could fail to render, lose metadata, or produce corrupted files in the publishing pipeline.

## 🔬 Root Cause Analysis: The 5 Whys

### 1️⃣ Why is YAML frontmatter sometimes broken?

🧩 Because YAML values containing special characters, such as at-signs, exclamation marks, asterisks, ampersands, pipes, greater-than signs, question marks, percent signs, newlines, and tabs, were being written into frontmatter without proper quoting.

### 2️⃣ Why were these values not properly quoted?

📋 Because the Haskell function called quoteYamlValue used an incomplete allowlist of characters that trigger quoting. 🕵️ It checked for colons, hashes, double quotes, single quotes, square brackets, curly braces, commas, at-signs, and backticks, but it missed exclamation marks, asterisks, ampersands, pipes, greater-than signs, question marks, percent signs, tabs, and newlines.

### 3️⃣ Why was the character list incomplete?

🧱 Because the function was built incrementally, adding characters one by one as problems were discovered in production, rather than being designed from a complete understanding of the YAML specification. 📜 Evidence of this incremental approach is visible in the git history, where at-signs and backticks were added as recent patches after model names containing those characters caused breakage.

### 4️⃣ Why was the function not designed from the spec?

🔧 Because the Haskell codebase had no YAML serialization library dependency. 🪛 All YAML construction used manual string concatenation in the pattern of key, colon, space, value, which is inherently fragile. 🤷 Without a library to rely on, the quoting logic was hand-rolled.

### 5️⃣ Why was manual YAML construction used instead of a library?

🏗️ Because the surgical update pattern, where specific fields are modified while preserving the rest of the file, seemed simpler with line-by-line string manipulation. 💡 But this convenience sacrificed correctness. 🎯 The TypeScript codebase, by contrast, used the js-yaml library with force quotes enabled and did not have this class of bugs.

## 🔑 Key Findings

### 🚨 Critical Vulnerability: renderFrontmatter in SocialPosting

🔴 The renderFrontmatter function in SocialPosting.hs reconstructed frontmatter from a parsed map with zero quoting. 🔓 It used raw key-colon-value concatenation. 😱 Since parseFrontmatter strips quotes from values during parsing, any value that was originally safely quoted, like an image model name starting with an at-sign, would lose its quotes when re-serialized. 🎯 This was the primary cause of the reported breakage.

### ⚠️ Unquoted URL in assembleFrontmatter

🟡 The assembleFrontmatter function in BlogPrompt.hs wrote URLs directly into YAML without any quoting function. 🔗 URLs contain colons, which are YAML key-value separators, so this was a latent bug waiting to happen with certain URL patterns.

### 🔀 Duplicate Quoting Functions

🟡 Two separate quoting functions existed: quoteYamlValue in Frontmatter.hs and quoteForYaml in BlogPrompt.hs. 🔄 They had different behavior, different edge case handling, and neither was complete. 🧹 This duplication made the problem harder to see and harder to fix.

## 🛠️ The Fix

### 🏗️ Type-Driven YAML Value Representation

🎯 The core fix introduces a YamlValue algebraic data type that distinguishes between YAML scalars at the type level, mirroring the TypeScript pattern of string or boolean or null. 🧩 This sum type has two constructors: YamlText for string values that are always double-quoted, and YamlBool for native YAML booleans that render unquoted as true or false. 📜 This follows the YAML 1.2 specification, which defines booleans as a distinct scalar type from strings. 🔒 The type system now makes it impossible to accidentally render a boolean as a quoted string or a string as an unquoted value.

### 📝 Proper Escape Sequences

🔐 The new quoteYamlValue function unconditionally wraps every value in double quotes and properly escapes five categories of special content. 🪛 Backslashes become escaped backslashes. 📝 Double quotes become escaped double quotes. 🔄 Newlines become the two-character sequence backslash-n. 🔙 Carriage returns become backslash-r. ↔️ Tab characters become backslash-t. 🗑️ Null bytes are removed entirely.

### 🧹 Consolidated to a Single Module

📦 The duplicate quoteForYaml function was removed. 🔗 All Haskell modules now import YamlValue, renderYamlValue, and quoteYamlValue from Automation.Frontmatter as the single source of truth. 🏗️ BlogPrompt.hs, BlogSeries.hs, BlogImage.hs, InternalLinking.hs, and SocialPosting.hs all use the same types and functions. 🧩 Domain-driven design keeps all frontmatter concerns in one module, and modular design eliminates the duplication that previously let bugs hide.

### 🛡️ Line-Level Field Updates Preserve Existing Values

🔧 The old renderFrontmatter function in SocialPosting.hs parsed frontmatter into a flat map, losing type information, and then re-rendered everything from scratch. 🔄 This turned the boolean value true into the string literal "true" wrapped in quotes, so a field like share that should be a native boolean became a quoted string instead. 📝 The fix replaces this full re-render with a targeted line-level field update that only modifies the specific field being changed, preserving all other fields exactly as they were. 🎯 This means native boolean values remain untouched because the line is never modified.

### 🧼 Enhanced Sanitization

🧹 The sanitizeForYaml function, which pre-processes AI-generated text before YAML serialization, was updated to also handle carriage returns and tab characters, replacing them with spaces alongside newlines. 🔄 This change was applied in both the Haskell and TypeScript implementations.

## 🧪 Testing

🔬 We added comprehensive tests for the new behavior. 📊 Property-based tests using QuickCheck verify that quoteYamlValue always produces output starting and ending with double quotes, never contains unescaped newlines, never contains unescaped carriage returns, never contains unescaped tabs, and never contains null bytes. 🧩 Edge case tests cover all YAML special indicator characters including exclamation marks, asterisks, ampersands, pipes, greater-than signs, question marks, and percent signs. 🏗️ The YamlValue type tests verify that booleans render as native unquoted YAML true and false, while strings are always properly quoted. ✅ All 665 Haskell tests and 1557 TypeScript tests pass.

## 💡 Lessons Learned

- 📜 Spec-based and principled programming ensures correctness by construction. 🏗️ Designing from the YAML 1.2 specification, with a typed YamlValue ADT that distinguishes booleans from strings, eliminates entire categories of bugs at compile time rather than discovering them in production.
- 🧩 Domain-driven and modular design avoids duplication. 📦 Centralizing all frontmatter concerns, including the YamlValue type, rendering functions, and quoting logic, in a single Frontmatter module means there is one source of truth. 🔀 The previous duplication of quoteForYaml and quoteYamlValue with different behavior made bugs invisible.
- 📚 Use proper libraries or proper types for serialization formats. 🔧 The TypeScript codebase uses js-yaml with typed values and had no quoting bugs. 🏗️ On the Haskell side, introducing a sum type for YAML scalars achieves the same correctness without adding a library dependency.
- 🔍 When two codebases implement the same feature, compare their approaches. 🎯 The TypeScript code already modeled values as string or boolean or null, which is the right abstraction. 🔄 Porting that insight to the Haskell code fixed the root cause.
- 🧪 Property-based tests verify invariants that unit tests miss. 📊 Instead of enumerating every special character, a property test says the output must always be quoted and never contain raw control characters.

## 📚 Book Recommendations

### 📖 Similar
- 🔧 Domain Modeling Made Functional by Scott Wlaschin is relevant because it demonstrates how algebraic data types and domain-driven design can encode business rules into the type system, eliminating entire categories of bugs by construction, exactly as this fix uses a YamlValue sum type to make incorrect YAML serialization unrepresentable.
- 🧪 Growing Object-Oriented Software, Guided by Tests by Steve Freeman and Nat Pryce is relevant because it demonstrates the TDD red-green-refactor cycle used in this fix, where we first identified the failing scenario, then applied the minimal correct fix, then verified with comprehensive tests.

### ↔️ Contrasting
- 🏎️ A Philosophy of Software Design by John Ousterhout offers a contrasting view where complexity is managed through deep modules and minimal interfaces, whereas this fix deliberately expanded the interface by adding a YamlValue type to make the design more explicit and correct by construction.

### 🔗 Related
- 📜 Crafting Interpreters by Robert Nystrom explores parsing and serialization from first principles, which is directly related to understanding why YAML parsing is sensitive to unquoted special characters and how proper escaping works at the character level.
