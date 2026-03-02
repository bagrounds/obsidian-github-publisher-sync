/**
 * Text-to-Speech player using the Web Speech API (SpeechSynthesis).
 *
 * Features:
 *  - Play / Pause
 *  - Skip ±30 s (approximated via word-count chunking)
 *  - Playback speed 0.5×–2×
 *  - Seek bar with elapsed / total time estimates
 *
 * Only reads the article content – no navigation, menus, or markup.
 */

import {
  WPS,
  splitIntoSentences,
  wordCount,
  estimateDuration,
  formatTime,
  buildCumulativeWords,
  sentenceIndexForTime,
  cleanText,
  SELECTORS_TO_REMOVE,
} from "./tts.utils"

// ---------------------------------------------------------------------------
// Text extraction (DOM-dependent)
// ---------------------------------------------------------------------------

/**
 * Extract readable text from the page article, stripping navigation, menus,
 * code blocks, and residual Markdown / HTML artefacts.
 */
function extractArticleText(): string {
  const article = document.querySelector("article")
  if (!article) return ""

  // Clone so we can remove unwanted nodes without mutating the DOM.
  const clone = article.cloneNode(true) as HTMLElement

  for (const sel of SELECTORS_TO_REMOVE) {
    clone.querySelectorAll(sel).forEach((el) => el.remove())
  }

  return cleanText(clone.textContent ?? "")
}

// ---------------------------------------------------------------------------
// Player state & DOM wiring — runs after DOM ready on every SPA navigation
// ---------------------------------------------------------------------------

document.addEventListener("nav", () => {
  // Bail out if the browser doesn't support speech synthesis.
  if (!("speechSynthesis" in window)) {
    const container = document.getElementById("tts-container")
    if (container) container.style.display = "none"
    return
  }

  const synth = window.speechSynthesis

  // DOM handles --
  const playBtn = document.getElementById("tts-play") as HTMLButtonElement | null
  const playIcon = document.getElementById("tts-play-icon") as HTMLElement | null
  const pauseIcon = document.getElementById("tts-pause-icon") as HTMLElement | null
  const backBtn = document.getElementById("tts-back") as HTMLButtonElement | null
  const forwardBtn = document.getElementById("tts-forward") as HTMLButtonElement | null
  const speedSel = document.getElementById("tts-speed") as HTMLSelectElement | null
  const seekBar = document.getElementById("tts-seek") as HTMLInputElement | null
  const currentTimeEl = document.getElementById("tts-current-time")
  const totalTimeEl = document.getElementById("tts-total-time")

  if (!playBtn) return // component not on page

  // ---- State ----
  let sentences: string[] = []
  let wordCounts: number[] = [] // per-sentence word counts
  let cumulativeWords: number[] = [] // running total of words up to (and including) each sentence
  let totalWords = 0
  let currentIdx = 0 // index of the sentence currently being spoken
  let playing = false
  let rate = 1
  let totalDuration = 0 // estimated total seconds at current rate
  let tickTimer: ReturnType<typeof setInterval> | null = null
  let sentenceStartTime = 0 // wall-clock time when current sentence started

  // ---- Helpers ----

  function prepare() {
    const text = extractArticleText()
    sentences = splitIntoSentences(text)
    wordCounts = sentences.map(wordCount)
    cumulativeWords = buildCumulativeWords(wordCounts)
    totalWords = cumulativeWords.length > 0 ? cumulativeWords[cumulativeWords.length - 1] : 0
    totalDuration = estimateDuration(totalWords, rate)
    if (totalTimeEl) totalTimeEl.textContent = formatTime(totalDuration)
  }

  function wordsBeforeIndex(idx: number): number {
    if (idx <= 0) return 0
    return cumulativeWords[idx - 1] ?? 0
  }

  function elapsedSeconds(): number {
    const wordsBefore = wordsBeforeIndex(currentIdx)
    const sentenceWords = wordCounts[currentIdx] ?? 0
    const sentenceDuration = estimateDuration(sentenceWords, rate)
    const wallElapsed = (Date.now() - sentenceStartTime) / 1000
    const fractionDone = sentenceDuration > 0 ? Math.min(wallElapsed / sentenceDuration, 1) : 0
    const wordsElapsedInSentence = sentenceWords * fractionDone
    return estimateDuration(wordsBefore + wordsElapsedInSentence, rate)
  }

  function updateUI() {
    const elapsed = playing ? elapsedSeconds() : estimateDuration(wordsBeforeIndex(currentIdx), rate)
    if (currentTimeEl) currentTimeEl.textContent = formatTime(elapsed)
    if (seekBar) seekBar.value = String(totalDuration > 0 ? (elapsed / totalDuration) * 100 : 0)
  }

  function showPlay() {
    if (playIcon) playIcon.style.display = ""
    if (pauseIcon) pauseIcon.style.display = "none"
    if (playBtn) playBtn.setAttribute("aria-label", "Play")
    if (playBtn) playBtn.title = "Play"
  }

  function showPause() {
    if (playIcon) playIcon.style.display = "none"
    if (pauseIcon) pauseIcon.style.display = ""
    if (playBtn) playBtn.setAttribute("aria-label", "Pause")
    if (playBtn) playBtn.title = "Pause"
  }

  function startTick() {
    stopTick()
    tickTimer = setInterval(updateUI, 250)
  }

  function stopTick() {
    if (tickTimer !== null) {
      clearInterval(tickTimer)
      tickTimer = null
    }
  }

  // ---- Core speech logic ----

  function speakFrom(idx: number) {
    synth.cancel() // stop anything in progress
    if (idx < 0) idx = 0
    if (idx >= sentences.length) {
      stop()
      return
    }

    currentIdx = idx
    playing = true
    showPause()
    startTick()
    speakCurrent()
  }

  function speakCurrent() {
    if (currentIdx >= sentences.length) {
      stop()
      return
    }

    const utterance = new SpeechSynthesisUtterance(sentences[currentIdx])
    utterance.rate = rate
    utterance.onend = () => {
      currentIdx++
      if (currentIdx < sentences.length && playing) {
        speakCurrent()
      } else if (currentIdx >= sentences.length) {
        stop()
      }
    }
    utterance.onerror = (e) => {
      // "interrupted" and "canceled" are expected when we call synth.cancel()
      if (e.error !== "interrupted" && e.error !== "canceled") {
        console.warn("[TTS] utterance error", e.error)
        // Try to continue with the next sentence
        currentIdx++
        if (currentIdx < sentences.length && playing) {
          speakCurrent()
        } else {
          stop()
        }
      }
    }
    sentenceStartTime = Date.now()
    synth.speak(utterance)
  }

  function stop() {
    synth.cancel()
    playing = false
    stopTick()
    showPlay()
    updateUI()
  }

  function reset() {
    stop()
    currentIdx = 0
    updateUI()
  }

  // ---- Event handlers ----

  function onPlay() {
    if (sentences.length === 0) prepare()
    if (sentences.length === 0) return // nothing to read

    if (playing) {
      // Pause — using cancel() instead of pause() for more reliable behavior across utterances
      synth.cancel()
      playing = false
      stopTick()
      showPlay()
      updateUI()
    } else {
      // Resume / start
      if (currentIdx >= sentences.length) currentIdx = 0
      speakFrom(currentIdx)
    }
  }

  function onBack() {
    if (sentences.length === 0) return
    const elapsed = elapsedSeconds()
    const targetTime = Math.max(0, elapsed - 30)
    seekToTime(targetTime)
  }

  function onForward() {
    if (sentences.length === 0) return
    const elapsed = elapsedSeconds()
    const targetTime = Math.min(totalDuration, elapsed + 30)
    seekToTime(targetTime)
  }

  function seekToTime(targetSec: number) {
    let idx = sentenceIndexForTime(targetSec, cumulativeWords, rate)
    idx = Math.min(idx, sentences.length - 1)
    idx = Math.max(idx, 0)

    if (playing) {
      speakFrom(idx)
    } else {
      currentIdx = idx
      updateUI()
    }
  }

  function onSeek() {
    if (!seekBar || sentences.length === 0) return
    const pct = Number(seekBar.value) / 100
    seekToTime(pct * totalDuration)
  }

  function onSpeedChange() {
    if (!speedSel) return
    rate = Number(speedSel.value) || 1
    totalDuration = estimateDuration(totalWords, rate)
    if (totalTimeEl) totalTimeEl.textContent = formatTime(totalDuration)

    if (playing) {
      // Restart current sentence at new speed
      speakFrom(currentIdx)
    } else {
      updateUI()
    }
  }

  // ---- Bind events ----
  playBtn.addEventListener("click", onPlay)
  backBtn?.addEventListener("click", onBack)
  forwardBtn?.addEventListener("click", onForward)
  seekBar?.addEventListener("input", onSeek)
  speedSel?.addEventListener("change", onSpeedChange)

  // ---- Cleanup on SPA navigation ----
  window.addCleanup(() => {
    stop()
    playBtn.removeEventListener("click", onPlay)
    backBtn?.removeEventListener("click", onBack)
    forwardBtn?.removeEventListener("click", onForward)
    seekBar?.removeEventListener("input", onSeek)
    speedSel?.removeEventListener("change", onSpeedChange)
  })

  // Initial prepare so the total time is shown
  prepare()
  updateUI()
})
