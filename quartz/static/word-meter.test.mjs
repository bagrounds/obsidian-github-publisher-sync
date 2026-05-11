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

const loadWordMeter = ({ localStorageStore } = {}) => {
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
  if (localStorageStore) {
    const store = localStorageStore
    sandbox.localStorage = {
      getItem: (key) => (key in store ? store[key] : null),
      setItem: (key, value) => { store[key] = String(value) },
      removeItem: (key) => { delete store[key] },
    }
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
const loadWordMeterWithLifecycle = ({ wakeLockSupported, keepAwakeChecked, requestRejects, localStorageStore } = {}) => {
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
  if (localStorageStore) {
    const store = localStorageStore
    sandbox.localStorage = {
      getItem: (key) => (key in store ? store[key] : null),
      setItem: (key, value) => { store[key] = String(value) },
      removeItem: (key) => { delete store[key] },
    }
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

// Harness for the on-device language-pack lifecycle. Mirrors loadWordMeterWithLifecycle
// but exposes the static `available` and `install` methods that Chromium uses
// to download on-device speech recognition models. Without these calls, the
// real browser rejects `start()` with `language-not-supported` on the very
// first attempt — the bug this suite locks down.
const loadWordMeterWithLanguagePack = ({ availability, installResult, exposeStaticApi = true } = {}) => {
  const elementsById = {}
  const makeElement = () => ({
    id: "",
    style: {},
    textContent: "",
    innerHTML: "",
    checked: false,
    disabled: false,
    addEventListener: () => {},
    removeEventListener: () => {},
    setAttribute() {},
    appendChild() {},
    get parentElement() { return null },
  })
  for (const id of [
    "wm-keep-awake", "wm-mode-cloud", "wm-mode-on-device", "wm-toggle", "wm-status",
    "wm-error", "wm-keep-awake-status", "wm-count", "wm-started", "wm-rate-short",
    "wm-rate-long", "wm-rate-overall", "wm-captions",
  ]) {
    elementsById[id] = { ...makeElement(), id }
  }
  // The host element drives init(): when present, the script captures an
  // environment snapshot and wires up the diagnostics panel. Without it,
  // init() returns early and diagnostics never populate.
  elementsById["word-meter"] = { ...makeElement(), id: "word-meter" }
  elementsById["wm-diagnostics-content"] = { ...makeElement(), id: "wm-diagnostics-content" }
  // On-device mode is the default per the production code.
  elementsById["wm-mode-on-device"].checked = true
  elementsById["wm-keep-awake"].checked = false

  const document = {
    getElementById: (id) => elementsById[id] || null,
    createElement: makeElement,
    addEventListener: () => {},
    removeEventListener: () => {},
    visibilityState: "visible",
  }

  const events = { startCalled: 0, availableCalls: [], installCalls: [] }

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
    start() { events.startCalled += 1 }
    stop() {}
  }
  if (exposeStaticApi) {
    FakeRecognition.available = (options) => {
      events.availableCalls.push(options)
      const value = availability ?? "available"
      return typeof value === "function" ? Promise.resolve(value()) : Promise.resolve(value)
    }
    FakeRecognition.install = (options) => {
      events.installCalls.push(options)
      const value = installResult ?? true
      return typeof value === "function" ? Promise.resolve(value()) : Promise.resolve(value)
    }
  }

  const sandbox = {
    document,
    navigator: { language: "en-US" },
    SpeechRecognition: FakeRecognition,
    webkitSpeechRecognition: FakeRecognition,
    setInterval: () => 0,
    clearInterval: () => {},
    setTimeout: () => 0,
    clearTimeout: () => {},
    Promise,
    Date, Math, Object, Array, String, Number, Boolean, JSON, isFinite,
    console,
  }
  sandbox.window = sandbox
  sandbox.window.__WM_TEST_HOOK__ = true
  vm.createContext(sandbox)
  vm.runInContext(wordMeterSource, sandbox)
  return {
    wm: sandbox.window.__wordMeter,
    events,
    errorBannerText: () => elementsById["wm-error"].textContent,
    statusText: () => elementsById["wm-status"].textContent,
    selectCloud: () => {
      elementsById["wm-mode-cloud"].checked = true
      elementsById["wm-mode-on-device"].checked = false
    },
  }
}

describe("Word Meter — on-device language pack", () => {
  test("starts immediately when the language pack is already available", async () => {
    const harness = loadWordMeterWithLanguagePack({ availability: "available" })
    await harness.wm.start()
    assert.strictEqual(harness.events.availableCalls.length, 1)
    assert.deepStrictEqual(JSON.parse(JSON.stringify(harness.events.availableCalls[0])), {
      langs: ["en-US"], processLocally: true,
    })
    assert.strictEqual(harness.events.installCalls.length, 0, "no install needed when already available")
    assert.strictEqual(harness.events.startCalled, 1)
    assert.strictEqual(harness.wm.getState().listening, true)
    assert.strictEqual(harness.errorBannerText(), "")
  })

  test("downloads the language pack and then starts when it is downloadable", async () => {
    // Reproduces the bug reported in the issue: on Android Chrome the on-device
    // path failed because the page never asked the browser to download the
    // language pack. With the fix, install() is called and start() proceeds.
    const harness = loadWordMeterWithLanguagePack({
      availability: "downloadable",
      installResult: true,
    })
    await harness.wm.start()
    assert.strictEqual(harness.events.installCalls.length, 1)
    assert.deepStrictEqual(JSON.parse(JSON.stringify(harness.events.installCalls[0])), {
      langs: ["en-US"], processLocally: true,
    })
    assert.strictEqual(harness.events.startCalled, 1, "start() runs after install succeeds")
    assert.strictEqual(harness.wm.getState().listening, true)
    assert.strictEqual(harness.errorBannerText(), "")
  })

  test("downloading state also triggers install and ultimately starts", async () => {
    const harness = loadWordMeterWithLanguagePack({
      availability: "downloading",
      installResult: true,
    })
    await harness.wm.start()
    assert.strictEqual(harness.events.installCalls.length, 1)
    assert.strictEqual(harness.events.startCalled, 1)
  })

  test("does not call start when the language pack install fails", async () => {
    const harness = loadWordMeterWithLanguagePack({
      availability: "downloadable",
      installResult: false,
    })
    await harness.wm.start()
    assert.strictEqual(harness.events.installCalls.length, 1)
    assert.strictEqual(harness.events.startCalled, 0)
    assert.match(harness.errorBannerText(), /download/i)
    assert.strictEqual(harness.wm.getState().listening, false)
  })

  test("does not call start (and does not attempt install) when on-device is unavailable", async () => {
    const harness = loadWordMeterWithLanguagePack({ availability: "unavailable" })
    await harness.wm.start()
    assert.strictEqual(harness.events.installCalls.length, 0)
    assert.strictEqual(harness.events.startCalled, 0)
    assert.match(harness.errorBannerText(), /not available/i)
    assert.strictEqual(harness.wm.getState().listening, false)
  })

  test("older browsers without the static API still start (fallback behavior)", async () => {
    const harness = loadWordMeterWithLanguagePack({ exposeStaticApi: false })
    await harness.wm.start()
    assert.strictEqual(harness.events.availableCalls.length, 0)
    assert.strictEqual(harness.events.installCalls.length, 0)
    assert.strictEqual(harness.events.startCalled, 1, "must not regress for browsers predating the install API")
    assert.strictEqual(harness.wm.getState().listening, true)
  })

  test("cloud mode skips the availability check entirely", async () => {
    const harness = loadWordMeterWithLanguagePack({ availability: "unavailable" })
    harness.selectCloud()
    await harness.wm.start()
    assert.strictEqual(harness.events.availableCalls.length, 0, "cloud mode must not poke the on-device API")
    assert.strictEqual(harness.events.installCalls.length, 0)
    assert.strictEqual(harness.events.startCalled, 1)
    assert.strictEqual(harness.wm.getState().listening, true)
  })

  test("stopping while the install is in flight prevents the eventual start", async () => {
    let resolveInstall
    const installPending = new Promise((resolve) => { resolveInstall = resolve })
    const harness = loadWordMeterWithLanguagePack({
      availability: "downloadable",
      installResult: () => installPending,
    })
    // Kick off start (do not await — install is intentionally pending).
    const startPromise = harness.wm.start()
    await flushMicrotasks()
    assert.strictEqual(harness.events.installCalls.length, 1, "install was kicked off")
    assert.strictEqual(harness.events.startCalled, 0, "start() must not run before install resolves")
    // User changes their mind and hits stop while the download is in flight.
    harness.wm.stop()
    assert.strictEqual(harness.wm.getState().listening, false)
    // Install completes after the stop. start() must NOT be called now.
    resolveInstall(true)
    await startPromise
    assert.strictEqual(harness.events.startCalled, 0, "stop must cancel the pending start")
    assert.strictEqual(harness.wm.getState().listening, false)
  })
})

describe("Word Meter — diagnostics and version", () => {
  test("exposes a build version string and an environment snapshot at init", () => {
    const harness = loadWordMeterWithLanguagePack({ availability: "available" })
    const state = harness.wm.getState()
    assert.ok(typeof state.version === "string" && state.version.length > 0)
    assert.ok(state.diagnosticsSnapshot, "snapshot is captured at init")
    assert.strictEqual(state.diagnosticsSnapshot.hasSpeechRecognition, true)
    assert.strictEqual(state.diagnosticsSnapshot.hasOnDeviceAvailable, true)
    assert.strictEqual(state.diagnosticsSnapshot.hasOnDeviceInstall, true)
  })

  test("captures missing on-device API support in the snapshot", () => {
    const harness = loadWordMeterWithLanguagePack({ exposeStaticApi: false })
    const snapshot = harness.wm.getState().diagnosticsSnapshot
    assert.strictEqual(snapshot.hasOnDeviceAvailable, false)
    assert.strictEqual(snapshot.hasOnDeviceInstall, false)
  })

  test("records a diagnostic entry for each step of the on-device pre-flight", async () => {
    const harness = loadWordMeterWithLanguagePack({
      availability: "downloadable",
      installResult: true,
    })
    await harness.wm.start()
    const labels = harness.wm.getState().diagnosticsEntries.map((entry) => entry.label)
    assert.ok(labels.some((label) => label.includes("beginListening")), `expected beginListening; got ${labels.join(" | ")}`)
    assert.ok(labels.some((label) => label.includes("available()")))
    assert.ok(labels.some((label) => label.includes("install()")))
    assert.ok(labels.some((label) => label.includes("recognition.start()")))
  })

  test("records the recognition error code when onerror fires", async () => {
    const harness = loadWordMeterWithLanguagePack({ availability: "available" })
    await harness.wm.start()
    harness.wm.simulateError("language-not-supported")
    const errorEntry = harness.wm.getState().diagnosticsEntries
      .find((entry) => entry.label === "recognition.onerror")
    assert.ok(errorEntry, "an onerror diagnostic was recorded")
    assert.match(errorEntry.detail, /language-not-supported/)
  })
})

describe("Word Meter — persistence across page loads", () => {
  test("totals and intervals survive a simulated reload via shared localStorage", () => {
    // Two separate sandboxes share the same backing store so that a reload
    // (a fresh sandbox loading word-meter.js again) sees the previous run's
    // persisted snapshot. This is the round-trip the user actually cares
    // about: switch apps, return, totals are still there.
    const sharedStore = {}
    const wm1 = loadWordMeter({ localStorageStore: sharedStore })
    wm1.simulateResult("hello world how are you", true)
    assert.strictEqual(wm1.getState().totalWords, 5)
    wm1.persistNow()

    const wm2 = loadWordMeter({ localStorageStore: sharedStore })
    wm2.reload()
    assert.strictEqual(wm2.getState().totalWords, 5, "total words restored")
  })

  test("an in-process reload restores totals through persistState round-trip", () => {
    const wm = loadWordMeter({ localStorageStore: {} })
    wm.simulateResult("alpha bravo charlie", true)
    wm.persistNow()
    const restored = wm.reload()
    assert.strictEqual(restored, true)
    assert.strictEqual(wm.getState().totalWords, 3)
  })

  test("returns null/false when storage is empty and there is nothing to restore", () => {
    const wm = loadWordMeter({ localStorageStore: {} })
    const restored = wm.reload()
    assert.strictEqual(restored, false)
    assert.strictEqual(wm.getState().totalWords, 0)
  })

  test("starting recognition while running survives a reload that records the active interval", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: false, localStorageStore: {} })
    harness.wm.start()
    harness.wm.simulateResult("good morning", true)
    harness.wm.stop()
    assert.strictEqual(harness.wm.getState().intervals.length, 1)
    assert.strictEqual(harness.wm.getState().intervals[0].words, 2)
  })

  test("survives a missing localStorage gracefully (no crash, no persistence)", () => {
    const wm = loadWordMeter() // no storage configured
    wm.simulateResult("a b c", true)
    // Persisting must not throw.
    wm.persistNow()
    assert.strictEqual(wm.getState().totalWords, 3)
  })

  test("ignores corrupted persisted JSON without throwing", () => {
    const sharedStore = { "word-meter:state:v1": "{not valid json" }
    const wm = loadWordMeter({ localStorageStore: sharedStore })
    // The IIFE doesn't auto-restore (no DOM host element), but reload() does:
    const restored = wm.reload()
    assert.strictEqual(restored, false)
    assert.strictEqual(wm.getState().totalWords, 0)
  })

  test("ignores persisted snapshots from an older schema version", () => {
    const sharedStore = {
      "word-meter:state:v1": JSON.stringify({ version: 0, totalWords: 999 }),
    }
    const wm = loadWordMeter({ localStorageStore: sharedStore })
    const restored = wm.reload()
    assert.strictEqual(restored, false)
    assert.strictEqual(wm.getState().totalWords, 0)
  })
})

describe("Word Meter — reset button", () => {
  test("reset clears totals, intervals, and the persisted snapshot", () => {
    const sharedStore = {}
    const wm = loadWordMeter({ localStorageStore: sharedStore })
    wm.simulateResult("one two three four", true)
    wm.persistNow()
    assert.strictEqual(wm.getState().totalWords, 4)
    wm.reset()
    assert.strictEqual(wm.getState().totalWords, 0)
    assert.strictEqual(wm.getState().intervals.length, 0)
    // After reset, a fresh load sees nothing.
    const wm2 = loadWordMeter({ localStorageStore: sharedStore })
    const restored = wm2.reload()
    assert.strictEqual(restored, false)
    assert.strictEqual(wm2.getState().totalWords, 0)
  })

  test("reset while listening stops the recognizer and clears state", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: false, localStorageStore: {} })
    harness.wm.start()
    harness.wm.simulateResult("foo bar", true)
    harness.wm.reset()
    const state = harness.wm.getState()
    assert.strictEqual(state.listening, false)
    assert.strictEqual(state.totalWords, 0)
    assert.strictEqual(state.intervals.length, 0)
    assert.strictEqual(state.firstStartedAt, null)
  })
})

describe("Word Meter — interval timeline", () => {
  test("each start/stop cycle appends a completed interval with its word count", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: false, localStorageStore: {} })
    harness.wm.start()
    harness.wm.simulateResult("one two three", true)
    harness.wm.stop()
    harness.wm.start()
    harness.wm.simulateResult("four five", true)
    harness.wm.stop()
    const intervals = harness.wm.getState().intervals
    assert.strictEqual(intervals.length, 2)
    assert.strictEqual(intervals[0].words, 3)
    assert.strictEqual(intervals[1].words, 2)
    assert.strictEqual(harness.wm.getState().totalWords, 5)
  })

  test("starting again after stop accumulates totals (does not reset to zero)", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: false, localStorageStore: {} })
    harness.wm.start()
    harness.wm.simulateResult("alpha bravo", true)
    harness.wm.stop()
    assert.strictEqual(harness.wm.getState().totalWords, 2)
    harness.wm.start()
    harness.wm.simulateResult("charlie delta echo", true)
    assert.strictEqual(
      harness.wm.getState().totalWords,
      5,
      "second start must continue from the previous total, not reset",
    )
  })

  test("the in-progress interval is exposed while listening and is folded into intervals on stop", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: false, localStorageStore: {} })
    harness.wm.start()
    harness.wm.simulateResult("hello", true)
    const stateBeforeStop = harness.wm.getState()
    assert.notStrictEqual(stateBeforeStop.currentInterval, null)
    assert.strictEqual(stateBeforeStop.currentInterval.words, 1)
    assert.strictEqual(stateBeforeStop.intervals.length, 0)
    harness.wm.stop()
    const stateAfterStop = harness.wm.getState()
    assert.strictEqual(stateAfterStop.currentInterval, null)
    assert.strictEqual(stateAfterStop.intervals.length, 1)
    assert.strictEqual(stateAfterStop.intervals[0].words, 1)
  })

  test("firstStartedAt is set on the first ever start and preserved across subsequent starts", async () => {
    const harness = loadWordMeterWithLifecycle({ wakeLockSupported: false, localStorageStore: {} })
    harness.wm.start()
    const firstStart = harness.wm.getState().firstStartedAt
    assert.ok(typeof firstStart === "number", "firstStartedAt must be a timestamp")
    harness.wm.stop()
    harness.wm.start()
    assert.strictEqual(
      harness.wm.getState().firstStartedAt,
      firstStart,
      "firstStartedAt must NOT change on subsequent starts",
    )
  })
})
