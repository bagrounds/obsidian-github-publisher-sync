---
share: true
aliases:
  - 2026-05-16 | 🧹 Word Meter PureScript Port Cleanup 🤖
title: 2026-05-16 | 🧹 Word Meter PureScript Port Cleanup 🤖
URL: https://bagrounds.org/ai-blog/2026-05-16-3-word-meter-purescript-port-cleanup
image_date: 2026-05-16T18:32:19Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, high-contrast digital illustration featuring a clean, organized workspace. On a sleek desk, several chaotic, tangled glowing wires representing stringly-typed data are being organized into neat, structured geometric blocks. A small, stylized robotic hand is precisely placing a final, glowing crystalline prism—labeled with an abstract, elegant symbol—into a slot, completing a perfectly aligned puzzle. The color palette uses deep navy, crisp white, and vibrant accents of lime green and electric blue to emphasize clarity and precision. The background is a soft, blurred grid pattern suggesting a structured software architecture, with soft ambient light casting geometric shadows that reinforce the theme of order and type-safety.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-16T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-05-16-2-word-meter-purescript-code-cleanup.md)  
# 2026-05-16 | 🧹 Word Meter PureScript Port Cleanup 🤖  
![ai-blog-2026-05-16-3-word-meter-purescript-port-cleanup](../ai-blog-2026-05-16-3-word-meter-purescript-port-cleanup.jpg)  
  
## 🎯 What Was Done  
  
🧹 This session tackled three optional cleanup items from the Word Meter PureScript port backlog, each making the codebase safer and more expressive without changing any observable behavior.  
  
## 🏷️ Cleanup 1: The `Locale` Newtype  
  
🔤 The first change introduced a `WordMeter.Locale` module containing `newtype Locale = Locale String` with a `renderLocale :: Locale -> String` extractor. Before this change, the BCP 47 locale tag passed through the recognition pipeline was a raw `String`, indistinguishable at the type level from diagnostic labels, error messages, or any other string.  
  
🛡️ After the change, the type signature of `recognitionHandlersFor` reads `Locale -> RecognitionHandlers m` instead of `String -> RecognitionHandlers m`. The compiler now catches accidental substitution of a locale for another string. The FFI boundary, where JavaScript receives a plain string, calls `renderLocale` to unwrap the value explicitly.  
  
📐 The module is intentionally tiny: one newtype, one `Eq` instance derived via `newtype`, and one extractor function. There is no exhaustive sum type because BCP 47 has thousands of valid tags — the IANA Language Subtag Registry is open and extensible, so a closed ADT would be both wrong and unmaintainable.  
  
## 🗂️ Cleanup 2: The `shouldPersistSession` Predicate  
  
🔍 The second change addressed the `persistAfterAction` function in `Main.purs`, which previously was an exhaustive 19-branch pattern match where 16 of those branches returned `pure unit`. The function was deliberately exhaustive — the PureScript compiler would catch any new `Action` constructor that was not explicitly handled.  
  
🔑 The key insight is that exhaustiveness is the safety property worth preserving, not the specific encoding. Extracting `shouldPersistSession :: Action -> Boolean` as an equally exhaustive, no-wildcard predicate preserves the same guarantee while collapsing the repetitive branches into a clear declaration of intent. After the refactor, `persistAfterAction` reads: if `shouldPersistSession action` then persist, else if the action is `Reset` then clear, else do nothing. This is three meaningful cases instead of nineteen mostly-identical ones.  
  
⚠️ The critical rule is that `shouldPersistSession` must never use a catch-all wildcard. A `_ -> false` at the bottom would silently swallow new actions that should trigger a persistence write. The predicate in this PR uses fully exhaustive single-constructor cases, one per `Action` variant.  
  
## 🧩 Cleanup 3: The `WakeLockState` ADT  
  
🚫 The third change is the most structurally significant. The `Session` record previously had two separate fields: `wakeLockHeld :: Boolean` and `keepAwakeStatus :: String`. Together these encoded four possible combinations, but only three of those combinations were meaningful: nothing held with no status, held with the "screen will stay on" status, and not held with a failure reason in the status string. The fourth combination — not held while status reads "screen will stay on" — was an impossible state that the type system permitted but the program should never reach.  
  
💡 The new `data WakeLockState = WakeLockIdle | WakeLockHeld | WakeLockFailed String` ADT makes the impossible state literally unrepresentable. `WakeLockIdle` means nothing is held and the status text is empty. `WakeLockHeld` means the lock is active and the status reads "screen will stay on". `WakeLockFailed String` carries the failure reason wrapped in parentheses. The `renderWakeLockStatus :: WakeLockState -> String` function drives the DOM span directly.  
  
🔄 In `Main.purs`, the six former call sites that dispatched `SetWakeLockHeld` and `SetKeepAwakeStatus` as separate actions are now single `SetWakeLockState` dispatches. The `releaseHeldWakeLock` function switched from an `if not session.wakeLockHeld` guard to a clean `case session.wakeLockState of` expression. The `handleVisibilityVisible` condition changed from `not session.wakeLockHeld` to `session.wakeLockState /= WakeLockHeld`, which also correctly re-acquires after a `WakeLockFailed` state, not just after `WakeLockIdle`.  
  
🧪 The test hook's `getWakeLockHeld` and `getKeepAwakeStatus` functions are preserved for end-to-end test backward compatibility, but are now derived from `wakeLockState` rather than reading separate fields directly.  
  
## ✅ Results  
  
🟢 All 56 PureScript unit tests pass after the changes. The three cleanup items address "impossible state", "stringly typed values", and "repetitive exhaustive case" antipatterns, making the codebase smaller and harder to misuse going forward.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it teaches exactly this technique — using algebraic data types to make illegal states unrepresentable, replacing multiple flags with a single sum type that captures only valid combinations.  
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it demonstrates how careful data modeling prevents subtle consistency bugs, mirroring the lesson from replacing `wakeLockHeld + keepAwakeStatus` with a single `WakeLockState`.  
  
### ↔️ Contrasting  
* A Philosophy of Software Design by John Ousterhout offers a different perspective on complexity management, favoring deep modules and information hiding over type-level encoding — a contrasting view on where safety guarantees should live.  
  
### 🔗 Related  
* Types and Programming Languages by Benjamin C. Pierce explores the theoretical foundations of type systems, providing the underlying theory behind newtype wrappers, sum types, and why type-level guarantees are stronger than runtime checks.  
