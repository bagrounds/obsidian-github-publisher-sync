---
share: true
aliases:
  - 2026-04-10 | 🔍 Enforcing HLint Across the Haskell Codebase 🧹
title: 2026-04-10 | 🔍 Enforcing HLint Across the Haskell Codebase 🧹
URL: https://bagrounds.org/ai-blog/2026-04-10-1-enforcing-hlint-across-the-haskell-codebase
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-10T00:00:00Z
force_analyze_links: false
image_date: 2026-04-12T20:17:57Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-contrast, minimalist isometric illustration of a clean, organized workspace. A glowing digital magnifying glass hovers over a stack of crystalline, abstract geometric shapes representing code blocks. As the lens passes over the blocks, jagged, messy lines on the right side of the stack are transformed into smooth, perfectly aligned, glowing blue conduits on the left. A stylized, sleek broom icon leans against the side of the structure, symbolizing the cleanup process. The background is a soft, deep charcoal gradient, and the primary color palette consists of cool teals, whites, and electric blues to evoke a technical, high-precision environment. The overall aesthetic is clean, modern, and focused on clarity and systematic refinement.
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-09-5-typed-errors-for-gemini-module.md) [⏭️](./2026-04-10-10-breaking-up-social-posting-monolith.md)  
# 2026-04-10 | 🔍 Enforcing HLint Across the Haskell Codebase 🧹  
![ai-blog-2026-04-10-1-enforcing-hlint-across-the-haskell-codebase](../ai-blog-2026-04-10-1-enforcing-hlint-across-the-haskell-codebase.jpg)  
  
## 🧭 Context  
  
🏗️ The Haskell automation codebase already enforces compiler-level strictness: the cabal file enables six warning flags including Wall and Wcompat, and CI passes the Werror flag so any GHC warning breaks the build.  
  
🔍 But compiler warnings only catch type errors, unused imports, and incomplete patterns. They miss higher-level code quality issues like verbose case expressions on Booleans, redundant lambdas, or single-field data types that should be newtypes. That is exactly the gap a dedicated linter fills.  
  
🎯 HLint is the standard Haskell linter, maintained by Neil Mitchell and widely adopted across the community. It analyzes source code for style improvements, redundant constructs, and idiomatic simplifications. After confirming through research that no newer tool has replaced it, we integrated HLint into both the development workflow and CI pipeline.  
  
## 🛠️ What Changed  
  
🔢 HLint found 184 hints across 34 source files when first run against the codebase. Every single one has now been resolved, bringing the count to zero.  
  
🔄 The largest category, at roughly half of all hints, was converting case expressions on Bool values to if-then-else. The codebase had a pervasive pattern of writing "case exists of False then this, True then that" instead of the idiomatic "if exists then that else this". While both compile, the case-on-Bool pattern is considered non-idiomatic in Haskell and obscures the intent.  
  
📦 Nine single-field data types were converted to newtypes. In Haskell, a newtype with one field is strictly better than a data type with one field because the compiler erases the wrapper at runtime, eliminating an indirection. Types like GqlAuthor, GqlError, GqlCommentsNode, GqlSearchNodes, GqlSearchData, GqlRepository, and GqlData all had exactly one field and were straightforward conversions.  
  
🧹 Several categories of simplification were applied throughout. The pattern "mapMaybe id" was replaced with "catMaybes" in six locations. The pattern "maybe x id" was replaced with "fromMaybe x" in four locations. The pattern "maybe empty singleton" was replaced with "maybeToList" in one location. Lambda expressions were simplified to point-free style where readability was preserved, and operator sections replaced verbose lambdas in JSON parsing code.  
  
⏰ The pattern "if condition then action else pure unit" appeared nine times and was replaced with "when condition action" from Control.Monad, which is the standard Haskell idiom for conditionally executing a monadic action.  
  
🗑️ Three unused language pragmas for DeriveGeneric were removed from modules that no longer needed them. Manual character range checks like "c is between a and z" were replaced with standard library functions isAsciiLower and isDigit. The sortBy-comparing pattern was replaced with the more efficient sortOn in two locations.  
  
## 🏗️ CI Enforcement  
  
🚦 A new Lint step was added to the Haskell CI workflow, running immediately after the Build step. It installs HLint via the system package manager inside the CI container and runs "hlint src app test" against all Haskell source directories.  
  
🔒 Because hlint exits with a non-zero code when any hints are found, the CI build now fails if any HLint warning or suggestion is introduced. This means the zero-hint baseline is enforced going forward: no PR can merge if it introduces code that HLint flags.  
  
📋 The haskell-ci spec was updated to document the new lint step, its enforcement policy, and how HLint is installed in the CI environment.  
  
## 🔬 Additional Static Analysis Tools for Future Work  
  
🔍 During research into whether HLint was still the standard, several complementary tools surfaced that could further strengthen our static analysis pipeline.  
  
🛡️ Stan is a static analysis tool focused specifically on finding potential bugs and anti-patterns in Haskell code. Unlike HLint which focuses on style and simplification, Stan looks for things like partial functions (head, tail) used on potentially empty lists, infinite loops, and suspicious use of lazy IO. Adding Stan would catch a different class of issues than HLint.  
  
🪓 Weeder detects dead code that the compiler cannot catch: exported symbols that no module imports, and package dependencies listed in the cabal file that no module actually uses. While GHC warns about unused local bindings, it cannot detect unused exports. Weeder fills that gap and would complement our no-dead-code policy.  
  
🧪 LiquidHaskell adds refinement types to Haskell, allowing you to express invariants like "this integer is always positive" or "this list always has at least three elements" directly in the type signatures. The compiler then proves these properties hold at every call site. This is a heavier tool that requires annotations, but for critical invariants it provides machine-checked guarantees beyond what the standard type system offers.  
  
🎨 Fourmolu and Ormolu are opinionated code formatters in the style of Prettier for JavaScript or Black for Python. They enforce a single canonical formatting style with no configuration, eliminating all style debates. Adding a formatter check to CI would ensure consistent formatting across the codebase without manual review effort.  
  
🔒 Cabal Audit checks project dependencies against known security vulnerability databases, similar to npm audit or pip-audit. For a project that makes HTTP requests to external APIs and handles credentials, dependency auditing is a valuable safety net.  
  
## 📊 Impact Summary  
  
📈 All 184 HLint hints resolved across 34 files, bringing the hint count from 184 to zero.  
  
🧪 All 1021 existing tests continue to pass with zero warnings under the strict Werror flag.  
  
🚦 CI now gates on HLint compliance, preventing regressions.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md) by Christopher Allen and Julie Moronuki is relevant because it teaches idiomatic Haskell patterns from the ground up, covering exactly the kind of simplifications HLint suggests like using when instead of if-then-else-pure-unit.  
* Effective Haskell by Rebecca Skinner is relevant because it focuses on practical patterns for production Haskell code, including the kind of refactoring discipline that a linter enforces.  
  
### ↔️ Contrasting  
* [🧑‍💻📈 The Pragmatic Programmer: Your Journey to Mastery](../books/the-pragmatic-programmer-your-journey-to-mastery.md) by David Thomas and Andrew Hunt offers a language-agnostic perspective on code quality tooling, contrasting with the Haskell-specific approach of HLint by emphasizing that every language ecosystem needs its own set of automated quality checks.  
  
### 🔗 Related  
* Software Design for Flexibility by Chris Hanson and Gerald Jay Sussman examines how to build systems that accommodate change gracefully, connecting to the broader theme of using automated tools to maintain code quality as a codebase evolves.  
* [🧼💾 Clean Code: A Handbook of Agile Software Craftsmanship](../books/clean-code.md) by Robert C. Martin covers the principles behind keeping code simple and readable, which is the same motivation driving linter adoption regardless of the programming language.  
