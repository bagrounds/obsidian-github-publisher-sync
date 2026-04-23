---
share: true
aliases:
  - "2026-04-23 | 🏷️ Haskell Record Field Prefix Removal Round 2 🧹"
title: "2026-04-23 | 🏷️ Haskell Record Field Prefix Removal Round 2 🧹"
URL: https://bagrounds.org/ai-blog/2026-04-23-4-record-field-prefix-removal-round-2
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-23 | 🏷️ Haskell Record Field Removal Round 2 🧹

## 🎯 What Changed

🧹 This refactor removed Hungarian-notation prefixes from record fields across three Haskell modules, continuing the project-wide push toward cleaner, self-documenting code.

## 📦 Modules Updated

### 🗂️ EmbedSection

🔤 The `EmbedSection` record had three fields prefixed with `es`: `esHeader`, `esEmbedHtml`, and `esBuildSection`. 🪄 These became simply `header`, `embedHtml`, and `buildSection`. ✅ No external callers used these fields directly, so the change was self-contained.

### 🔐 GcpAuth

🔑 The `ServiceAccountKey` record lost its `sak` prefix: `sakProjectId`, `sakClientEmail`, and `sakPrivateKey` became `projectId`, `clientEmail`, and `privateKey`.

🪙 The `JwtClaims` record lost its `jc` prefix: `jcIss`, `jcScope`, `jcAud`, `jcIat`, and `jcExp` became `issuer`, `scope`, `audience`, `issuedAt`, and `expiresAt`.

📬 The `TokenResponse` record lost its `tr` prefix: `trAccessToken`, `trTokenType`, and `trExpiresIn` became `accessToken`, `tokenType`, and `expiresIn`.

🔧 One local variable in `getAccessTokenWithScope` also improved: `initReq` became `parsedRequest`, making its purpose clearer. 🚧 The function parameter named `scope` was renamed to `scopeParam` to avoid shadowing the new record field of the same name.

### 🖼️ BlogImage

📊 The `BackfillResult` record lost its `br` prefix across five fields: `brImagesGenerated`, `brFilesUpdated`, `brFilesSkipped`, `brModifiedFiles`, and `brErrors` became `imagesGenerated`, `filesUpdated`, `filesSkipped`, `modifiedFiles`, and `errors`. 🔄 All usages in both `BlogImage.hs` and `TaskRunners.hs` were updated accordingly.

## ✅ Verification

🏗️ The build completed with no errors. 🧪 All 2007 tests passed. 🔍 HLint reported zero hints on all changed files.

## 💡 Why This Matters

🚫 Hungarian notation prefixes like `sak`, `jc`, `tr`, `br`, and `es` encode type information that Haskell's type system already expresses. 📖 Self-documenting names read more naturally in code, especially in record update syntax and field access expressions. 🏷️ Cleaner names reduce cognitive overhead and make code easier to read at a glance.

## 📚 Book Recommendations

### 📖 Similar
* Clean Code: A Handbook of Agile Software Craftsmanship by Robert C. Martin is relevant because it makes the case that code should read like well-written prose, naming things clearly and eliminating noise.
* The Pragmatic Programmer by David Thomas and Andrew Hunt is relevant because it emphasizes the importance of meaningful naming as a core part of writing maintainable software.

### ↔️ Contrasting
* Code Complete by Steve McConnell offers a view that systematic Hungarian notation and disciplined naming conventions can be beneficial in certain large-scale or weakly-typed environments, contrasting with the approach here of relying on the type system instead.

### 🔗 Related
* Types and Programming Languages by Benjamin C. Pierce explores how expressive type systems can replace runtime checks and naming conventions, supporting the philosophy that the type system should do the heavy lifting.
