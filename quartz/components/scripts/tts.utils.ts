/**
 * Pure utility functions for the Text-to-Speech player.
 * Extracted so they can be unit-tested independently of the DOM.
 */

/** Average words-per-minute used for time estimates. */
export const AVG_WPM = 150

/** Words spoken per second at 1× speed. */
export const WPS = AVG_WPM / 60

/**
 * Split text into sentences (rough heuristic). Keeps the delimiter
 * attached so speech sounds natural.
 */
export function splitIntoSentences(text: string): string[] {
  if (!text) return []
  const raw = text.match(/[^.!?]*[.!?]+[\s]*/g)
  if (!raw) return text.length > 0 ? [text] : []
  return raw.map((s) => s.trim()).filter((s) => s.length > 0)
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
  let idx = 0
  for (let i = 0; i < cumulativeWords.length; i++) {
    if (cumulativeWords[i] >= targetWords) {
      idx = i
      return idx
    }
    idx = i + 1
  }
  return Math.min(idx, Math.max(cumulativeWords.length - 1, 0))
}

/**
 * Clean raw text by collapsing whitespace and stripping residual
 * Markdown / markup characters.
 */
export function cleanText(text: string): string {
  return text
    .replace(/\s+/g, " ")
    .replace(/[#*_`~\[\](){}<>|]/g, "")
    .trim()
}

/** Selectors for elements that should be removed before text extraction. */
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
  "code",
  "script",
  "style",
  "svg",
  ".katex",
  ".mermaid",
  ".callout-title-inner",
  ".external-icon",
  "button",
]
