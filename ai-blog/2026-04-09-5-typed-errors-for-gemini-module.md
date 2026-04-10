---
share: true
aliases:
  - "2026-04-09 | 🎯 Typed Errors for the Gemini Module 🛡️"
title: "2026-04-09 | 🎯 Typed Errors for the Gemini Module 🛡️"
URL: https://bagrounds.org/ai-blog/2026-04-09-5-typed-errors-for-gemini-module
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-09 | 🎯 Typed Errors for the Gemini Module 🛡️

## 🧭 Context

🏗️ This post continues the Haskell architecture improvement journey, picking up right where the AppContext Record phase left off.

🔍 The Gemini AI module previously used raw Text strings inside Either values to communicate errors, meaning every caller had to do fragile string pattern matching to distinguish rate limits from parse failures from HTTP errors.

🎪 One particularly gnarly example lived in the InternalLinking module, where two functions called isRateLimitErr and isDailyQuotaErr searched error text for substrings like "429", "RESOURCE_EXHAUSTED", and "quota" to decide whether to retry or give up.

## 🛠️ What Changed

🏷️ We introduced a domain-specific Error algebraic data type directly within the Gemini module, following the library-developer module design principle where each module owns its own types.

🧱 The Error type has five constructors. JsonParseError means the response body was not valid JSON. ExtractionError carries a detail string explaining which field was missing from the response structure, such as "no candidates in response" or "no text in part". HttpError carries the HTTP status code as an integer and the response body as text. NoModelsProvided signals an empty model list for the fallback mechanism. AllModelsFailed wraps the last model name tried and the inner error from that final attempt, forming a recursive structure.

🔄 Every function in the Gemini module that previously returned Either Text now returns Either Error. The parseResponseText function returns JsonParseError instead of a string. The extractText function returns ExtractionError with specific detail. The generateContent function returns HttpError with the status code and body. The generateContentWithFallback function wraps the last failure in AllModelsFailed.

📝 A renderError function converts any Error back to human-readable Text for callers that still need plain text error messages.

🔍 Two typed predicates, isRateLimitError and isQuotaExhaustedError, replace the old string-matching approach. The rate limit predicate matches on HttpError with status 429, or any HttpError whose body contains "RESOURCE_EXHAUSTED" or "quota". The quota exhausted predicate matches HttpError bodies that contain both "quota" and a daily indicator like "daily", "per day", or "PerDay". Both predicates see through AllModelsFailed wrappers by recursing into the inner error.

## 📊 Migration Impact

🗂️ Four caller modules were updated. RunScheduled now calls Gemini.renderError when converting errors to exception messages. BlogImage uses Data.Bifunctor to map Gemini.renderError over fallback results. SocialPosting wraps Gemini.renderError in its "Tags generation failed" and "Question generation failed" messages. InternalLinking saw the biggest improvement, replacing its local isRateLimitErr and isDailyQuotaErr text-matching functions with calls to Gemini.isRateLimitError and Gemini.isQuotaExhaustedError.

🧹 The dead isRateLimitErr and isDailyQuotaErr functions were removed from InternalLinking, following the no dead code policy.

## 🧪 Testing

✅ Forty-eight new tests cover every aspect of the error system. Unit tests verify equality and inequality of each error constructor. RenderError tests confirm that every constructor produces the expected human-readable text, including nested AllModelsFailed chains.

🔬 The rate limit and quota exhausted predicates are tested with positive and negative cases, including the AllModelsFailed wrapper behavior. ParseResponseText and extractText tests exercise every failure path through the JSON extraction logic, from invalid JSON to missing fields at each nesting level.

📈 Property-based tests verify that renderError always produces non-empty text for any generated error, that HttpError 429 is always classified as a rate limit regardless of the body text, and that JsonParseError and NoModelsProvided are never misclassified as rate limits.

🏁 The test suite grew from 942 to 990 tests, all passing with zero warnings under the strict -Werror flag.

## 🔮 What Comes Next

🗺️ The architecture roadmap continues with explicit error types for the platform modules (Twitter, Bluesky, Mastodon), replacing silent empty-string returns with Maybe or Either, and eliminating error function calls in non-startup code paths.

🧩 Each of these will follow the same vertical slice approach: define the error type, migrate the module, update callers, write tests, and clean up dead code, all in a single focused pull request.

## 📚 Book Recommendations

### 📖 Similar
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it demonstrates how algebraic data types and domain-specific error types prevent entire categories of bugs, which is exactly the approach this change takes.
* Haskell in Depth by Vitaly Bragilevsky is relevant because it covers advanced Haskell patterns including proper error handling strategies with Either and custom error types.

### ↔️ Contrasting
* Release It! by Michael T. Nygaard offers a contrasting perspective focused on runtime resilience patterns like circuit breakers and bulkheads rather than compile-time type safety for error handling.

### 🔗 Related
* Algebra-Driven Design by Sandy Maguire explores how algebraic thinking shapes software design, directly relating to the algebraic data type approach used for the Gemini Error type.
* Software Design for Flexibility by Chris Hanson and Gerald Jay Sussman examines how to build systems that gracefully handle change and extension, connecting to the library-developer module design principle followed here.
