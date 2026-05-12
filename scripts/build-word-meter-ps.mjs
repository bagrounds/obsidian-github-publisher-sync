#!/usr/bin/env node
// Build script for the PureScript Word Meter bundle.
//
// Runs `spago bundle` against `purs-ps/` and writes the resulting IIFE
// to `quartz/static/word-meter-ps.js`. The legacy `word-meter.js`
// stays in place until the port is complete (see the PR description
// and `specs/word-meter-purescript-port.md`).
//
// Honors a few env knobs so the same script works locally, in CI, and
// from the Playwright fixture in `tests/e2e/`:
//
//   PS_MINIFY=1   pass --minify to spago bundle
//   PS_OUTFILE    override the destination path (relative or absolute)

import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import path from "node:path"

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(scriptDirectory, "..")
const pursPsRoot = path.join(repoRoot, "purs-ps")
const defaultOutfile = path.join(repoRoot, "quartz", "static", "word-meter-ps.js")
const outfile = process.env.PS_OUTFILE
  ? path.resolve(process.env.PS_OUTFILE)
  : defaultOutfile

const args = [
  "bundle",
  "--bundle-type",
  "app",
  "--platform",
  "browser",
  "--module",
  "WordMeter.Main",
  "--outfile",
  outfile,
]
if (process.env.PS_MINIFY === "1") args.push("--minify")

const result = spawnSync("npx", ["--prefix", repoRoot, "spago", ...args], {
  cwd: pursPsRoot,
  stdio: "inherit",
})

process.exit(result.status ?? 1)
