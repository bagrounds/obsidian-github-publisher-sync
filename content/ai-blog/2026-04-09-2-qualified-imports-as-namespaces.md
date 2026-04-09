---
share: true
aliases:
  - 2026-04-09 | 🏷️ Qualified Imports as Namespaces 🔤
title: 2026-04-09 | 🏷️ Qualified Imports as Namespaces 🔤
URL: https://bagrounds.org/ai-blog/2026-04-09-2-qualified-imports-as-namespaces
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-09T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-09-1-vertical-module-design.md)  
# 2026-04-09 | 🏷️ Qualified Imports as Namespaces 🔤  
  
## 🎯 The Mission  
  
🔄 Following yesterday's vertical module refactoring, we had self-contained platform modules, but their exported names still carried redundant prefixes. 🐦 The Twitter module exported TwitterCredentials, twitterLimits, tweetSectionHeader, and postTweet. 🤔 If you already know you are working with the Twitter module, why repeat "Twitter" in every name?  
  
## 💡 The Haskell Namespace Pattern  
  
📖 Many well-designed Haskell libraries use a common pattern: export short, generic names from modules and let consumers import them qualified. 🗺️ The module qualifier acts as a namespace, so the type name itself can be concise.  
  
🔢 Think of Data.Map: it exports lookup, insert, and delete, not mapLookup, mapInsert, and mapDelete. 📋 Consumers write Map.lookup and Map.insert, which reads like natural language.  
  
## 🔀 What Changed  
  
### 🐦 Automation.Platforms.Twitter  
  
🏷️ TwitterCredentials became Credentials. 📊 twitterLimits became limits. 📝 tweetSectionHeader became sectionHeader. 🔤 twitterDisplayName became displayName. 📮 postTweet became post. 🗑️ deleteTweet became deletePost. 🧑‍💻 Consumers now write Twitter.Credentials, Twitter.limits, Twitter.post, which is both shorter and more descriptive.  
  
### 🦋 Automation.Platforms.Bluesky  
  
🏷️ BlueskyCredentials became Credentials. 📝 BlueskyPostResult became PostResult. 📊 blueskyLimits became limits. ⏱️ blueskyOembedInitialDelayMs became oembedInitialDelayMs. 📮 postToBluesky became post. 🔍 extractBlueskyDid became extractDid. 🏗️ buildBlueskyPostUrl became buildPostUrl. 🧑‍💻 Consumers write Bluesky.Credentials, Bluesky.post, Bluesky.extractDid.  
  
### 🐘 Automation.Platforms.Mastodon  
  
🏷️ MastodonCredentials became Credentials. 📝 MastodonPostResult became PostResult. 📊 mastodonLimits became limits. 📮 postToMastodon became post. 🔍 extractMastodonInstanceUrl became extractInstanceUrl. 🧑‍💻 Consumers write Mastodon.Credentials, Mastodon.post, Mastodon.extractInstanceUrl.  
  
### 🤖 Automation.Gemini  
  
🏷️ GeminiConfig became Config. 📝 GeminiRequest became Request. 📝 GeminiResponse became Response. 📊 defaultGeminiModel became defaultModel. 🔄 geminiFlashFallback became flashFallback. 🔄 geminiModelFallback became modelFallback. 🧑‍💻 Consumers write Gemini.Config, Gemini.defaultModel, Gemini.generateContentWithFallback.  
  
### 📋 Automation.Types  
  
🪶 The re-export hub was slimmed significantly. 🚫 It no longer re-exports platform-specific types, credentials, or constants. ✅ It only re-exports truly shared types: Secret, PlatformLimits, Url, Title, RelativePath, ReflectionData, OgMetadata, EmbedSection, EnvironmentConfig, and ObsidianCredentials.  
  
## 🧩 Handling Name Collisions  
  
⚠️ Renaming Request in the Gemini module created a collision with Network.HTTP.Client.Request. 🔧 The fix was to import Network.HTTP.Client qualified as HTTP internally, so record update syntax uses HTTP.method and HTTP.requestBody while the module exports its own Gemini.Request without ambiguity.  
  
⚠️ Renaming twitterHandle to handle would shadow the Haskell Prelude handle function and cause name shadowing warnings in functions with a handle parameter. 🔧 The fix was to keep twitterHandle as the one exception where the module-level name retains its qualifier, since handle is too generic a word.  
  
## ✨ The Payoff  
  
📏 Consumer code reads more naturally. 🔎 Instead of extractBlueskyDid and extractMastodonInstanceUrl, you see Bluesky.extractDid and Mastodon.extractInstanceUrl. 🧠 The module qualifier provides context, so the function name focuses on what it does rather than repeating where it lives.  
  
📉 Types.hs shrank from re-exporting over forty symbols to just a dozen shared types. 🎯 Each platform module is now truly independent. 🧹 Removing a platform means deleting one module and updating a handful of qualified imports.  
  
## 📏 AGENTS.md Updates  
  
📝 A new rule was added for qualified imports: import feature modules qualified and use short names within the module. 🧑‍💻 Consumers write import qualified Automation.Platforms.Twitter as Twitter and reference Twitter.Credentials, Twitter.limits, Twitter.post. 🔤 Reserve unqualified imports for truly shared types like PlatformLimits, Secret, and Url.  
  
## 🧪 Tests  
  
🏁 All 924 tests pass with zero warnings. 🔄 Test files updated to use qualified imports matching the new pattern.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Haskell in Depth by Vitaly Bragilevsky is relevant because it covers module design patterns including qualified imports and namespace management, which are exactly the techniques applied in this refactoring.  
* Real World Haskell by Bryan O'Sullivan, Don Stewart, and John Goerzen is relevant because it demonstrates idiomatic Haskell module organization where qualified imports serve as lightweight namespaces.  
  
### ↔️ Contrasting  
* [🧼💾 Clean Code: A Handbook of Agile Software Craftsmanship](../books/clean-code.md) by Robert C. Martin offers a view where long descriptive names are preferred over short names with contextual qualification, which contrasts with the Haskell convention of using module qualifiers to provide context instead of encoding it in the name itself.  
  
### 🔗 Related  
* [💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md) by Don Norman explores how context shapes meaning, which parallels how module qualifiers provide context that allows shorter, more focused names to be unambiguous.  
