/**
 * Text-to-Speech player using the Web Speech API (SpeechSynthesis).
 *
 * Features:
 *  - Play / Pause
 *  - Skip ±30 s (approximated via word-count chunking)
 *  - Playback speed 0.5×–2×
 *  - Seek bar with elapsed / total time estimates
 *  - Sentence highlighting & auto-scroll
 *  - Always-fixed player with collapsible toggle
 *
 * Only reads the article content – no navigation, menus, or markup.
 * Emojis are stripped so the synthesiser reads clean prose.
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
  INLINE_SELECTORS_TO_REMOVE,
  BLOCK_SELECTORS,
} from "./tts.utils"

// ---------------------------------------------------------------------------
// Block-aware text extraction with DOM element mapping
// ---------------------------------------------------------------------------

interface TextBlock {
  element: Element
  text: string
  charStart: number
  charEnd: number
}

/**
 * Check whether a block element should be skipped because it (or an ancestor
 * below the article root) matches a removal selector.
 */
function shouldSkipBlock(el: Element, article: Element): boolean {
  let current: Element | null = el
  while (current && current !== article) {
    for (const sel of SELECTORS_TO_REMOVE) {
      try {
        if (current.matches(sel)) return true
      } catch {
        /* invalid selector – skip */
      }
    }
    current = current.parentElement
  }
  return false
}

/**
 * Walk the article's block-level text elements and build a parallel
 * structure of cleaned text + DOM references.  Returns the concatenated
 * full text and an array of TextBlock descriptors.
 *
 * Skips parent block elements that contain nested block children to avoid
 * reading the same content twice (e.g. <li> containing <p>).
 */
function extractArticleBlocks(): { text: string; blocks: TextBlock[] } {
  const article = document.querySelector("article")
  if (!article) return { text: "", blocks: [] }

  const blocks: TextBlock[] = []
  const blockElements = article.querySelectorAll(BLOCK_SELECTORS)
  let offset = 0

  for (const el of blockElements) {
    if (shouldSkipBlock(el, article)) continue

    // Skip parent blocks that contain nested block children to avoid
    // reading the same content twice (e.g. <li> wrapping a <p>).
    if (el.querySelector(BLOCK_SELECTORS)) continue

    // Clone to strip inline junk without mutating the real DOM
    const clone = el.cloneNode(true) as HTMLElement
    for (const sel of INLINE_SELECTORS_TO_REMOVE) {
      clone.querySelectorAll(sel).forEach((e) => e.remove())
    }

    const text = cleanText(clone.textContent ?? "")
    if (!text) continue

    blocks.push({ element: el, text, charStart: offset, charEnd: offset + text.length })
    offset += text.length + 1 // +1 for the joining space
  }

  const fullText = blocks.map((b) => b.text).join(" ")
  return { text: fullText, blocks }
}

/**
 * Map each sentence index to the index of the TextBlock that contains
 * the start of that sentence.
 */
function buildSentenceBlockMap(
  sentences: string[],
  fullText: string,
  blocks: TextBlock[],
): number[] {
  const map: number[] = []
  let searchPos = 0
  for (const sentence of sentences) {
    const pos = fullText.indexOf(sentence, searchPos)
    if (pos >= 0) {
      let blockIdx = 0
      let found = false
      for (let i = 0; i < blocks.length; i++) {
        if (pos >= blocks[i].charStart && pos < blocks[i].charEnd) {
          blockIdx = i
          found = true
          break
        }
        if (pos < blocks[i].charStart) {
          blockIdx = i
          found = true
          break
        }
      }
      // If not found inside any block, default to the last block
      if (!found && blocks.length > 0) {
        blockIdx = blocks.length - 1
      }
      map.push(blockIdx)
      searchPos = pos + sentence.length
    } else {
      map.push(map.length > 0 ? map[map.length - 1] : 0)
    }
  }
  return map
}

// ---------------------------------------------------------------------------
// Player state & DOM wiring — runs after DOM ready on every SPA navigation
// ---------------------------------------------------------------------------

document.addEventListener("nav", () => {
  // Bail out if the browser doesn't support speech synthesis.
  if (!("speechSynthesis" in window)) {
    const wrapper = document.getElementById("tts-wrapper")
    if (wrapper) wrapper.style.display = "none"
    return
  }

  const synth = window.speechSynthesis

  // DOM handles
  const wrapper = document.getElementById("tts-wrapper")
  const container = document.getElementById("tts-container")
  const playBtn = document.getElementById("tts-play") as HTMLButtonElement | null
  const playIcon = document.getElementById("tts-play-icon") as HTMLElement | null
  const pauseIcon = document.getElementById("tts-pause-icon") as HTMLElement | null
  const backBtn = document.getElementById("tts-back") as HTMLButtonElement | null
  const forwardBtn = document.getElementById("tts-forward") as HTMLButtonElement | null
  const speedSel = document.getElementById("tts-speed") as HTMLSelectElement | null
  const seekBar = document.getElementById("tts-seek") as HTMLInputElement | null
  const currentTimeEl = document.getElementById("tts-current-time")
  const totalTimeEl = document.getElementById("tts-total-time")
  const toggleBtn = document.getElementById("tts-toggle") as HTMLButtonElement | null

  if (!playBtn || !container || !wrapper) return

  // ---- State ----
  let sentences: string[] = []
  let wordCounts: number[] = []
  let cumulativeWords: number[] = []
  let totalWords = 0
  let currentIdx = 0
  let playing = false
  // Read speed from the selector (persists across SPA navigations)
  let rate = speedSel ? Number(speedSel.value) || 1 : 1
  let totalDuration = 0
  let tickTimer: ReturnType<typeof setInterval> | null = null
  let sentenceStartTime = 0
  let blocks: TextBlock[] = []
  let sentenceBlockMap: number[] = []
  let prevHighlightEl: Element | null = null

  // ---- Toggle collapse/expand ----

  function onToggle() {
    wrapper!.classList.toggle("tts-collapsed")
  }

  // Position player above FixedFooter if present
  function adjustForFooter() {
    const fixedFooter = document.querySelector(".fixed-cta-footer") as HTMLElement | null
    if (fixedFooter) {
      const footerHeight = fixedFooter.getBoundingClientRect().height
      wrapper!.style.bottom = `${footerHeight}px`
    } else {
      wrapper!.style.bottom = ""
    }
  }

  adjustForFooter()

  // ---- Helpers ----

  function prepare() {
    const result = extractArticleBlocks()
    blocks = result.blocks
    sentences = splitIntoSentences(result.text)
    sentenceBlockMap = buildSentenceBlockMap(sentences, result.text, blocks)
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

  // ---- Highlight & scroll ----

  function highlightCurrentSentence() {
    // Remove previous highlight
    if (prevHighlightEl) {
      prevHighlightEl.classList.remove("tts-highlight")
      prevHighlightEl = null
    }

    if (currentIdx >= sentenceBlockMap.length) return
    const blockIdx = sentenceBlockMap[currentIdx]
    if (blockIdx >= blocks.length) return

    const el = blocks[blockIdx].element
    el.classList.add("tts-highlight")
    prevHighlightEl = el

    // Auto-scroll to keep the highlighted element visible
    el.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  function clearHighlight() {
    if (prevHighlightEl) {
      prevHighlightEl.classList.remove("tts-highlight")
      prevHighlightEl = null
    }
  }

  // ---- Play / Pause UI ----

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
    synth.cancel()
    if (idx < 0) idx = 0
    if (idx >= sentences.length) {
      stop()
      return
    }

    currentIdx = idx
    playing = true
    showPause()
    startTick()
    highlightCurrentSentence()
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
        highlightCurrentSentence()
        speakCurrent()
      } else if (currentIdx >= sentences.length) {
        stop()
      }
    }
    utterance.onerror = (e) => {
      if (e.error !== "interrupted" && e.error !== "canceled") {
        console.warn("[TTS] utterance error", e.error)
        currentIdx++
        if (currentIdx < sentences.length && playing) {
          highlightCurrentSentence()
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
    clearHighlight()
    updateUI()
  }

  // ---- Event handlers ----

  function onPlay() {
    if (sentences.length === 0) prepare()
    if (sentences.length === 0) return

    if (playing) {
      // Pause — using cancel() for reliable cross-utterance behaviour
      synth.cancel()
      playing = false
      stopTick()
      showPlay()
      // Keep highlight while paused so the user sees where they are
      updateUI()
    } else {
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
      highlightCurrentSentence()
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

    // Don't restart the current sentence — let it finish at the old rate.
    // The new rate will apply to the next utterance automatically.
    updateUI()
  }

  // ---- Bind events ----
  playBtn.addEventListener("click", onPlay)
  backBtn?.addEventListener("click", onBack)
  forwardBtn?.addEventListener("click", onForward)
  seekBar?.addEventListener("input", onSeek)
  speedSel?.addEventListener("change", onSpeedChange)
  toggleBtn?.addEventListener("click", onToggle)

  // ---- Cleanup on SPA navigation ----
  window.addCleanup(() => {
    stop()
    playBtn.removeEventListener("click", onPlay)
    backBtn?.removeEventListener("click", onBack)
    forwardBtn?.removeEventListener("click", onForward)
    seekBar?.removeEventListener("input", onSeek)
    speedSel?.removeEventListener("change", onSpeedChange)
    toggleBtn?.removeEventListener("click", onToggle)
  })

  // Initial prepare so the total time is shown
  prepare()
  updateUI()
})
