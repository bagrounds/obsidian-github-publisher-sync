# Haskell CI

## Overview

The Haskell CI workflow builds, tests, and packages the Haskell automation codebase on every push that touches Haskell source files or the workflow definition itself.

## Trigger

- Push to any branch
- Path filter: `haskell/**` and `.github/workflows/haskell.yml`
- Concurrency: one run per branch, cancels in-progress runs on new pushes

## Build Environment

- Runs on `ubuntu-latest` inside the `haskell:9.14.1` container (GHC 9.14.1 + Cabal)
- Permissions: `contents: read` only

## Caching Strategy

Two directories are cached for fast incremental builds:

1. `~/.cabal/store` — pre-built dependency packages
2. `haskell/dist-newstyle` — project compilation artifacts (object files, interface files, executables)

Cache key structure (three-tier fallback):

- **Exact key:** hash of `automation.cabal` + hash of all source files (`src/**`, `app/**`, `test/**`)
- **First fallback:** hash of `automation.cabal` only (dependencies match, project incrementally recompiled)
- **Second fallback:** any previous `cabal-ghc914-` key (best-effort partial cache)

## Build Step

- `cabal update` — refreshes the Hackage package index
- `cabal build all -j --ghc-options="-Werror"` — builds library, executables, and test suite in parallel with warnings treated as errors

## Lint Step

- `hlint src/ app/ test/` — runs HLint, the standard Haskell linter, against all source, executable, and test files
- Any HLint hint (warning or suggestion) fails the build
- HLint is installed via `apt-get` inside the container at CI time

## Test Step

- `cabal test --test-show-details=direct` — runs the Tasty test suite with direct output

## Artifacts

Two executables are staged and uploaded:

- `run-scheduled` — main automation entry point
- `inject-giscus` — static comment injection tool

Artifact retention: 90 days.

## Compiler Warnings Policy

- The cabal file enables `-Wall`, `-Wcompat`, `-Widentities`, `-Wincomplete-record-updates`, `-Wincomplete-uni-patterns`, and `-Wredundant-constraints`
- CI enforces `-Werror` so any warning is a build failure
- All source files must compile warning-free
