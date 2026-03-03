/**
 * Pure utility functions for the Text-to-Speech player.
 * Extracted so they can be unit-tested independently of the DOM.
 */

/** Average words-per-minute used for time estimates. */
export const AVG_WPM = 150

/** Words spoken per second at 1× speed. */
export const WPS = AVG_WPM / 60

/**
 * Strip emoji characters from text, including variation selectors and
 * zero-width joiners used in compound emoji sequences.
 */
export function stripEmojis(text: string): string {
  return text
    .replace(/\p{Extended_Pictographic}/gu, "")
    .replace(/[\u{FE00}-\u{FE0F}\u{200D}]/gu, "")
}

/**
 * Split text into sentences (rough heuristic). Keeps the delimiter
 * attached so speech sounds natural. Captures trailing text that
 * lacks sentence-ending punctuation.
 */
export function splitIntoSentences(text: string): string[] {
  if (!text) return []
  const raw = text.match(/[^.!?]*[.!?]+[\s]*/g)
  if (!raw) return text.length > 0 ? [text] : []
  const matched = raw.join("")
  const trailing = text.slice(matched.length).trim()
  const result = raw.map((s) => s.trim()).filter((s) => s.length > 0)
  if (trailing.length > 0) {
    result.push(trailing)
  }
  return result
}

/** Count words in a string. */
export function wordCount(s: string): number {
  return s.split(/\s+/).filter(Boolean).length
}

/** Estimate total duration (seconds) for a word count at a given rate. */
export function estimateDuration(words: number, rate: number): number {
  return words / (WPS * rate)
}

/** Format seconds → m:ss */
export function formatTime(sec: number): string {
  if (!Number.isFinite(sec) || sec < 0) return "0:00"
  const m = Math.floor(sec / 60)
  const s = Math.floor(sec % 60)
  return `${m}:${s.toString().padStart(2, "0")}`
}

/**
 * Build cumulative word-count array from per-sentence word counts.
 * cumulativeWords[i] = total words in sentences 0..i (inclusive).
 */
export function buildCumulativeWords(wordCounts: number[]): number[] {
  const result: number[] = []
  let running = 0
  for (const wc of wordCounts) {
    running += wc
    result.push(running)
  }
  return result
}

/**
 * Given a target time (seconds), find the sentence index that corresponds
 * to that position in the text.
 */
export function sentenceIndexForTime(
  targetSec: number,
  cumulativeWords: number[],
  rate: number,
): number {
  const targetWords = targetSec * WPS * rate
  for (let i = 0; i < cumulativeWords.length; i++) {
    if (cumulativeWords[i] >= targetWords) {
      return i
    }
  }
  return Math.max(cumulativeWords.length - 1, 0)
}

/**
 * Clean raw text by collapsing whitespace, stripping residual
 * Markdown / markup characters, and removing emoji.
 */
export function cleanText(text: string): string {
  return stripEmojis(text)
    .replace(/\s+/g, " ")
    .replace(/[#*_`~\[\](){}<>|]/g, "")
    .trim()
}

/** Selectors for block-level containers that should be skipped entirely. */
export const SELECTORS_TO_REMOVE = [
  "nav",
  "header",
  "footer",
  ".sidebar",
  ".backlinks",
  ".graph",
  ".toc",
  ".explorer",
  ".search",
  "pre",
  "script",
  "style",
  "svg",
  ".katex",
  ".mermaid",
  ".callout-title-inner",
  ".external-icon",
  "button",
  ".tts-container",
]

/** Inline selectors to remove within block elements during text extraction. */
export const INLINE_SELECTORS_TO_REMOVE = [
  "code",
  "svg",
  ".katex",
  ".mermaid",
  "button",
  ".external-icon",
]

/** Block-level selectors for text content elements. */
export const BLOCK_SELECTORS =
  "p, li, h1, h2, h3, h4, h5, h6, td, th, dd, dt, figcaption, summary"
