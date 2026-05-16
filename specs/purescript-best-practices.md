---
share: true
title: 🟣 PureScript Best Practices
---

# 🟣 PureScript Best Practices

Research findings on PureScript design patterns and idioms, compiled as a reference for the Word Meter PureScript port. Observations are drawn from the PureScript community, the `purescript-halogen` and `purescript-contrib` codebases, and domain-driven design principles aligned with this repo's engineering standards.

## Type system

### Newtypes over raw primitives

Wrap domain concepts in newtypes rather than passing raw `String`, `Int`, or `Number` through multiple function boundaries. A newtype costs nothing at runtime (it is erased by the compiler) but prevents mixing values that share a structural representation.

```purescript
-- Avoid: easy to pass the wrong Number
startRecognition :: String -> Number -> m Unit

-- Prefer: each concept is its own type
newtype Locale = Locale String
newtype Timestamp = Timestamp Number
startRecognition :: Locale -> Timestamp -> m Unit
```

### Closed sets as ADTs

Model any value that comes from a fixed, known set as a sum type with one constructor per variant. Never use `String` for a closed set; the compiler cannot exhaustiveness-check strings.

```purescript
-- Avoid
type RecognitionPath = String  -- "on-device" | "cloud"

-- Prefer
data RecognitionPath = OnDevicePath | CloudPath
```

Adding `derive instance Enum RecognitionPath` and `derive instance Bounded RecognitionPath` enables exhaustive tests that iterate every constructor automatically.

### `NonEmpty` for non-empty guarantees

When a function genuinely requires at least one element, express that in the type. A runtime `Array.head` followed by `fromMaybe` is a code smell; use `NonEmpty Array` to push the invariant to the call site.

### Smart constructors for validated newtypes

When a newtype carries an invariant (e.g. a threshold between 0 and 1, a non-negative duration), hide the constructor and expose a smart constructor that returns `Maybe` or `Either` on invalid input.

## Modules

### One concept per module

Each module should own exactly one domain concept: its types, its constants, and the pure functions over those types. Avoid grouping unrelated types into a shared module just because they share a structural pattern (e.g. a `Constants` module for all configuration values, or a `Types` module for all types).

**Test of good module design:** if a consumer needed only one feature, could they import a single module and get everything they need? If deleting a feature requires changes to an unrelated module, the module boundary is wrong.

### No re-exports

Each module should only export symbols it defines. Consumers should import directly from the module that defines the symbol. Re-exporting symbols from sub-modules to create a facade adds indirection and hides where functionality lives.

### Qualified imports for feature modules

Import feature-focused modules qualified so that the namespace becomes part of the name:

```purescript
import qualified WordMeter.Recognition.Path as RecognitionPath

-- Call site reads naturally:
RecognitionPath.processLocallyFor path
```

Reserve unqualified imports for truly shared types (like `Maybe`, `Effect`, `Prelude`) and for modules where field names do not collide.

### Vertical organization over horizontal

Organize code by feature (domain concept), not by code artifact kind. A module like `WordMeter.Capability.Recognition` that contains the typeclass, the `AppM` instance, the test newtype, and its event ADT is better than separate `Capability`, `Instance`, and `TestDouble` modules that force a consumer to import three modules to understand one feature.

## Effects and purity

### Functional core, imperative shell

Keep domain logic in pure functions; push `Effect` to the edges. A function should only have `Effect` in its signature if it truly reads mutable state, performs I/O, or triggers a side effect. Pure functions are easier to test (no capability constraints needed), easier to reason about, and compose freely.

### Capability typeclasses over `Effect` constraints

When a function needs an effect (clock, clipboard, DOM mount, storage), express the requirement as a capability typeclass constraint rather than reaching for `Effect` directly. This keeps orchestration code polymorphic over the implementation, enables test newtypes that record or stub the capability, and makes it clear from the type what the function can actually do.

```purescript
-- Avoid: couples to concrete implementation
persistNow :: Effect Unit

-- Prefer: works with any monad that has Storage
persistNow :: forall m. Storage m => m Unit
```

### `ReaderT` for shared context

When several functions need the same read-only environment (configuration, `Ref`s, system handles), thread it via `ReaderT`. This avoids threading individual parameters and keeps the environment extensible.

### Explicit error types over `Maybe` / exceptions

Prefer `Either` with a domain-specific error ADT over returning `Maybe` (which loses the error reason) or throwing exceptions (which bypass the type system). Reserve `Maybe` for truly optional values where the absent case is not an error.

```purescript
-- Avoid: caller cannot distinguish "not found" from "parse error"
load :: String -> Effect (Maybe Session)

-- Prefer: every failure mode is named
data LoadError = StorageUnavailable | ParseError JsonDecodeError
load :: String -> Effect (Either LoadError Session)
```

## Reducer pattern

### Exhaustive pattern matching as a discipline

The `Action` / `reduce` pattern benefits from exhaustive case coverage of every action. PureScript will warn on non-exhaustive patterns, so the compiler acts as a checklist for new actions.

When a new action is added that requires persistence, the compiler warning on `persistAfterAction` (or equivalent exhaustive dispatch) forces the author to make an explicit decision. This is a feature, not a burden.

### Separate what changes from what side-effects happen

The reducer (`reduce`) should be a pure function from `(Action, Session) -> Session`. Side effects triggered by an action (persist, render, record wake-lock event) belong in the orchestrator layer (`Main`), not in the reducer.

### Avoid boolean flags for multi-state conditions

When a field can be in more than two meaningful states, model it as an ADT rather than a `Boolean` combined with another `String`.

```purescript
-- Avoid: what does false + "" mean vs false + "error"?
wakeLockHeld :: Boolean
keepAwakeStatus :: String

-- Prefer: one type covers all states
data WakeLockState = Idle | Held | Failed String
```

## Testing

### Pure-by-default for unit tests

Every pure function (reducer cases, formatters, classifiers) should be unit-tested without any `Effect` or capability constraints. The test suite should run synchronously in a few milliseconds for the pure layer.

### Test newtypes for capabilities

Each capability typeclass should have a deterministic test newtype that records or stubs the effect. This allows orchestration functions in `Main` to be tested as pure logic against known inputs and outputs, without touching the browser or filesystem.

### Property-based tests for invariants

Pure functions with clear algebraic properties (e.g. `reduce` is referentially transparent, `formatDurationMs` is monotone, `ratePerMinute` is zero for zero words) are candidates for property-based tests via `purescript-quickcheck` or `purescript-spec-quickcheck`.

## PureScript-specific idioms

### `case _` for cleaner function bodies

PureScript's `case _` syntax eliminates the need for a named argument when the function body is a single `case` expression:

```purescript
-- Verbose
classifyCode code = case code of
  "not-allowed" -> NotAllowed
  ...

-- Idiomatic
classifyCode = case _ of
  "not-allowed" -> NotAllowed
  ...
```

### Point-free style with `>>>` and `<<<`

Use function composition (`>>>` for left-to-right, `<<<` for right-to-left) to express pipelines without naming intermediate values. The `normalizeTranscript` and `collapseWhitespaceToSpace` functions in this codebase already use this style effectively.

### `where` clauses for local helpers

Local helper bindings that are only meaningful in the context of a parent function belong in a `where` clause rather than at module level. This keeps the module's public API clean and signals to readers that the helper is not intended for external use.

### Deriving instances

Use `derive instance` and `derive newtype instance` to avoid boilerplate `Eq`, `Show`, `Ord`, and typeclass forwarding. Where the derived `Show` is too verbose, write a hand-rolled instance or a `render` function and document the intent.

## Naming conventions (aligned with repo standards)

- No abbreviations: `nowMilliseconds` not `nowMs`, `durationMilliseconds` not `durationMs`.
- No Hungarian notation: the type system says what a value is; the name says what it means.
- No `Impl` / `_impl` suffixes on FFI bindings.
- No single-letter variables unless the function is a genuinely abstract combinator (category-theory level).
- Qualified imports for feature modules; the qualifier folds the namespace into the call site.
