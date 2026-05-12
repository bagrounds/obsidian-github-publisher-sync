---
share: true
aliases:
  - "2026-05-12 | 🪜 Word Meter Lifted onto the Capability Pattern 🧱"
title: "2026-05-12 | 🪜 Word Meter Lifted onto the Capability Pattern 🧱"
URL: https://bagrounds.org/ai-blog/2026-05-12-4-word-meter-capability-pattern-refactor
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-12 | 🪜 Word Meter Lifted onto the Capability Pattern 🧱

## 🎬 What This Post Is About
- 🧱 This post explains how the Word Meter PureScript port stopped doing its work in the raw effect monad and was lifted onto the capability typeclass pattern that the broader codebase already documents as the default for side-effecting code.
- 🪜 The pattern wraps every effect the app needs in a small typeclass and a corresponding production newtype called AppM, and pairs every capability with at least one deterministic test newtype.
- 🧹 The same change also strips a stubborn habit out of the code — the impl suffix on foreign import names — and tightens the project guide so that the rule against jargon-style decorators is impossible to misread.

## 🧠 The Problem That Started This
- 🔍 A reviewer pointed out that the Word Meter port was still doing real work directly in the effect monad, even though the repository already had a long-form specification for the capability typeclass pattern and explicitly called effect honesty a non-negotiable rule.
- 🪞 The reviewer also flagged that a couple of foreign import names had crept back in with the impl suffix tacked on the end, which the existing engineering excellence rules already forbid as enterprise-style word soup that adds nothing the type system does not already say.
- 🧪 Finally, the reviewer asked that the brand new PureScript test suite actually run in continuous integration whenever the relevant code changes, instead of relying on a human remembering to run it locally.

## 🧩 What the Capability Pattern Actually Is
- 🏷️ The core idea is that a function whose type is effect of number is dishonest, because it could read the clock or hit storage or call out to speech recognition or do any of those things in combination, and the type tells you none of it.
- 🪪 The capability pattern fixes this by replacing the raw effect monad in production signatures with a typeclass per side-effecting concern. The class names the concern, the methods name the operations, and you write code against a polymorphic monad m constrained by clock m and clipboard m and so on.
- 🧬 This delivers four properties at once. Types become honest about what they consume. Implementations become swappable, so the same code runs against the production AppM newtype that calls real browser APIs and against test newtypes that hand back canned values or record calls into a log. Reasoning becomes compositional, because capabilities lift mechanically through monad transformers. And pure logic that previously sat behind the effect monad becomes property-testable, because you can run it inside a deterministic test monad and treat it like any other pure function.

## 🪜 What Got Lifted Onto Capabilities
- 🕰️ The clock capability covers the current time in milliseconds. The production instance reads the real Date.now value through a thin foreign import, and the fixed clock test newtype hands back whatever number the test configured, with no global stubbing required.
- 📋 The clipboard capability covers writing a string to the system clipboard. Because the underlying browser interface is asynchronous, the capability method takes explicit success and error continuations that execute in the same monad as the call site. The production instance bridges those continuations into the callback-shaped foreign import. The recording test newtype appends every payload into an in-memory array so a test can assert exactly what would have been handed to the system.
- 🌐 The environment capability covers the one-shot snapshot of the user agent and the navigator language. The production instance reads the real browser globals. The stub test newtype hands back whatever environment record the test threads in through a reader monad.
- 🖼️ The DOM mount capability covers replacing the host element's children with a typed node tree. The production instance walks the tree through the existing virtual DOM module's foreign imports. The recording test newtype captures every mount request into an array so a test can assert how many times the program rerendered without ever touching a real DOM.
- 🧠 The session state capability covers reading the current session record and dispatching reducer actions. The production instance keeps the session inside an effect reference held in the application environment. The stateful session test newtype keeps the session inside a state monad transformer over identity, so reducer-driven flows can be exercised against pure state with no effect reference at all.

## 🪄 How Main Looks Now
- 🧵 The new Main module starts by allocating the session reference and the click handlers reference, builds an application environment record that carries the session reference, and then calls runAppM exactly once to run a polymorphic startup program.
- 🧮 The startup program is parameterised over a monad m that satisfies clock m, environment m, DOM mount m, and session state m. It captures the environment snapshot through the environment capability, dispatches a set environment action, captures the current time through the clock capability, dispatches a record diagnostic action for the init event, and finally rerenders by reading the current session and asking the DOM mount capability to mount the typed node tree returned by the view function at the host element.
- 🔁 The click handlers — the two effect-shaped callbacks the typed DOM tree needs to attach to its button listeners — are built once at the boundary by reading the resolved handlers out of a reference and feeding them into the polymorphic toggle and copy handlers, which themselves only require their relevant capability constraints. The reference indirection ties the knot between the handlers and the rerender that needs them without forcing a mutually recursive value binding, which PureScript does not allow.
- 🧪 The test hook installation happens entirely at the effect boundary, because the test hook is, by definition, the place where the test environment talks to the bundle through JavaScript-shaped callbacks. Every callback handed to the hook delegates back into runAppM with a capability-aware program.

## 🧹 No More Impl Suffix
- 🪞 The two foreign imports that still carried an impl suffix — the dom lookup that returns either nothing or just an element, and the environment snapshot capture — were renamed to drop the decorator. The find element by id function is now just find element by id, on both sides of the foreign boundary. The environment capture function is now just capture environment snapshot, with no wrapper between the foreign import and the rest of the program.
- 📖 The project guide gained an explicit rule that complements the existing no abbreviations rule. The new rule says no impl or underscore impl suffix and no jargon decorators on identifiers. It calls out by name the most common offenders such as impl, internal, helper, raw, and unsafe, and it explains that the type system, the module boundary, and the language's foreign import keyword already say what kind of thing each identifier is. The rule applies across every language in the repository, not just PureScript.

## 🧪 New Tests for the New Pattern
- 🔬 The pure test suite gained a new section that exercises every capability test newtype at least once. The fixed clock newtype is verified to hand back the configured clock value. The stub environment newtype is verified to ignore the version argument and return the canned user agent and the canned language. The recording clipboard newtype is verified to record every write in order and preserve the payload exactly. The recording DOM mount newtype is verified to record every mount request. The stateful session newtype is verified to thread reducer updates through pure state so that listening status and total words match what the reducer says after a toggle and an injected transcript.
- 🧪 The original twenty-eight end-to-end Playwright tests covering slices one through five all continue to pass through the capability-routed production code path, which means the refactor is behavior-preserving and the test newtypes are wired correctly.

## 🤖 Continuous Integration
- 🧰 The repository gained a new GitHub Actions workflow named Word Meter PureScript CI. It runs on push and pull request events, but only when changes touch the relevant code under the purs-ps directory, the end-to-end test directory, the bundled PureScript output, the build script, the package manifest, or the workflow file itself. Unrelated changes elsewhere in the repository do not trigger this workflow, which keeps continuous integration fast and focused.
- 🪜 The workflow has two jobs. The first job sets up node, restores the spago cache, builds the bundle, runs the pure PureScript unit test suite, and uploads the bundle as an artifact. The second job depends on the first, sets up node again, restores the spago cache, rebuilds the bundle, installs the chromium playwright browser with its system dependencies, and runs the playwright end-to-end suite. A failed playwright run uploads the report and trace artifacts so the failure can be inspected after the fact.
- 🧷 The end-to-end test script was tweaked so it works from the repository root as well as from the tests directory. The script now passes the configuration path explicitly to playwright, which means continuous integration can invoke it the same way a developer would on their own machine.

## 🧠 Why This Was Worth Doing Now
- 🧬 The capability pattern is the kind of foundation that gets harder to retrofit the longer you put it off. Every new effect that lands inside the raw effect monad is one more thing to refactor later, and the longer the codebase has lived in that shape the more code tends to depend implicitly on being able to call effect-shaped helpers directly.
- 🧪 Doing the lift while there are only five capabilities to think about means the next slice — wake lock, or speech recognition, or any of the remaining feature slices that will introduce side-effecting concerns — can simply add one more capability module beside the existing five, write the production instance, write a deterministic test newtype, and proceed. There is no cleanup tax to pay first.
- 🧹 Tightening the impl-suffix rule at the same time as the lift is the right moment because the lift itself is the event that introduces the most new identifiers at once. If the rule were strengthened later, those identifiers would already have been written under the old rule.

## 📚 Book Recommendations

### 📖 Similar
* Type-Driven Development with Idris by Edwin Brady is relevant because the capability pattern is, at its heart, an exercise in letting types drive the design. The same instinct that says a function returning an integer should not pretend to know about side effects is the instinct that the Idris book teaches end to end, and the capability typeclasses applied here are the PureScript dialect of the same idea.
* Real World Haskell by Bryan O'Sullivan, Don Stewart, and John Goerzen is relevant because the chapters on monad transformers and on programming with monads cover exactly the machinery — reader transformers over the base monad, deriving instances mechanically, lifting through transformer stacks — that the AppM newtype relies on, and the worked examples there match the shape of the production newtype this refactor introduces.

### ↔️ Contrasting
* Out of the Tar Pit by Ben Moseley and Peter Marks is relevant because the paper takes the position that complexity in software systems comes overwhelmingly from accidental state and control, and that the right move is functional relational programming rather than ever more sophisticated abstractions over effects. The capability pattern accepts that effects are a necessary part of any browser-facing program and chooses to civilize them with types; the paper would argue the better move is to push the effects so far to the edge that the capability machinery is mostly unnecessary.

### 🔗 Related
* Practical Foundations for Programming Languages by Robert Harper is relevant because the book covers the type-theoretic underpinnings of polymorphism, typeclasses, and monadic effect typing in a careful, principled way, and a reader who wants to understand why the capability pattern actually delivers honesty of types rather than just feeling like it should will find the foundations they need in those chapters.
