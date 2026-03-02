import test, { describe } from "node:test"
import assert from "node:assert"
import {
  AVG_WPM,
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
// Constants
// ---------------------------------------------------------------------------
describe("TTS constants", () => {
  test("AVG_WPM is a positive number", () => {
    assert.strictEqual(typeof AVG_WPM, "number")
    assert.ok(AVG_WPM > 0)
  })

  test("WPS derives from AVG_WPM", () => {
    assert.strictEqual(WPS, AVG_WPM / 60)
  })

  test("SELECTORS_TO_REMOVE is a non-empty array of strings", () => {
    assert.ok(Array.isArray(SELECTORS_TO_REMOVE))
    assert.ok(SELECTORS_TO_REMOVE.length > 0)
    for (const sel of SELECTORS_TO_REMOVE) {
      assert.strictEqual(typeof sel, "string")
    }
  })
})

// ---------------------------------------------------------------------------
// splitIntoSentences
// ---------------------------------------------------------------------------
describe("splitIntoSentences", () => {
  test("returns empty array for empty string", () => {
    assert.deepStrictEqual(splitIntoSentences(""), [])
  })

  test("returns empty array for undefined-ish falsy input", () => {
    // The function accepts a string, but "" is falsy
    assert.deepStrictEqual(splitIntoSentences(""), [])
  })

  test("splits on periods", () => {
    const result = splitIntoSentences("Hello world. How are you. Fine.")
    assert.strictEqual(result.length, 3)
    assert.ok(result[0].includes("Hello world"))
    assert.ok(result[1].includes("How are you"))
    assert.ok(result[2].includes("Fine"))
  })

  test("splits on exclamation marks", () => {
    const result = splitIntoSentences("Wow! Amazing! Great!")
    assert.strictEqual(result.length, 3)
  })

  test("splits on question marks", () => {
    const result = splitIntoSentences("Who? What? Where?")
    assert.strictEqual(result.length, 3)
  })

  test("handles mixed punctuation", () => {
    const result = splitIntoSentences("Hello. How are you? Great!")
    assert.strictEqual(result.length, 3)
  })

  test("handles text without sentence-ending punctuation", () => {
    const result = splitIntoSentences("No punctuation here")
    assert.strictEqual(result.length, 1)
    assert.strictEqual(result[0], "No punctuation here")
  })

  test("handles single sentence", () => {
    const result = splitIntoSentences("Just one sentence.")
    assert.strictEqual(result.length, 1)
    assert.ok(result[0].includes("Just one sentence"))
  })

  test("handles multiple periods in a row (e.g. ellipsis)", () => {
    const result = splitIntoSentences("Wait... What happened? I see.")
    // The ellipsis may split oddly, but we should get something reasonable
    assert.ok(result.length >= 2)
  })

  test("handles very long text", () => {
    const longText = Array(100).fill("This is sentence number N.").join(" ")
    const result = splitIntoSentences(longText)
    assert.strictEqual(result.length, 100)
  })

  test("does not return empty strings in results", () => {
    const result = splitIntoSentences("A. B. C. ")
    for (const s of result) {
      assert.ok(s.length > 0, `Got empty string in results`)
    }
  })

  test("handles abbreviations (Mr. Mrs.) without perfect splitting", () => {
    // This is a known limitation — just verify it doesn't crash
    const result = splitIntoSentences("Mr. Smith went home. He was tired.")
    assert.ok(result.length >= 1)
  })
})

// ---------------------------------------------------------------------------
// wordCount
// ---------------------------------------------------------------------------
describe("wordCount", () => {
  test("returns 0 for empty string", () => {
    assert.strictEqual(wordCount(""), 0)
  })

  test("counts single word", () => {
    assert.strictEqual(wordCount("hello"), 1)
  })

  test("counts multiple words", () => {
    assert.strictEqual(wordCount("one two three"), 3)
  })

  test("handles extra whitespace", () => {
    assert.strictEqual(wordCount("  one   two   three  "), 3)
  })

  test("handles tabs and newlines", () => {
    assert.strictEqual(wordCount("one\ttwo\nthree"), 3)
  })

  test("handles whitespace-only string", () => {
    assert.strictEqual(wordCount("   "), 0)
  })
})

// ---------------------------------------------------------------------------
// estimateDuration
// ---------------------------------------------------------------------------
describe("estimateDuration", () => {
  test("returns 0 for 0 words", () => {
    assert.strictEqual(estimateDuration(0, 1), 0)
  })

  test("returns positive duration for positive words", () => {
    const dur = estimateDuration(150, 1)
    assert.ok(dur > 0)
    // 150 words at 150 WPM = 60 seconds
    assert.strictEqual(dur, 60)
  })

  test("higher rate means shorter duration", () => {
    const normal = estimateDuration(150, 1)
    const fast = estimateDuration(150, 2)
    assert.ok(fast < normal)
    assert.strictEqual(fast, normal / 2)
  })

  test("lower rate means longer duration", () => {
    const normal = estimateDuration(150, 1)
    const slow = estimateDuration(150, 0.5)
    assert.ok(slow > normal)
    assert.strictEqual(slow, normal * 2)
  })

  test("handles fractional word counts", () => {
    const dur = estimateDuration(75, 1)
    assert.strictEqual(dur, 30) // half of 60s
  })
})

// ---------------------------------------------------------------------------
// formatTime
// ---------------------------------------------------------------------------
describe("formatTime", () => {
  test("formats 0 seconds", () => {
    assert.strictEqual(formatTime(0), "0:00")
  })

  test("formats seconds < 60", () => {
    assert.strictEqual(formatTime(5), "0:05")
    assert.strictEqual(formatTime(30), "0:30")
    assert.strictEqual(formatTime(59), "0:59")
  })

  test("formats exact minutes", () => {
    assert.strictEqual(formatTime(60), "1:00")
    assert.strictEqual(formatTime(120), "2:00")
    assert.strictEqual(formatTime(600), "10:00")
  })

  test("formats minutes and seconds", () => {
    assert.strictEqual(formatTime(90), "1:30")
    assert.strictEqual(formatTime(125), "2:05")
    assert.strictEqual(formatTime(3661), "61:01")
  })

  test("handles fractional seconds by flooring", () => {
    assert.strictEqual(formatTime(5.7), "0:05")
    assert.strictEqual(formatTime(59.9), "0:59")
    assert.strictEqual(formatTime(60.1), "1:00")
  })

  test("handles negative values", () => {
    assert.strictEqual(formatTime(-1), "0:00")
    assert.strictEqual(formatTime(-100), "0:00")
  })

  test("handles NaN", () => {
    assert.strictEqual(formatTime(NaN), "0:00")
  })

  test("handles Infinity", () => {
    assert.strictEqual(formatTime(Infinity), "0:00")
    assert.strictEqual(formatTime(-Infinity), "0:00")
  })
})

// ---------------------------------------------------------------------------
// buildCumulativeWords
// ---------------------------------------------------------------------------
describe("buildCumulativeWords", () => {
  test("returns empty array for empty input", () => {
    assert.deepStrictEqual(buildCumulativeWords([]), [])
  })

  test("returns same value for single element", () => {
    assert.deepStrictEqual(buildCumulativeWords([5]), [5])
  })

  test("accumulates correctly", () => {
    assert.deepStrictEqual(buildCumulativeWords([3, 5, 2]), [3, 8, 10])
  })

  test("handles zeros", () => {
    assert.deepStrictEqual(buildCumulativeWords([0, 0, 5]), [0, 0, 5])
  })

  test("last element equals total", () => {
    const counts = [10, 20, 30, 40]
    const cum = buildCumulativeWords(counts)
    assert.strictEqual(cum[cum.length - 1], 100)
  })
})

// ---------------------------------------------------------------------------
// sentenceIndexForTime
// ---------------------------------------------------------------------------
describe("sentenceIndexForTime", () => {
  // Setup: 4 sentences with 10 words each = 40 total words
  // At rate 1, WPS=2.5, so 40 words = 16 seconds total
  // Sentence 0: words 0-10, cumulative [10]
  // Sentence 1: words 10-20, cumulative [10, 20]
  // Sentence 2: words 20-30, cumulative [10, 20, 30]
  // Sentence 3: words 30-40, cumulative [10, 20, 30, 40]
  const cumWords = [10, 20, 30, 40]

  test("returns 0 for time 0", () => {
    assert.strictEqual(sentenceIndexForTime(0, cumWords, 1), 0)
  })

  test("returns correct index for middle of text", () => {
    // 8 seconds at rate 1 = 8 * 2.5 = 20 target words
    // cumWords[1] = 20, so index 1
    const idx = sentenceIndexForTime(8, cumWords, 1)
    assert.strictEqual(idx, 1)
  })

  test("returns last index for time at end", () => {
    // 16 seconds = 40 target words, cumWords[3] = 40, so index 3
    const idx = sentenceIndexForTime(16, cumWords, 1)
    assert.strictEqual(idx, 3)
  })

  test("returns last valid index for time beyond total", () => {
    // 20 seconds > total 16s: should clamp to last valid index
    const idx = sentenceIndexForTime(20, cumWords, 1)
    // The function returns min(length, last matching + 1), clamped by caller
    assert.ok(idx >= cumWords.length - 1)
  })

  test("accounts for playback rate", () => {
    // At rate 2, 4 seconds = 4 * 2.5 * 2 = 20 target words
    const idx = sentenceIndexForTime(4, cumWords, 2)
    assert.strictEqual(idx, 1)
  })

  test("handles empty cumulative array", () => {
    const idx = sentenceIndexForTime(5, [], 1)
    assert.strictEqual(idx, 0)
  })

  test("handles single sentence", () => {
    const idx = sentenceIndexForTime(0, [10], 1)
    assert.strictEqual(idx, 0)
  })
})

// ---------------------------------------------------------------------------
// cleanText
// ---------------------------------------------------------------------------
describe("cleanText", () => {
  test("returns empty string for empty input", () => {
    assert.strictEqual(cleanText(""), "")
  })

  test("collapses multiple spaces", () => {
    assert.strictEqual(cleanText("hello   world"), "hello world")
  })

  test("collapses newlines and tabs", () => {
    assert.strictEqual(cleanText("hello\n\tworld"), "hello world")
  })

  test("strips markdown characters", () => {
    assert.strictEqual(cleanText("# Hello **world** _italic_"), "Hello world italic")
  })

  test("strips brackets and parens", () => {
    assert.strictEqual(cleanText("[link](url)"), "linkurl")
  })

  test("strips angle brackets", () => {
    assert.strictEqual(cleanText("<div>content</div>"), "divcontent/div")
  })

  test("strips pipes (table syntax)", () => {
    const result = cleanText("| cell | cell |")
    assert.ok(!result.includes("|"))
    assert.ok(result.includes("cell"))
  })

  test("strips backticks", () => {
    assert.strictEqual(cleanText("`code`"), "code")
  })

  test("strips tilde (strikethrough)", () => {
    assert.strictEqual(cleanText("~~deleted~~"), "deleted")
  })

  test("trims leading/trailing whitespace", () => {
    assert.strictEqual(cleanText("  hello  "), "hello")
  })

  test("preserves normal prose", () => {
    const prose = "The quick brown fox jumps over the lazy dog."
    assert.strictEqual(cleanText(prose), prose)
  })

  test("handles mixed content", () => {
    const input = "## Title\n\n**Bold** and _italic_ with `code` and [link](url)."
    const result = cleanText(input)
    assert.ok(!result.includes("#"))
    assert.ok(!result.includes("*"))
    assert.ok(!result.includes("_"))
    assert.ok(!result.includes("`"))
    assert.ok(!result.includes("["))
    assert.ok(!result.includes("]"))
    assert.ok(result.includes("Title"))
    assert.ok(result.includes("Bold"))
    assert.ok(result.includes("italic"))
  })
})

// ---------------------------------------------------------------------------
// Integration: full pipeline
// ---------------------------------------------------------------------------
describe("TTS pipeline integration", () => {
  test("full text → sentences → word counts → duration → seek", () => {
    const text = "First sentence here. Second sentence is longer than the first. Third."
    const sentences = splitIntoSentences(text)
    assert.ok(sentences.length >= 3)

    const counts = sentences.map(wordCount)
    assert.ok(counts.every((c) => c > 0))

    const cumulative = buildCumulativeWords(counts)
    assert.strictEqual(cumulative.length, sentences.length)

    const totalWords = cumulative[cumulative.length - 1]
    const duration = estimateDuration(totalWords, 1)
    assert.ok(duration > 0)

    const timeStr = formatTime(duration)
    assert.ok(timeStr.includes(":"))

    // Seeking to 0 should give first sentence
    const idx0 = sentenceIndexForTime(0, cumulative, 1)
    assert.strictEqual(idx0, 0)

    // Seeking to end should give last sentence
    const idxEnd = sentenceIndexForTime(duration, cumulative, 1)
    assert.ok(idxEnd >= sentences.length - 1)
  })

  test("clean text then split preserves sentence structure", () => {
    const dirty = "## Heading\n\n**Bold sentence.** Normal _sentence_ here! Last one?"
    const cleaned = cleanText(dirty)
    const sentences = splitIntoSentences(cleaned)
    assert.ok(sentences.length >= 3)
    // No markdown chars in any sentence
    for (const s of sentences) {
      assert.ok(!s.includes("#"))
      assert.ok(!s.includes("**"))
      assert.ok(!s.includes("_"))
    }
  })

  test("speed changes correctly scale duration", () => {
    const words = 300 // 2 minutes at 1x
    const dur1x = estimateDuration(words, 1)
    const dur2x = estimateDuration(words, 2)
    const dur05x = estimateDuration(words, 0.5)

    assert.strictEqual(dur1x, 120) // 300 words / 2.5 WPS = 120s
    assert.strictEqual(dur2x, 60) // half the time
    assert.strictEqual(dur05x, 240) // double the time
  })

  test("seek position is consistent across speed changes", () => {
    const cumWords = [50, 100, 150, 200]
    // At rate 1, halfway (100 words) = 100/2.5 = 40s
    // At rate 2, halfway (100 words) = 100/5 = 20s
    const idx1x = sentenceIndexForTime(40, cumWords, 1)
    const idx2x = sentenceIndexForTime(20, cumWords, 2)
    assert.strictEqual(idx1x, idx2x) // same sentence
  })
})
