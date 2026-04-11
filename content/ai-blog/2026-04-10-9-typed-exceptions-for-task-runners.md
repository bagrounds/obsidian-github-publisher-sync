---
share: true
aliases:
  - 2026-04-10 | 🎯 Typed Exceptions for Task Runners 🛡️
title: 2026-04-10 | 🎯 Typed Exceptions for Task Runners 🛡️
URL: https://bagrounds.org/ai-blog/2026-04-10-9-typed-exceptions-for-task-runners
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-10T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-10-8-extracting-pure-utilities-from-the-god-module.md)  
# 2026-04-10 | 🎯 Typed Exceptions for Task Runners 🛡️  
  
## 🧩 The Problem  
  
🔥 Seven calls to Haskell's built-in error function lurked in the RunScheduled task runners, each one a potential source of confusing crash messages.  
  
💥 The error function throws an untyped ErrorCall exception, which carries no structured information about what went wrong.  
  
🎭 When the TaskRunner framework caught these exceptions, the run summary would display raw error messages prefixed with ErrorCall, making it harder to read at a glance.  
  
📋 The architecture roadmap identified these seven non-startup error calls as the next target for principled error handling.  
  
## 🔧 The Solution  
  
🏗️ We introduced a typed TaskError exception in the TaskRunner module, a simple newtype wrapper around Text with three key properties.  
  
🎨 First, a custom Show instance that outputs just the message text, with no constructor name or quotes cluttering the output.  
  
📦 Second, an Exception instance that allows the TaskRunner's existing try-based catch mechanism to catch it seamlessly alongside any other exception.  
  
🧰 Third, a failTask helper function that accepts Text directly, eliminating the need for Text to String conversion at every call site.  
  
## 🔄 What Changed  
  
🗂️ In RunScheduled.hs, all seven non-startup error calls became failTask calls.  
  
🤖 The callGeminiForGenerator function, used by both AI fiction and reflection title generators, now throws a TaskError with a descriptive Gemini API error prefix.  
  
📝 The runBlogSeries function had five error calls replaced, covering missing run configurations, series lookup failures, blog context build failures, generation failures, and post parsing failures.  
  
🧮 One interesting wrinkle emerged with the slug construction. The original code used error inside a pure let binding, since error has the type forall a, String to a, meaning it fits anywhere. But failTask returns IO a, which cannot appear in a pure let binding. The fix was to restructure the binding from a let expression into a monadic do-binding using the either failTask pure pattern.  
  
## 🧪 Testing  
  
✅ Seven new tests bring the total from 1202 to 1209.  
  
🔍 Unit tests verify that Show outputs clean messages without the constructor name, that unicode characters in error messages are preserved, and that TaskError can be caught both as SomeException and downcast via fromException.  
  
🔗 An integration test confirms that a task using failTask is properly marked as failed in the run summary with the correct error message.  
  
🎲 A property test verifies that any arbitrary error message string round-trips correctly through the throw-and-catch cycle, ensuring the custom Show instance faithfully preserves the original message.  
  
## 💡 Key Learnings  
  
🏷️ Typed exceptions carry more semantic weight than error's ErrorCall. A TaskError can be specifically caught and identified, while ErrorCall is a catch-all that could come from anywhere in the program.  
  
📐 When migrating from error to an IO-based failure function, be prepared to restructure pure let bindings into monadic bindings. The either failTask pure pattern bridges Either values into IO cleanly.  
  
🔤 Accepting Text directly in the failure API eliminates boilerplate. Since most error messages in the codebase are already Text values from domain functions returning Either Text, there is no need for a String intermediary.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* [🐣🌱👨‍🏫💻 Haskell Programming from First Principles](../books/haskell-programming-from-first-principles.md) by Christopher Allen and Julie Moronuki is relevant because it thoroughly covers Haskell's exception handling mechanisms, including the distinction between pure bottom values from error and proper IO exceptions from throwIO, which is exactly the distinction this change makes.  
* Real World Haskell by Bryan O'Sullivan, Don Stewart, and John Goerzen is relevant because it dedicates significant attention to error handling patterns in production Haskell code, including when to use exceptions versus Either types for different layers of an application.  
  
### ↔️ Contrasting  
* Release It! by Michael Nygard offers a contrasting perspective focused on runtime resilience patterns like circuit breakers and bulkheads, where the emphasis is on gracefully degrading rather than precisely typing every failure mode.  
  
### 🔗 Related  
* [🧑‍💻📈 The Pragmatic Programmer: Your Journey to Mastery](../books/the-pragmatic-programmer-your-journey-to-mastery.md) by David Thomas and Andrew Hunt explores the broader principle of failing fast with clear error messages, which is the motivation behind replacing untyped error calls with descriptive typed exceptions that produce readable run summaries.  
