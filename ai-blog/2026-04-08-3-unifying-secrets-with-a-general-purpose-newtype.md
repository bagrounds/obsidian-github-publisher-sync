---
share: true
aliases:
  - "2026-04-08 | 🔐 Unifying Secrets with a General Purpose Newtype 🤖"
title: "2026-04-08 | 🔐 Unifying Secrets with a General Purpose Newtype 🤖"
URL: https://bagrounds.org/ai-blog/2026-04-08-3-unifying-secrets-with-a-general-purpose-newtype
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-08 | 🔐 Unifying Secrets with a General Purpose Newtype 🤖

## 🎯 The Mission

🔑 Every application has secrets: API keys, access tokens, passwords, auth tokens.
🧩 Previously, only one of these had a dedicated type: the Gemini API key lived inside an ApiKey newtype.
🚨 All other sensitive values, like Twitter access secrets, Bluesky passwords, Mastodon tokens, and Obsidian auth tokens, were plain Text fields.
🎭 That meant they could accidentally appear in logs, error messages, or debug output without any protection.

## 🏗️ What Changed

🆕 A new module called Automation.Secret now provides a single Secret newtype that wraps any sensitive text value.
🛡️ The Show instance always returns the word redacted in angle brackets, so no secret value can ever leak through show or print.
✅ A smart constructor called mkSecret rejects empty or whitespace-only values, catching configuration errors early.

🔄 The old ApiKey type has been completely replaced by Secret across the entire codebase.
📋 Here is a summary of every credential field that is now protected:

- 🐦 Twitter credentials: the API key, API secret, access token, and access secret are all Secret
- 🦋 Bluesky credentials: the app password is Secret, while the identifier remains plain text
- 🐘 Mastodon credentials: the access token is Secret, while the instance URL remains plain text
- 🤖 Gemini configuration: the API key is Secret
- 📱 Obsidian credentials: the auth token is Secret, and the optional vault password is Maybe Secret

## 🧹 Cleanup Along the Way

🗑️ Several backward compatibility aliases were removed because they added indirection without value.
📐 The functions twitterUrlLength, twitterMaxLength, blueskyMaxLength, and mastodonMaxLength were aliases for accessing fields on the PlatformLimits records.
🎯 Call sites now use the direct accessor, like platformMaxCharacters blueskyLimits, which is both clearer and more consistent.

🧪 Two convenience functions in Automation.Text, calculateTweetLength and validateTweetLength, were also removed.
📊 They were just partial applications of the more general calculatePostLength and validatePostLength with twitterLimits baked in.
🔗 All call sites have been updated to use the general versions directly.

## 🧪 Testing

✅ All 867 tests pass after the refactoring.
🔬 The property test for Show redaction was strengthened with a precondition requiring key text longer than ten characters.
🎲 This avoids false positives where a single character like the letter a might coincidentally appear in the redacted output string.

## 💡 Design Decisions

🧅 The Secret module lives at the leaf of the dependency graph, imported by Automation.Types and Automation.ObsidianSync.
🔄 Automation.Types re-exports Secret and mkSecret for backward compatibility, so most modules did not need new import lines.
🏷️ Fields like bcIdentifier and mcInstanceUrl remain plain Text because they are not secret values; they are public identifiers.
📦 The approach follows the domain types over primitives principle: sensitive values deserve their own type to prevent accidental misuse.

## 📚 Book Recommendations

### 📖 Similar
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it demonstrates how newtype wrappers and smart constructors prevent entire categories of bugs, exactly the pattern used here with the Secret type.
* Haskell in Depth by Vitaly Bragilevsky is relevant because it covers advanced newtype usage, phantom types, and module design patterns that inform how Secret was structured.

### ↔️ Contrasting
* The Pragmatic Programmer by David Thomas and Andrew Hunt offers a contrasting view by focusing on practical shortcuts and trade-offs rather than the type-level safety guarantees emphasized in this refactoring.

### 🔗 Related
* Cryptography Engineering by Niels Ferguson, Bruce Schneier, and Tadayoshi Kohno explores the broader challenge of handling secrets safely in software systems, from key management to secure memory handling.
