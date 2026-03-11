import test, { describe } from "node:test"
import assert from "node:assert"
import {
  AVG_WPM,
  WPS,
  stripEmojis,
  splitIntoSentences,
  wordCount,
  estimateDuration,
  formatTime,
  buildCumulativeWords,
  sentenceIndexForTime,
  cleanText,
  injectBlockPauses,
  SELECTORS_TO_REMOVE,
  INLINE_SELECTORS_TO_REMOVE,
  BLOCK_SELECTORS,
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

  test("INLINE_SELECTORS_TO_REMOVE is a non-empty array of strings", () => {
    assert.ok(Array.isArray(INLINE_SELECTORS_TO_REMOVE))
    assert.ok(INLINE_SELECTORS_TO_REMOVE.length > 0)
  })

  test("BLOCK_SELECTORS is a non-empty string", () => {
    assert.strictEqual(typeof BLOCK_SELECTORS, "string")
    assert.ok(BLOCK_SELECTORS.length > 0)
  })
})

// ---------------------------------------------------------------------------
// stripEmojis
// ---------------------------------------------------------------------------
describe("stripEmojis", () => {
  test("returns empty string for empty input", () => {
    assert.strictEqual(stripEmojis(""), "")
  })

  test("strips common emoji", () => {
    assert.strictEqual(stripEmojis("Hello 🌍 World"), "Hello  World")
  })

  test("strips multiple emoji", () => {
    assert.strictEqual(stripEmojis("🏡 Home 📚 Books 🎤 Talks"), " Home  Books  Talks")
  })

  test("strips compound emoji (ZWJ sequences)", () => {
    const result = stripEmojis("Family: 👨‍👩‍👧‍👦 here")
    assert.ok(!result.includes("👨"))
    assert.ok(!result.includes("👩"))
    assert.ok(result.includes("Family"))
    assert.ok(result.includes("here"))
  })

  test("preserves normal text", () => {
    assert.strictEqual(stripEmojis("Hello World"), "Hello World")
  })

  test("preserves numbers and punctuation", () => {
    assert.strictEqual(stripEmojis("Price: $9.99! (50% off)"), "Price: $9.99! (50% off)")
  })

  test("preserves accented characters", () => {
    assert.strictEqual(stripEmojis("café résumé naïve"), "café résumé naïve")
  })

  test("handles emoji-only string", () => {
    const result = stripEmojis("🎉🎊🎈")
    assert.strictEqual(result.trim(), "")
  })

  test("handles text with emoji variation selectors", () => {
    // Variation selector U+FE0F forces emoji presentation
    const result = stripEmojis("star\u2B50\uFE0F here")
    assert.ok(!result.includes("\u2B50"))
    assert.ok(!result.includes("\uFE0F"))
    assert.ok(result.includes("star"))
    assert.ok(result.includes("here"))
  })

  test("strips skin tone modifiers", () => {
    // 👋🏽 = U+1F44B U+1F3FD (wave + medium skin tone)
    const result = stripEmojis("Hello 👋🏽 there")
    assert.ok(!result.includes("👋"))
    assert.ok(!result.includes("\u{1F3FD}"))
    assert.ok(result.includes("Hello"))
    assert.ok(result.includes("there"))
  })

  test("strips all skin tone variants", () => {
    // Light, medium-light, medium, medium-dark, dark
    const tones = "\u{1F3FB}\u{1F3FC}\u{1F3FD}\u{1F3FE}\u{1F3FF}"
    const result = stripEmojis(`before ${tones} after`)
    assert.ok(!result.includes("\u{1F3FB}"))
    assert.ok(!result.includes("\u{1F3FF}"))
    assert.ok(result.includes("before"))
    assert.ok(result.includes("after"))
  })

  test("strips flag emoji (regional indicators)", () => {
    // 🇺🇸 = U+1F1FA U+1F1F8
    const result = stripEmojis("USA 🇺🇸 flag")
    assert.ok(!result.includes("\u{1F1FA}"))
    assert.ok(!result.includes("\u{1F1F8}"))
    assert.ok(result.includes("USA"))
    assert.ok(result.includes("flag"))
  })

  test("strips keycap emoji", () => {
    // Keycap: 1️⃣ = 0031 FE0F 20E3
    const result = stripEmojis("press 1\uFE0F\u20E3 now")
    assert.ok(!result.includes("\u20E3"))
    assert.ok(result.includes("press"))
    assert.ok(result.includes("now"))
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
    const result = splitIntoSentences("Mr. Smith went home. He was tired.")
    assert.ok(result.length >= 1)
  })

  test("captures trailing text without punctuation", () => {
    const result = splitIntoSentences("First sentence. Trailing text")
    assert.strictEqual(result.length, 2)
    assert.ok(result[0].includes("First sentence"))
    assert.strictEqual(result[1], "Trailing text")
  })

  test("does not duplicate when text ends with punctuation", () => {
    const result = splitIntoSentences("One. Two. Three.")
    assert.strictEqual(result.length, 3)
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
    assert.strictEqual(dur, 30)
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
  const cumWords = [10, 20, 30, 40]

  test("returns 0 for time 0", () => {
    assert.strictEqual(sentenceIndexForTime(0, cumWords, 1), 0)
  })

  test("returns correct index for middle of text", () => {
    const idx = sentenceIndexForTime(8, cumWords, 1)
    assert.strictEqual(idx, 1)
  })

  test("returns last index for time at end", () => {
    const idx = sentenceIndexForTime(16, cumWords, 1)
    assert.strictEqual(idx, 3)
  })

  test("returns last valid index for time beyond total", () => {
    const idx = sentenceIndexForTime(20, cumWords, 1)
    assert.ok(idx >= cumWords.length - 1)
  })

  test("accounts for playback rate", () => {
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

  test("strips emoji from text", () => {
    const result = cleanText("🏡 Home 📚 Books")
    assert.ok(!result.includes("🏡"))
    assert.ok(!result.includes("📚"))
    assert.ok(result.includes("Home"))
    assert.ok(result.includes("Books"))
  })

  test("strips emoji mixed with markdown", () => {
    const result = cleanText("## 🌌 Topics **🎤 Talks**")
    assert.ok(!result.includes("🌌"))
    assert.ok(!result.includes("🎤"))
    assert.ok(!result.includes("#"))
    assert.ok(!result.includes("*"))
    assert.ok(result.includes("Topics"))
    assert.ok(result.includes("Talks"))
  })
})

// ---------------------------------------------------------------------------
// injectBlockPauses
// ---------------------------------------------------------------------------
describe("injectBlockPauses", () => {
  test("returns empty string for empty input", () => {
    assert.strictEqual(injectBlockPauses(""), "")
  })

  test("appends semicolon to plain text", () => {
    assert.strictEqual(injectBlockPauses("Introduction"), "Introduction;")
  })

  test("appends semicolon to a heading-like block", () => {
    assert.strictEqual(injectBlockPauses("Getting Started"), "Getting Started;")
  })

  test("does not add semicolon when text ends with period", () => {
    assert.strictEqual(injectBlockPauses("This is a sentence."), "This is a sentence.")
  })

  test("does not add semicolon when text ends with exclamation mark", () => {
    assert.strictEqual(injectBlockPauses("Wow!"), "Wow!")
  })

  test("does not add semicolon when text ends with question mark", () => {
    assert.strictEqual(injectBlockPauses("How are you?"), "How are you?")
  })

  test("does not add semicolon when text ends with semicolon", () => {
    assert.strictEqual(injectBlockPauses("already paused;"), "already paused;")
  })

  test("does not add semicolon when text ends with colon", () => {
    assert.strictEqual(injectBlockPauses("Note:"), "Note:")
  })

  test("appends semicolon to list item text", () => {
    assert.strictEqual(injectBlockPauses("Install dependencies"), "Install dependencies;")
  })

  test("appends semicolon to text ending with a number", () => {
    assert.strictEqual(injectBlockPauses("Chapter 3"), "Chapter 3;")
  })

  test("appends semicolon to text ending with a closing parenthesis", () => {
    assert.strictEqual(injectBlockPauses("see above)"), "see above);")
  })

  test("handles single word", () => {
    assert.strictEqual(injectBlockPauses("Overview"), "Overview;")
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

    const idx0 = sentenceIndexForTime(0, cumulative, 1)
    assert.strictEqual(idx0, 0)

    const idxEnd = sentenceIndexForTime(duration, cumulative, 1)
    assert.ok(idxEnd >= sentences.length - 1)
  })

  test("clean text then split preserves sentence structure", () => {
    const dirty = "## Heading\n\n**Bold sentence.** Normal _sentence_ here! Last one?"
    const cleaned = cleanText(dirty)
    const sentences = splitIntoSentences(cleaned)
    assert.ok(sentences.length >= 3)
    for (const s of sentences) {
      assert.ok(!s.includes("#"))
      assert.ok(!s.includes("**"))
      assert.ok(!s.includes("_"))
    }
  })

  test("speed changes correctly scale duration", () => {
    const words = 300
    const dur1x = estimateDuration(words, 1)
    const dur2x = estimateDuration(words, 2)
    const dur05x = estimateDuration(words, 0.5)

    assert.strictEqual(dur1x, 120)
    assert.strictEqual(dur2x, 60)
    assert.strictEqual(dur05x, 240)
  })

  test("seek position is consistent across speed changes", () => {
    const cumWords = [50, 100, 150, 200]
    const idx1x = sentenceIndexForTime(40, cumWords, 1)
    const idx2x = sentenceIndexForTime(20, cumWords, 2)
    assert.strictEqual(idx1x, idx2x)
  })

  test("emoji-heavy text is cleaned and split correctly", () => {
    const input = "🏡 Home sweet home. 📚 Read all the books! 🎤 Give a talk?"
    const cleaned = cleanText(input)
    assert.ok(!cleaned.includes("🏡"))
    assert.ok(!cleaned.includes("📚"))
    assert.ok(!cleaned.includes("🎤"))
    const sentences = splitIntoSentences(cleaned)
    assert.ok(sentences.length >= 3)
  })

  test("trailing text without punctuation is captured in pipeline", () => {
    const text = "First part. Second part without ending"
    const sentences = splitIntoSentences(text)
    assert.strictEqual(sentences.length, 2)
    assert.ok(sentences[1].includes("Second part without ending"))
  })

  test("block pauses are injected before sentence splitting", () => {
    // Simulates the pipeline: cleanText → injectBlockPauses → join → splitIntoSentences
    const blocks = ["Introduction", "First sentence.", "Key takeaway"]
    const processed = blocks.map((b) => injectBlockPauses(cleanText(b)))
    assert.strictEqual(processed[0], "Introduction;")
    assert.strictEqual(processed[1], "First sentence.")
    assert.strictEqual(processed[2], "Key takeaway;")

    const fullText = processed.join(" ")
    const sentences = splitIntoSentences(fullText)
    // The semicolons don't split sentences (only .!? do), but they
    // still cause the synthesiser to insert a pause.
    assert.ok(sentences.length >= 1)
  })

  test("block pauses create natural breaks for headings and list items", () => {
    // Typical page structure: heading, paragraph, list items
    const blocks = [
      "Getting Started",         // heading — no punctuation
      "This guide walks you through setup.", // paragraph — has period
      "Install Node.js",         // list item — no punctuation
      "Run npm install",         // list item — no punctuation
      "Open the browser",        // list item — no punctuation
    ]
    const processed = blocks.map((b) => injectBlockPauses(cleanText(b)))
    assert.strictEqual(processed[0], "Getting Started;")
    assert.strictEqual(processed[1], "This guide walks you through setup.")
    assert.strictEqual(processed[2], "Install Node.js;")
    assert.strictEqual(processed[3], "Run npm install;")
    assert.strictEqual(processed[4], "Open the browser;")
  })
})

// ---------------------------------------------------------------------------
// Property-based tests
//
// These use randomised inputs to check invariants that must hold for *any*
// input, not just hand-picked examples.
// ---------------------------------------------------------------------------

const ALPHANUMERIC_CHARS = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

/** Simple PRNG-style random string generators for property tests. */
function randomAlphaNum(len: number): string {
  let out = ""
  for (let i = 0; i < len; i++) out += ALPHANUMERIC_CHARS[Math.floor(Math.random() * ALPHANUMERIC_CHARS.length)]
  return out
}

function randomSentences(count: number): string {
  const delimiters = [".", "!", "?"]
  return Array.from({ length: count }, () => {
    const words = Math.floor(Math.random() * 10) + 1
    const text = Array.from({ length: words }, () => randomAlphaNum(Math.floor(Math.random() * 8) + 1)).join(" ")
    return text + delimiters[Math.floor(Math.random() * delimiters.length)]
  }).join(" ")
}

// 50 iterations balances meaningful coverage with fast execution (~300 ms total).
const PROPERTY_ITERATIONS = 50

describe("Property-based: stripEmojis", () => {
  test("never increases string length", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = randomAlphaNum(20) + "🎉🇺🇸👋🏽" + randomAlphaNum(20)
      assert.ok(stripEmojis(input).length <= input.length)
    }
  })

  test("ASCII-only input is returned unchanged", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = randomAlphaNum(Math.floor(Math.random() * 100))
      assert.strictEqual(stripEmojis(input), input)
    }
  })

  test("output never contains Extended_Pictographic codepoints", () => {
    const emojiSamples = ["😀", "🌍", "🏡", "📚", "🎤", "❤️", "🇫🇷", "👨‍👩‍👧"]
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const emoji = emojiSamples[Math.floor(Math.random() * emojiSamples.length)]
      const input = randomAlphaNum(10) + emoji + randomAlphaNum(10)
      const output = stripEmojis(input)
      assert.ok(!/\p{Extended_Pictographic}/u.test(output), `Found emoji in output: "${output}"`)
    }
  })
})

describe("Property-based: splitIntoSentences", () => {
  test("joining split sentences reconstructs the original words", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const count = Math.floor(Math.random() * 5) + 1
      const input = randomSentences(count)
      const sentences = splitIntoSentences(input)
      const rejoined = sentences.join(" ")
      // Every word from the original must appear in the rejoined result
      for (const word of input.split(/\s+/).filter(Boolean)) {
        const stripped = word.replace(/[.!?]/g, "")
        if (stripped) {
          assert.ok(rejoined.includes(stripped), `Lost word "${stripped}" from "${input}"`)
        }
      }
    }
  })

  test("never returns empty strings", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = randomSentences(Math.floor(Math.random() * 5) + 1)
      const sentences = splitIntoSentences(input)
      for (const s of sentences) {
        assert.ok(s.length > 0, `Empty string in result for input "${input}"`)
      }
    }
  })
})

describe("Property-based: wordCount", () => {
  test("non-negative for any input", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = randomAlphaNum(Math.floor(Math.random() * 100))
      assert.ok(wordCount(input) >= 0)
    }
  })

  test("single word gives count 1", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const word = randomAlphaNum(Math.floor(Math.random() * 10) + 1).replace(/\s/g, "x")
      if (word.trim()) {
        assert.strictEqual(wordCount(word), 1)
      }
    }
  })
})

describe("Property-based: estimateDuration + formatTime", () => {
  test("duration is non-negative for non-negative words and positive rate", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const words = Math.floor(Math.random() * 1000)
      const rate = 0.5 + Math.random() * 1.5
      const dur = estimateDuration(words, rate)
      assert.ok(dur >= 0, `Negative duration for words=${words}, rate=${rate}`)
    }
  })

  test("formatTime always matches m:ss pattern", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const sec = Math.random() * 7200
      const result = formatTime(sec)
      assert.ok(/^\d+:\d{2}$/.test(result), `Bad format: "${result}" for sec=${sec}`)
    }
  })

  test("doubling rate halves duration", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const words = Math.floor(Math.random() * 500) + 1
      const rate = 0.5 + Math.random() * 1.5
      const dur1 = estimateDuration(words, rate)
      const dur2 = estimateDuration(words, rate * 2)
      assert.ok(Math.abs(dur1 / 2 - dur2) < 0.001, `Half invariant failed: ${dur1} / 2 ≠ ${dur2}`)
    }
  })
})

describe("Property-based: buildCumulativeWords", () => {
  test("output length equals input length", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const len = Math.floor(Math.random() * 20)
      const input = Array.from({ length: len }, () => Math.floor(Math.random() * 50))
      assert.strictEqual(buildCumulativeWords(input).length, len)
    }
  })

  test("values are monotonically non-decreasing", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = Array.from({ length: Math.floor(Math.random() * 20) + 1 }, () =>
        Math.floor(Math.random() * 50),
      )
      const cum = buildCumulativeWords(input)
      for (let j = 1; j < cum.length; j++) {
        assert.ok(cum[j] >= cum[j - 1], `Not monotonic at index ${j}: ${cum[j - 1]} > ${cum[j]}`)
      }
    }
  })

  test("last element equals sum of inputs", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = Array.from({ length: Math.floor(Math.random() * 20) + 1 }, () =>
        Math.floor(Math.random() * 50),
      )
      const cum = buildCumulativeWords(input)
      const total = input.reduce((a, b) => a + b, 0)
      assert.strictEqual(cum[cum.length - 1], total)
    }
  })
})

describe("Property-based: sentenceIndexForTime", () => {
  test("always returns a valid index for non-empty cumulative arrays", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const len = Math.floor(Math.random() * 10) + 1
      const counts = Array.from({ length: len }, () => Math.floor(Math.random() * 50) + 1)
      const cum = buildCumulativeWords(counts)
      const totalDur = estimateDuration(cum[cum.length - 1], 1)
      const targetSec = Math.random() * totalDur * 1.5 // sometimes beyond end
      const idx = sentenceIndexForTime(targetSec, cum, 1)
      assert.ok(idx >= 0, `Negative index for targetSec=${targetSec}`)
      assert.ok(idx < cum.length, `Index ${idx} out of bounds (len=${cum.length})`)
    }
  })

  test("higher time never gives a lower index", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const len = Math.floor(Math.random() * 10) + 1
      const counts = Array.from({ length: len }, () => Math.floor(Math.random() * 50) + 1)
      const cum = buildCumulativeWords(counts)
      const t1 = Math.random() * 60
      const t2 = t1 + Math.random() * 60
      const idx1 = sentenceIndexForTime(t1, cum, 1)
      const idx2 = sentenceIndexForTime(t2, cum, 1)
      assert.ok(idx2 >= idx1, `Monotonicity violated: idx(${t1})=${idx1} > idx(${t2})=${idx2}`)
    }
  })
})

describe("Property-based: cleanText", () => {
  test("output length never exceeds input length", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = randomAlphaNum(Math.floor(Math.random() * 100))
      assert.ok(cleanText(input).length <= input.length)
    }
  })

  test("output never contains markdown characters", () => {
    const mdChars = /[#*_`~\[\](){}<>|]/
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = "## " + randomAlphaNum(30) + " **bold** _italic_ `code`"
      const output = cleanText(input)
      assert.ok(!mdChars.test(output), `Markdown chars in output: "${output}"`)
    }
  })
})

describe("Property-based: injectBlockPauses", () => {
  test("output length is never less than input length", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = randomAlphaNum(Math.floor(Math.random() * 50) + 1).trim()
      if (!input) continue
      assert.ok(
        injectBlockPauses(input).length >= input.length,
        `Output shorter than input for "${input}"`,
      )
    }
  })

  test("output always ends with punctuation", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = randomAlphaNum(Math.floor(Math.random() * 50) + 1).trim()
      if (!input) continue
      const output = injectBlockPauses(input)
      assert.ok(
        /[.!?;:]$/.test(output),
        `Output "${output}" does not end with pause-producing punctuation`,
      )
    }
  })

  test("idempotent — applying twice gives same result as once", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const input = randomAlphaNum(Math.floor(Math.random() * 50) + 1).trim()
      if (!input) continue
      const once = injectBlockPauses(input)
      const twice = injectBlockPauses(once)
      assert.strictEqual(once, twice, `Not idempotent for "${input}": "${once}" → "${twice}"`)
    }
  })

  test("text already ending with punctuation is unchanged", () => {
    const endings = [".", "!", "?", ";", ":"]
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const base = randomAlphaNum(Math.floor(Math.random() * 30) + 1).trim()
      if (!base) continue
      const ending = endings[Math.floor(Math.random() * endings.length)]
      const input = base + ending
      assert.strictEqual(
        injectBlockPauses(input),
        input,
        `Unexpected modification of "${input}"`,
      )
    }
  })
})
