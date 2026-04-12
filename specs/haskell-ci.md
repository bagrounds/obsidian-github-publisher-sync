# Haskell CI

## Overview

The Haskell CI workflow builds, tests, and packages the Haskell automation codebase on every push that touches Haskell source files or the workflow definition itself.

## Trigger

- Push to any branch, or pull request, when files match the path filter
- Path filter: `haskell/**` and `.github/workflows/haskell.yml`
- The `pull_request` trigger ensures Haskell CI appears as a check on PRs that touch Haskell files, even when the latest commit in the PR only changes non-Haskell files
- Concurrency: one run per branch, cancels in-progress runs on new pushes

## Build Environment

- Runs on `ubuntu-latest` inside the `haskell:9.14.1` container (GHC 9.14.1 + Cabal)
- Permissions: `contents: read` only
- `CABAL_DIR` is set to `/github/home/.cabal` to force cabal to use the old-style directory layout, ensuring cache paths match where cabal actually reads and writes packages. Without this, modern cabal (3.10+) defaults to XDG Base Directory paths (e.g. `~/.local/state/cabal/store`), which would not match the `~/.cabal/store` cache path.

## Jobs

The workflow runs two parallel jobs for maximum throughput:

### build-and-test

Builds the project, runs tests, and produces artifacts.

### lint

Runs HLint independently and in parallel with the build.

## Caching Strategy

Three directories are cached for fast incremental builds:

1. `~/.cabal/store` — pre-built dependency packages
2. `~/.cabal/packages` — downloaded Hackage package tarballs and index
3. `haskell/dist-newstyle` — project compilation artifacts (object files, interface files, executables)

Cache key structure (three-tier fallback):

- **Exact key:** hash of `automation.cabal` + `cabal.project` + hash of all source files (`src/**`, `app/**`, `test/**`)
- **First fallback:** hash of `automation.cabal` + `cabal.project` only (dependencies match, project incrementally recompiled)
- **Second fallback:** any previous `cabal-ghc914-` key (best-effort partial cache)

## Update Hackage Index Step

- Runs `cabal update` only when the cached package index directory is missing (i.e. on a cold cache)
- When the cache is warm, the Hackage package index from a previous build is reused, saving ~15 seconds of network time
- If the build step fails (e.g. a new dependency was added that isn't in the cached index), it falls back to running `cabal update` and retrying the build

## Build Step

- `cabal build all -j` — builds library, executables, and test suite in parallel
- If the initial build fails, falls back to refreshing the Hackage index with `cabal update` and retrying
- The `cabal.project` file sets `tests: True` so `cabal build all` includes the test suite and its dependencies, ensuring the test step has nothing to rebuild

## Lint Step

- Runs in a separate parallel job to avoid blocking the build-and-test critical path
- `hlint src/ app/ test/` — runs HLint, the standard Haskell linter, against all source, executable, and test files
- Any HLint hint (warning or suggestion) fails the build
- HLint is installed via `apt-get` inside the container at CI time

## Test Step

- `cabal test --test-show-details=direct` — runs the Tasty test suite with direct output
- Because the build step already compiled the test suite with the same configuration, this step only executes the tests without recompilation

## Artifacts

Two executables are staged and uploaded:

- `run-scheduled` — main automation entry point
- `inject-giscus` — static comment injection tool

Artifact retention: 90 days.

## Compiler Warnings Policy

- The cabal file enables `-Wall`, `-Wcompat`, `-Widentities`, `-Wincomplete-record-updates`, `-Wincomplete-uni-patterns`, `-Wredundant-constraints`, and `-Werror` for all components via the `shared` common stanza
- All source files — library, executables, and tests — must compile warning-free
