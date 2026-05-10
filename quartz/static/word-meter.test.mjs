// Tests for quartz/static/word-meter.js.
//
// word-meter.js is a browser IIFE that wraps a SpeechRecognition front-end. We
// load the source into a Node `vm` sandbox with a minimal DOM stub and exercise
// the production code paths via the built-in `__WM_TEST_HOOK__` test hook,
// which exposes simulateResult / getState / reset.
//
// The Android Chrome scenarios reproduce the overcount bug reported in
// https://github.com/bagrounds/obsidian-github-publisher-sync/issues/6897:
// continuous mode + interimResults emits each refinement of one utterance as
// a separate finalized SpeechRecognitionResult containing the full cumulative
// transcript.
import test, { describe } from "node:test"
import assert from "node:assert"
import { readFileSync } from "node:fs"
import vm from "node:vm"
import path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const wordMeterSource = readFileSync(path.join(here, "word-meter.js"), "utf8")

const stubElement = () => {
  const node = {
    id: "",
    style: {},
    textContent: "",
    innerHTML: "",
    setAttribute: () => {},
    appendChild: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
  }
  return node
}

const loadWordMeter = () => {
  const sandbox = {
    document: {
      getElementById: () => null,
      createElement: stubElement,
      addEventListener: () => {},
      removeEventListener: () => {},
    },
    setInterval: () => 0,
    clearInterval: () => {},
    setTimeout: () => 0,
    clearTimeout: () => {},
    Date,
    Math,
    Object,
    Array,
    String,
    Number,
    Boolean,
    JSON,
    isFinite,
    console,
  }
  sandbox.window = sandbox
  sandbox.window.__WM_TEST_HOOK__ = true
  vm.createContext(sandbox)
  vm.runInContext(wordMeterSource, sandbox)
  return sandbox.window.__wordMeter
}

describe("Word Meter — finalized result integration", () => {
  test("counts a single final result correctly", () => {
    const wm = loadWordMeter()
    wm.simulateResult("twinkle twinkle little star", true)
    assert.strictEqual(wm.getState().totalWords, 4)
  })

  test("interim results are not counted", () => {
    const wm = loadWordMeter()
    wm.simulateResult("twinkle", false)
    wm.simulateResult("twinkle twinkle", false)
    wm.simulateResult("twinkle twinkle little star", true)
    assert.strictEqual(wm.getState().totalWords, 4)
  })

  test("Android Chrome cumulative refinement: 4-word phrase counts as 4", () => {
    // Reproduces the screenshot in issue #6897 where each refinement is
    // emitted as a NEW finalized result with the full cumulative transcript.
    // Before the fix, this counted 17. The expected count is 4.
    const wm = loadWordMeter()
    const refinements = [
      "twinkle",
      "twinkle twinkle",
      "Twinkle",
      "Twinkle Twinkle",
      "Twinkle Twinkle Little",
      "Twinkle Twinkle Little Star",
      "twinkle twinkle little star",
      "twinkle twinkle little star",
    ]
    refinements.forEach((text) => wm.simulateResult(text, true))
    assert.strictEqual(wm.getState().totalWords, 4)
  })

  test("Android Chrome cumulative refinement: 10-word phrase counts as 10", () => {
    // Before the fix this counted 99; the expected count is 10.
    const wm = loadWordMeter()
    const refinements = [
      "twinkle",
      "twinkle twinkle",
      "twinkle twinkle little",
      "twinkle twinkle little star",
      "twinkle twinkle little star how",
      "twinkle twinkle little star how I",
      "twinkle twinkle little star how I wonder",
      "twinkle twinkle little star how I wonder what",
      "twinkle twinkle little star how I wonder what you",
      "twinkle twinkle little star how I wonder what you are",
      "twinkle twinkle little star how I wonder what you are",
    ]
    refinements.forEach((text) => wm.simulateResult(text, true))
    assert.strictEqual(wm.getState().totalWords, 10)
  })

  test("distinct (non-overlapping) utterances accumulate independently", () => {
    const wm = loadWordMeter()
    wm.simulateResult("hello world", true)
    wm.simulateResult("how are you", true)
    assert.strictEqual(wm.getState().totalWords, 5)
  })

  test("an exact-duplicate finalized result does not double-count", () => {
    const wm = loadWordMeter()
    wm.simulateResult("hello world", true)
    wm.simulateResult("hello world", true)
    assert.strictEqual(wm.getState().totalWords, 2)
  })

  test("captions panel shows the latest refinement once, not every variant", () => {
    const wm = loadWordMeter()
    const refinements = [
      "twinkle",
      "twinkle twinkle",
      "twinkle twinkle little",
      "twinkle twinkle little star",
    ]
    refinements.forEach((text) => wm.simulateResult(text, true))
    const captions = wm.getState().captions
    assert.strictEqual(captions.length, 1)
    assert.strictEqual(captions[0], "twinkle twinkle little star")
  })

  test("an earlier-snapshot final result is ignored, not re-counted", () => {
    // Some recognizers re-emit a shorter snapshot of an utterance after they
    // have already emitted the full one. We must not treat that as a brand
    // new utterance.
    const wm = loadWordMeter()
    wm.simulateResult("hello world how are you", true)
    wm.simulateResult("hello world", true)
    assert.strictEqual(wm.getState().totalWords, 5)
  })
})
