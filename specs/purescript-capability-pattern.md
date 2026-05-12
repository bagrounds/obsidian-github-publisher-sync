---
share: true
title: 🪜 PureScript Capability Pattern
---

# 🪜 PureScript Capability Pattern

This is the reference document for the **capability typeclass** pattern as used across this codebase (and as inherited from [`bagrounds/domination`](https://github.com/bagrounds/domination/tree/master/src/Capability)). It is intentionally general — it is **not** specific to the Word Meter port — and every new PureScript feature in this repo should follow it.

## What the pattern is for

PureScript's standard escape hatch for side effects is the `Effect` monad. `Effect` says "this computation talks to the outside world", but it does not say **what part** of the outside world it talks to. That is too coarse:

- A function with type `Effect Number` could be reading the clock, fetching a random number, hitting `localStorage`, calling out to `SpeechRecognition`, or any combination of those.
- Tests cannot intercept any of those effects without monkey-patching globals or shimming the FFI.
- Code review cannot tell, by reading the type alone, what the function actually depends on.

The capability pattern fixes this by replacing `Effect` in production signatures with **a typeclass per side-effecting concern**. The class names the concern, the methods name the operations the concern supports, and you write code against `forall m. Clock m => Storage m => …` rather than against raw `Effect`. This delivers four properties at once:

1. **Honesty of types.** The type of a function tells you exactly which capabilities it consumes. `forall m. Clock m => m Int` tells you it reads the clock and nothing else.
2. **Swappable implementations.** The same code runs against the production `AppM` newtype (which uses real `Effect.Now`, `localStorage`, etc.) and against test newtypes (which return canned values, record calls, throw deterministically, …).
3. **Compositional reasoning.** Capabilities lift through monad transformers (`HalogenM`, `ReaderT`, `ExceptT`, …) by mechanical instances, so callers compose them without each capability knowing about the transformer stack.
4. **Property-testable pure logic.** Once a function's signature is `Clock m => Random m => m a` instead of `Effect a`, you can run that function inside a test monad that returns a deterministic clock and a seeded PRNG, and `quickcheck` it the same way you would a pure function.

The pattern is the PureScript answer to the same problem Haskell's [`mtl`](https://hackage.haskell.org/package/mtl) classes (`MonadReader`, `MonadState`, `MonadError`) solve, and the same problem ZIO's `Has` / Cats Effect's tagless final style solves in Scala. The literature calls it **tagless final** — see [Oleg Kiselyov's collected notes on Tagless Final Encodings](https://okmij.org/ftp/tagless-final/index.html) for the foundational treatment, and [The RIO Monad](https://www.fpcomplete.com/blog/2017/07/the-rio-monad/) for the closely related `ReaderT Env IO` shape this codebase's `AppM` adopts.

## Anatomy of a capability

A capability is one PureScript module per concern. Each module contains:

1. **The typeclass.** A multi-parameter or single-parameter class with a `Monad m =>` superclass and one method per operation.
2. **A lifting instance for `HalogenM`** (and any other transformer the project uses). This lets components written in `HalogenM` use the capability without manual `lift`.
3. **One or more concrete newtypes** that implement the capability. Typically there is `XM` (a `newtype` over `Effect` that runs the capability in isolation, used in tests and in small subprograms) and an instance for the production `AppM`.
4. **A `runXM :: XM ~> Effect`** that strips the wrapper.

The canonical shape, lifted from `bagrounds/domination/src/Capability/Clock.purs`:

```purescript
module Domination.Capability.Clock where

import Prelude

import Control.Monad.Except.Trans (ExceptT)
import Control.Monad.Trans.Class (lift)
import Domination.AppM (AppM)
import Effect.Class (liftEffect)
import FFI as FFI
import Halogen (HalogenM)

class Monad m <= Clock m where
  now :: m Int

instance clockHalogenM :: Clock m => Clock (HalogenM st act slots msg m) where
  now = lift now

instance clockAppM :: Clock AppM where
  now = liftEffect FFI.now

instance clockExceptTString :: Clock m => Clock (ExceptT String m) where
  now = lift now
```

Two things to notice about that example:

- `now :: m Int`, not `now :: Effect Int`. Production code that needs the clock writes `forall m. Clock m => m Foo`, never `forall m. MonadEffect m => m Foo` and never `Effect Foo`. **If a production function calls `Effect.Now.now` directly, the capability has been bypassed.**
- The `HalogenM` and `ExceptT` instances are pure mechanical lifts. Adding a transformer to the stack costs one instance per capability, not a refactor of every consumer.

For a capability with several methods, the same pattern holds — methods become a record of class members, and the test newtype just needs an instance that supplies all of them. `Storage` in the same repo is a good example: `save` and `load` are both class members, both lifted through transformers, both implemented for `AppM`, and both implemented for a `StorageM` newtype that runs against real `localStorage` directly.

## AppM: the production newtype

Every project that adopts the pattern has a single production monad, conventionally called `AppM`. It is a `ReaderT Env Aff` (or `ReaderT Env Effect` for non-async apps) so it can carry shared configuration (HTTP managers, base URLs, the WebSpeech recognizer handle) and naturally interop with Halogen, Aff, and `Effect`:

```purescript
newtype AppM a = AppM (ReaderT Env Aff a)

runAppM :: Env -> AppM ~> Aff
runAppM env (AppM m) = runReaderT m env

derive newtype instance functorAppM :: Functor AppM
derive newtype instance applyAppM :: Apply AppM
derive newtype instance applicativeAppM :: Applicative AppM
derive newtype instance bindAppM :: Bind AppM
derive newtype instance monadAppM :: Monad AppM
derive newtype instance monadEffectAppM :: MonadEffect AppM
derive newtype instance monadAffAppM :: MonadAff AppM
```

`AppM` itself never adds methods. It is a host for capability instances and for the application's configuration. The entry point of the program is the one and only place that calls `runAppM`.

## Why test newtypes exist (and what they look like)

Test newtypes are the whole reason the pattern is worth the indirection. A test newtype is a thin wrapper that implements **only the capabilities the test needs**, with the simplest possible behavior — a constant clock, an in-memory map for storage, a deterministic PRNG, a transcript-replay recognizer. The same production function, with no source change, runs inside that newtype.

A minimal sketch for testing rate calculations under a controlled clock:

```purescript
newtype FixedClockM a = FixedClockM (ReaderT Int Identity a)
derive newtype instance functorFixedClockM :: Functor FixedClockM
derive newtype instance applyFixedClockM :: Apply FixedClockM
derive newtype instance applicativeFixedClockM :: Applicative FixedClockM
derive newtype instance bindFixedClockM :: Bind FixedClockM
derive newtype instance monadFixedClockM :: Monad FixedClockM

instance clockFixedClockM :: Clock FixedClockM where
  now = FixedClockM ask

runFixedClockM :: forall a. Int -> FixedClockM a -> a
runFixedClockM t (FixedClockM m) = runIdentity (runReaderT m t)
```

A test using it is one line: `runFixedClockM 1_700_000_000 someCapabilityFunction`. There is no `unsafeCoerce`, no global stubbing, no Jest-style spy infrastructure — the test gets exact determinism by giving the function a different monad.

For a richer test newtype (`MonadState` over a record of in-memory state, plus instances for several capabilities at once) see `StorageM` in the `bagrounds/domination` reference and the `mtl`-style examples in [`Real World Haskell` chapter 19](http://book.realworldhaskell.org/read/programming-with-monads.html). The PureScript port of the idea is identical except for the syntactic differences in deriving instances.

## Rules this codebase follows

The pattern only pays off if it is applied consistently. These rules are non-negotiable for production PureScript modules in this repo:

1. **Never use `Effect` in a production signature** once the relevant capability exists. If a function reads the clock, its signature is `Clock m => m Foo`, not `Effect Foo` and not `MonadEffect m => m Foo`. The exception is the program entry point that calls `runAppM`.
2. **Never use `MonadEffect m => m Foo` as a workaround.** `MonadEffect` says "this can do *any* effect", which gives back the dishonesty `Effect` had in the first place.
3. **Every capability has at least one test newtype.** A capability with only an `AppM` instance is just `Effect` with extra steps.
4. **Capability modules contain only the capability.** Business logic that happens to be expressed in terms of a capability lives in a feature module. The capability module exports the class, the production instance, the test newtype(s), and the transformer lifts — nothing else.
5. **Capabilities are added when a feature needs them, not speculatively.** A slice that does not need persistence does not introduce `Storage`. This keeps each PR small and keeps unused machinery out of the bundle.
6. **No `Impl` suffix on FFI imports.** PureScript's `foreign import` already says it is the FFI binding — the `Impl` suffix is enterprise C# habit and violates the no-abbreviations rule. The FFI import is named exactly what the module exposes; if a wrapper is needed it gets a different name (e.g. `nowMs` vs `nowMsAsInt`).

## How to add a new capability

When a slice introduces a new effectful concern:

1. Create `purs-ps/src/<Project>/Capability/<Name>.purs` with the class, the `HalogenM` lift (if Halogen is in use), the `AppM` instance, and at least one test newtype with `runXM`.
2. Add the matching FFI module under `purs-ps/src/<Project>/FFI/<Name>.purs` if any platform binding is needed. The FFI binding name matches what the capability exports; no `Impl` suffix.
3. Refactor the calling code to take `<Name> m => …` instead of `Effect …`.
4. Update `specs/word-meter-purescript-port.md` (or the matching project spec) to list the new capability.
5. Add `spago test` unit tests that run the calling code under the test newtype and assert exact behavior.

If two capabilities share state (e.g. `Clock` and `Random` both backed by a single `Effect.Ref`), each still gets its own class — the **classes** are the API surface; the **instances** are free to share state under the hood.

## Further reading

- [`bagrounds/domination/src/Capability`](https://github.com/bagrounds/domination/tree/master/src/Capability) — the working reference implementation that this doc is derived from. `Clock`, `Storage`, `Log`, `Random`, `Timer`, `Uuid`, `Audio`, `Broadcast`, `WireCodec`, and `Dom` are all worth reading.
- [`bagrounds/domination/src/AppM.purs`](https://github.com/bagrounds/domination/blob/master/src/AppM.purs) — the canonical `AppM` newtype.
- [Real World Halogen — Capability-driven design](https://thomashoneyman.com/guides/real-world-halogen/) by Thomas Honeyman — the canonical PureScript / Halogen write-up of this pattern, with a worked example app.
- [Don't Use Typeclasses To Define Default Values](https://www.parsonsmatt.org/2017/04/09/dont_use_typeclasses_to_define_default_values.html) by Matt Parsons — useful counter-pressure on when *not* to reach for a typeclass.
- [The ReaderT Design Pattern](https://www.fpcomplete.com/blog/2017/06/readert-design-pattern/) by Michael Snoyman — Haskell-side companion to the `AppM = ReaderT Env Aff` choice.
- [Tagless Final Encodings](https://okmij.org/ftp/tagless-final/index.html) by Oleg Kiselyov — foundational notes on the encoding the pattern relies on.

## When *not* to use the pattern

This pattern is the right default for **anything that crosses the FFI boundary or talks to the runtime**. It is the wrong choice for:

- **Pure data manipulation.** Word counting, rate math, transcript parsing, JSON encoding — these stay as pure functions returning `a`, not `m a`. Lifting pure logic into a capability monad just to "be consistent" is a smell.
- **Internal helpers that are already in a capability context.** Inside a `Clock m => …` function, a small `let`-bound helper that does not itself need a capability stays unparameterized.
- **One-shot scripts.** A throwaway CLI script can live in `Effect` directly. The pattern pays off where the same code is exercised by both production and tests, not in code that has only one runtime.

The rule of thumb: **the moment a function's behavior depends on the outside world and you want to test it, lift it onto a capability.** Until then, leave it pure.
