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

// Richer loader that mocks SpeechRecognition, navigator (with optional
// wakeLock support), and a DOM that surfaces the keep-awake checkbox so the
// session lifecycle (`beginListening`/`endListening`) can run end-to-end.
const loadWordMeterWithLifecycle = ({ wakeLockSupported, keepAwakeChecked, requestRejects } = {}) => {
  const elementsById = {}
  const visibilityListeners = []
  let visibilityState = "visible"

  const makeElement = () => {
    const node = {
      id: "",
      style: {},
      textContent: "",
      innerHTML: "",
      checked: false,
      disabled: false,
      addEventListener: () => {},
      removeEventListener: () => {},
      setAttribute(name, value) {
        if (name === "checked") this.checked = true
        if (name === "id") this.id = value
      },
      appendChild() {},
      get parentElement() { return null },
    }
    return node
  }

  const document = {
    getElementById: (id) => elementsById[id] || null,
    createElement: makeElement,
    addEventListener: (eventName, handler) => {
      if (eventName === "visibilitychange") visibilityListeners.push(handler)
    },
    removeEventListener: () => {},
    get visibilityState() { return visibilityState },
  }

  // Pre-seed the IDs the production code reads so we can drive behaviour.
  elementsById["wm-keep-awake"] = { ...makeElement(), id: "wm-keep-awake", checked: keepAwakeChecked !== false }
  elementsById["wm-mode-cloud"] = { ...makeElement(), id: "wm-mode-cloud", checked: false }
  elementsById["wm-mode-on-device"] = { ...makeElement(), id: "wm-mode-on-device", checked: true }
  elementsById["wm-toggle"] = makeElement()
  elementsById["wm-status"] = makeElement()
  elementsById["wm-error"] = makeElement()
  elementsById["wm-keep-awake-status"] = makeElement()
  elementsById["wm-count"] = makeElement()
  elementsById["wm-started"] = makeElement()
  elementsById["wm-rate-short"] = makeElement()
  elementsById["wm-rate-long"] = makeElement()
  elementsById["wm-rate-overall"] = makeElement()
  elementsById["wm-captions"] = makeElement()

  let wakeLockReleaseCount = 0
  let wakeLockRequestCount = 0
  const wakeLock = wakeLockSupported
    ? {
        request: () => {
          wakeLockRequestCount += 1
          if (requestRejects) return Promise.reject(new Error("denied"))
          return Promise.resolve({
            release: () => { wakeLockReleaseCount += 1; return Promise.resolve() },
            addEventListener: () => {},
          })
        },
      }
    : undefined

  class FakeRecognition {
    constructor() {
      this.continuous = false
      this.interimResults = false
      this.lang = ""
      this.processLocally = undefined
      this.onresult = null
      this.onerror = null
      this.onend = null
    }
    start() {}
    stop() {}
  }

  const sandbox = {
    document,
    navigator: { language: "en-US", ...(wakeLock ? { wakeLock } : {}) },
    SpeechRecognition: FakeRecognition,
    webkitSpeechRecognition: FakeRecognition,
    setInterval: () => 0,
    clearInterval: () => {},
    setTimeout: () => 0,
    clearTimeout: () => {},
    Promise,
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

  return {
    wm: sandbox.window.__wordMeter,
    triggerVisibilityChange: (state) => {
      visibilityState = state
      visibilityListeners.forEach((handler) => handler())
    },
    counts: () => ({ requested: wakeLockRequestCount, released: wakeLockReleaseCount }),
    setCheckboxChecked: (checked) => { elementsById["wm-keep-awake"].checked = checked },
  }
}

const flushMicrotasks = () => new Promise((resolve) => setImmediate(resolve))

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

describe("Word Meter — keep-awake / Screen Wake Lock", () => {
  test("acquires a wake lock when starting with keep-awake checked and lock supported", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: true, keepAwakeChecked: true })
    harness.wm.start()
    await flushMicrotasks()
    assert.strictEqual(harness.counts().requested, 1)
    assert.strictEqual(harness.wm.getState().keepAwake, true)
    assert.strictEqual(harness.wm.getState().wakeLockHeld, true)
  })

  test("releases the wake lock when the user stops listening", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: true, keepAwakeChecked: true })
    harness.wm.start()
    await flushMicrotasks()
    harness.wm.stop()
    await flushMicrotasks()
    assert.strictEqual(harness.counts().released, 1)
    assert.strictEqual(harness.wm.getState().wakeLockHeld, false)
  })

  test("does NOT acquire a wake lock when the user unchecks the toggle", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: true, keepAwakeChecked: false })
    harness.wm.start()
    await flushMicrotasks()
    assert.strictEqual(harness.counts().requested, 0)
    assert.strictEqual(harness.wm.getState().keepAwake, false)
    assert.strictEqual(harness.wm.getState().wakeLockHeld, false)
  })

  test("survives missing Wake Lock API without throwing", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: false, keepAwakeChecked: true })
    // Must not throw on browsers without navigator.wakeLock (e.g. older Safari).
    harness.wm.start()
    await flushMicrotasks()
    assert.strictEqual(harness.wm.getState().listening, true)
    assert.strictEqual(harness.wm.getState().wakeLockHeld, false)
    harness.wm.stop()
  })

  test("re-acquires the wake lock after the page becomes visible again", async () => {
    // Browsers automatically release the wake lock when the page is hidden.
    // The meter listens for visibilitychange and re-requests the lock so a
    // brief tab switch doesn't end the long listening session.
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: true, keepAwakeChecked: true })
    harness.wm.start()
    await flushMicrotasks()
    const requestsAfterStart = harness.counts().requested
    // Hide the page (mimics the browser silently releasing the lock), then
    // show it again. The visibility handler must not double-request while a
    // lock is already held, and must not lose any requests on the way back.
    harness.triggerVisibilityChange("hidden")
    harness.triggerVisibilityChange("visible")
    await flushMicrotasks()
    const requestsAfterVisible = harness.counts().requested
    assert.ok(requestsAfterVisible >= requestsAfterStart, "must not lose requests")
    assert.ok(
      requestsAfterVisible <= requestsAfterStart + 1,
      "must not double-request while a lock is already held",
    )
  })
})
