import test, { describe } from "node:test"
import assert from "node:assert"
import {
  AUTOPLAY_READ_KEY,
  AUTOPLAY_ENABLED_KEY,
  AUTOPLAY_PENDING_KEY,
  NEXT_MARKER,
  BACK_MARKER,
  extractNavLinks,
  urlToSlug,
  isIndexOrHome,
  decodeReadPages,
  encodeReadPages,
  resolveNextUrl,
  type NavLinks,
  type LinkInfo,
} from "./tts.autoplay"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
describe("Auto-play constants", () => {
  test("storage keys are non-empty strings", () => {
    for (const key of [AUTOPLAY_READ_KEY, AUTOPLAY_ENABLED_KEY, AUTOPLAY_PENDING_KEY]) {
      assert.strictEqual(typeof key, "string")
      assert.ok(key.length > 0)
    }
  })

  test("storage keys are distinct", () => {
    const keys = new Set([AUTOPLAY_READ_KEY, AUTOPLAY_ENABLED_KEY, AUTOPLAY_PENDING_KEY])
    assert.strictEqual(keys.size, 3)
  })

  test("marker emoji are single grapheme clusters", () => {
    assert.ok(NEXT_MARKER.length <= 2)
    assert.ok(BACK_MARKER.length <= 2)
  })
})

// ---------------------------------------------------------------------------
// extractNavLinks
// ---------------------------------------------------------------------------
describe("extractNavLinks", () => {
  test("returns nulls for empty array", () => {
    const result = extractNavLinks([])
    assert.strictEqual(result.next, null)
    assert.strictEqual(result.back, null)
  })

  test("finds next link by marker", () => {
    const links: LinkInfo[] = [
      { text: "Home", href: "/index" },
      { text: "⏭️", href: "/series/next-post" },
    ]
    const result = extractNavLinks(links)
    assert.strictEqual(result.next, "/series/next-post")
    assert.strictEqual(result.back, null)
  })

  test("finds back link by marker", () => {
    const links: LinkInfo[] = [
      { text: "⏮️", href: "/series/prev-post" },
      { text: "Blog", href: "/blog" },
    ]
    const result = extractNavLinks(links)
    assert.strictEqual(result.next, null)
    assert.strictEqual(result.back, "/series/prev-post")
  })

  test("finds both next and back links", () => {
    const links: LinkInfo[] = [
      { text: "Home", href: "/" },
      { text: "⏮️ Previous", href: "/series/prev" },
      { text: "Next ⏭️", href: "/series/next" },
    ]
    const result = extractNavLinks(links)
    assert.strictEqual(result.next, "/series/next")
    assert.strictEqual(result.back, "/series/prev")
  })

  test("marker can appear anywhere in link text", () => {
    const links: LinkInfo[] = [
      { text: "Go to ⏭️ next article", href: "/next" },
      { text: "Back ⏮️ to start", href: "/prev" },
    ]
    const result = extractNavLinks(links)
    assert.strictEqual(result.next, "/next")
    assert.strictEqual(result.back, "/prev")
  })

  test("takes first match when multiple next links exist", () => {
    const links: LinkInfo[] = [
      { text: "⏭️", href: "/first" },
      { text: "⏭️", href: "/second" },
    ]
    const result = extractNavLinks(links)
    assert.strictEqual(result.next, "/first")
  })

  test("ignores links without markers", () => {
    const links: LinkInfo[] = [
      { text: "Some page", href: "/page-a" },
      { text: "Another page", href: "/page-b" },
    ]
    const result = extractNavLinks(links)
    assert.strictEqual(result.next, null)
    assert.strictEqual(result.back, null)
  })
})

// ---------------------------------------------------------------------------
// urlToSlug
// ---------------------------------------------------------------------------
describe("urlToSlug", () => {
  test("strips leading slash", () => {
    assert.strictEqual(urlToSlug("/articles/my-post"), "articles/my-post")
  })

  test("strips trailing slash", () => {
    assert.strictEqual(urlToSlug("/articles/my-post/"), "articles/my-post")
  })

  test("preserves trailing /index for isIndexOrHome detection", () => {
    assert.strictEqual(urlToSlug("/auto-blog-zero/index"), "auto-blog-zero/index")
  })

  test("handles full URL", () => {
    assert.strictEqual(
      urlToSlug("https://bagrounds.org/auto-blog-zero/2026-03-15-weekly-recap"),
      "auto-blog-zero/2026-03-15-weekly-recap",
    )
  })

  test("strips hash fragment", () => {
    assert.strictEqual(urlToSlug("/articles/my-post#section"), "articles/my-post")
  })

  test("handles root path", () => {
    assert.strictEqual(urlToSlug("/"), "")
  })

  test("handles bare slug", () => {
    assert.strictEqual(urlToSlug("articles/my-post"), "articles/my-post")
  })

  test("handles index at root", () => {
    assert.strictEqual(urlToSlug("/index"), "index")
  })
})

// ---------------------------------------------------------------------------
// isIndexOrHome
// ---------------------------------------------------------------------------
describe("isIndexOrHome", () => {
  test("empty string is home", () => {
    assert.strictEqual(isIndexOrHome(""), true)
  })

  test("'index' is home", () => {
    assert.strictEqual(isIndexOrHome("index"), true)
  })

  test("series index page is index", () => {
    assert.strictEqual(isIndexOrHome("auto-blog-zero/index"), true)
  })

  test("leading slash index", () => {
    assert.strictEqual(isIndexOrHome("/index"), true)
  })

  test("regular article is not index", () => {
    assert.strictEqual(isIndexOrHome("auto-blog-zero/2026-03-15-weekly-recap"), false)
  })

  test("deeply nested index is detected", () => {
    assert.strictEqual(isIndexOrHome("a/b/c/index"), true)
  })

  test("page containing 'index' in name is not index", () => {
    assert.strictEqual(isIndexOrHome("articles/indexed-search"), false)
  })

  test("trailing slash root is home", () => {
    assert.strictEqual(isIndexOrHome("/"), true)
  })
})

// ---------------------------------------------------------------------------
// decodeReadPages / encodeReadPages
// ---------------------------------------------------------------------------
describe("decodeReadPages", () => {
  test("null returns empty set", () => {
    const result = decodeReadPages(null)
    assert.strictEqual(result.size, 0)
  })

  test("empty string returns empty set", () => {
    const result = decodeReadPages("")
    assert.strictEqual(result.size, 0)
  })

  test("valid JSON array returns set of slugs", () => {
    const result = decodeReadPages('["a","b","c"]')
    assert.strictEqual(result.size, 3)
    assert.ok(result.has("a"))
    assert.ok(result.has("b"))
    assert.ok(result.has("c"))
  })

  test("invalid JSON returns empty set", () => {
    const result = decodeReadPages("not valid json")
    assert.strictEqual(result.size, 0)
  })

  test("non-array JSON returns empty set", () => {
    const result = decodeReadPages('{"a":1}')
    assert.strictEqual(result.size, 0)
  })

  test("deduplicates entries", () => {
    const result = decodeReadPages('["a","a","b"]')
    assert.strictEqual(result.size, 2)
  })
})

describe("encodeReadPages", () => {
  test("empty set encodes to empty array", () => {
    assert.strictEqual(encodeReadPages(new Set()), "[]")
  })

  test("set of slugs encodes to JSON array", () => {
    const pages = new Set(["a", "b", "c"])
    const encoded = encodeReadPages(pages)
    const decoded = JSON.parse(encoded)
    assert.ok(Array.isArray(decoded))
    assert.strictEqual(decoded.length, 3)
    assert.ok(decoded.includes("a"))
    assert.ok(decoded.includes("b"))
    assert.ok(decoded.includes("c"))
  })

  test("round-trip preserves data", () => {
    const original = new Set(["auto-blog-zero/post-1", "chickie-loo/post-2"])
    const encoded = encodeReadPages(original)
    const decoded = decodeReadPages(encoded)
    assert.deepStrictEqual(decoded, original)
  })
})

// ---------------------------------------------------------------------------
// resolveNextUrl
// ---------------------------------------------------------------------------
describe("resolveNextUrl", () => {
  test("returns null when no links at all", () => {
    const result = resolveNextUrl({ next: null, back: null }, [], new Set())
    assert.strictEqual(result, null)
  })

  test("prefers next nav link", () => {
    const navLinks: NavLinks = {
      next: "/series/next-post",
      back: "/series/prev-post",
    }
    const result = resolveNextUrl(navLinks, ["/other/page"], new Set())
    assert.strictEqual(result, "/series/next-post")
  })

  test("falls back to back nav link when next is already read", () => {
    const navLinks: NavLinks = {
      next: "/series/next-post",
      back: "/series/prev-post",
    }
    const readPages = new Set(["series/next-post"])
    const result = resolveNextUrl(navLinks, ["/other/page"], readPages)
    assert.strictEqual(result, "/series/prev-post")
  })

  test("falls back to article links when both nav links are read", () => {
    const navLinks: NavLinks = {
      next: "/series/next-post",
      back: "/series/prev-post",
    }
    const readPages = new Set(["series/next-post", "series/prev-post"])
    const articleLinks = ["/other/unread-page"]
    const result = resolveNextUrl(navLinks, articleLinks, readPages)
    assert.strictEqual(result, "/other/unread-page")
  })

  test("skips index pages in article links", () => {
    const navLinks: NavLinks = { next: null, back: null }
    const articleLinks = ["/auto-blog-zero/index", "/auto-blog-zero/real-post"]
    const result = resolveNextUrl(navLinks, articleLinks, new Set())
    assert.strictEqual(result, "/auto-blog-zero/real-post")
  })

  test("skips home page in article links", () => {
    const navLinks: NavLinks = { next: null, back: null }
    const articleLinks = ["/", "/articles/good-post"]
    const result = resolveNextUrl(navLinks, articleLinks, new Set())
    assert.strictEqual(result, "/articles/good-post")
  })

  test("skips already-read article links", () => {
    const navLinks: NavLinks = { next: null, back: null }
    const articleLinks = ["/articles/read-post", "/articles/unread-post"]
    const readPages = new Set(["articles/read-post"])
    const result = resolveNextUrl(navLinks, articleLinks, readPages)
    assert.strictEqual(result, "/articles/unread-post")
  })

  test("returns null when everything is read", () => {
    const navLinks: NavLinks = {
      next: "/series/next",
      back: "/series/prev",
    }
    const readPages = new Set(["series/next", "series/prev", "articles/other"])
    const articleLinks = ["/articles/other"]
    const result = resolveNextUrl(navLinks, articleLinks, readPages)
    assert.strictEqual(result, null)
  })

  test("returns null when only index/home pages remain", () => {
    const navLinks: NavLinks = { next: null, back: null }
    const articleLinks = ["/", "/index", "/series/index"]
    const result = resolveNextUrl(navLinks, articleLinks, new Set())
    assert.strictEqual(result, null)
  })

  test("picks first unread article link in document order", () => {
    const navLinks: NavLinks = { next: null, back: null }
    const articleLinks = ["/a/first", "/a/second", "/a/third"]
    const readPages = new Set(["a/first"])
    const result = resolveNextUrl(navLinks, articleLinks, readPages)
    assert.strictEqual(result, "/a/second")
  })

  test("next nav link with null back still works", () => {
    const navLinks: NavLinks = { next: "/series/only-next", back: null }
    const result = resolveNextUrl(navLinks, [], new Set())
    assert.strictEqual(result, "/series/only-next")
  })

  test("back nav link with null next still works", () => {
    const navLinks: NavLinks = { next: null, back: "/series/only-back" }
    const result = resolveNextUrl(navLinks, [], new Set())
    assert.strictEqual(result, "/series/only-back")
  })

  test("skips next nav link when it is an index page", () => {
    const navLinks: NavLinks = { next: "/series/index", back: null }
    const articleLinks = ["/series/real-post"]
    const result = resolveNextUrl(navLinks, articleLinks, new Set())
    assert.strictEqual(result, "/series/real-post")
  })

  test("skips back nav link when it is an index page", () => {
    const navLinks: NavLinks = { next: null, back: "/series/index" }
    const articleLinks = ["/series/real-post"]
    const result = resolveNextUrl(navLinks, articleLinks, new Set())
    assert.strictEqual(result, "/series/real-post")
  })

  test("returns null when both nav links are index pages and no article links", () => {
    const navLinks: NavLinks = { next: "/a/index", back: "/b/index" }
    const result = resolveNextUrl(navLinks, [], new Set())
    assert.strictEqual(result, null)
  })

  test("falls through index nav links to article links", () => {
    const navLinks: NavLinks = { next: "/series/index", back: "/other/index" }
    const articleLinks = ["/articles/good-post"]
    const result = resolveNextUrl(navLinks, articleLinks, new Set())
    assert.strictEqual(result, "/articles/good-post")
  })
})

// ---------------------------------------------------------------------------
// Integration tests
// ---------------------------------------------------------------------------
describe("Auto-play integration", () => {
  test("typical series navigation flow", () => {
    // Simulate reading through a 3-post series
    const posts = ["series/post-1", "series/post-2", "series/post-3"]
    const readPages = new Set<string>()

    // At post-1: has next link to post-2
    const nav1: NavLinks = { next: "/series/post-2", back: null }
    const next1 = resolveNextUrl(nav1, [], readPages)
    assert.strictEqual(next1, "/series/post-2")
    readPages.add(posts[0])

    // At post-2: has both links
    const nav2: NavLinks = { next: "/series/post-3", back: "/series/post-1" }
    const next2 = resolveNextUrl(nav2, [], readPages)
    assert.strictEqual(next2, "/series/post-3")
    readPages.add(posts[1])

    // At post-3: last post, only back link (already read)
    const nav3: NavLinks = { next: null, back: "/series/post-2" }
    const next3 = resolveNextUrl(nav3, [], readPages)
    assert.strictEqual(next3, null) // series complete
    readPages.add(posts[2])
  })

  test("fallback to BFS when series is exhausted", () => {
    const readPages = new Set(["series/post-1", "series/post-2", "series/post-3"])
    const navLinks: NavLinks = { next: null, back: "/series/post-2" }
    const articleLinks = ["/series/index", "/topics/cool-topic", "/articles/linked-article"]

    const result = resolveNextUrl(navLinks, articleLinks, readPages)
    // Should skip index, skip already-read series posts, find the topic
    assert.strictEqual(result, "/topics/cool-topic")
  })

  test("round-trip encode/decode preserves read tracking", () => {
    const pages = new Set(["a/post-1", "b/post-2"])
    const stored = encodeReadPages(pages)
    const restored = decodeReadPages(stored)

    const navLinks: NavLinks = { next: "/a/post-1", back: null }
    const result = resolveNextUrl(navLinks, ["/a/post-1", "/c/post-3"], restored)
    // post-1 is read, so should fall through to BFS
    assert.strictEqual(result, "/c/post-3")
  })

  test("slug normalisation ensures consistent tracking", () => {
    const readPages = new Set<string>()
    readPages.add(urlToSlug("https://example.com/series/post-1"))

    const navLinks: NavLinks = { next: "/series/post-1", back: null }
    // Even though stored with full URL and resolved with path, should match
    const result = resolveNextUrl(navLinks, [], readPages)
    assert.strictEqual(result, null) // already read
  })
})

// ---------------------------------------------------------------------------
// Property-based tests
// ---------------------------------------------------------------------------
const PROPERTY_ITERATIONS = 50

function randomSlug(): string {
  const segments = Math.floor(Math.random() * 3) + 1
  return Array.from({ length: segments }, () => {
    const len = Math.floor(Math.random() * 10) + 3
    return Array.from({ length: len }, () =>
      "abcdefghijklmnopqrstuvwxyz0123456789-"[Math.floor(Math.random() * 37)],
    ).join("")
  }).join("/")
}

describe("Property-based: urlToSlug", () => {
  test("never starts with a slash", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const slug = randomSlug()
      const result = urlToSlug("/" + slug)
      assert.ok(!result.startsWith("/"), `Slug starts with /: "${result}"`)
    }
  })

  test("never ends with a slash", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const slug = randomSlug()
      const result = urlToSlug("/" + slug + "/")
      assert.ok(!result.endsWith("/"), `Slug ends with /: "${result}"`)
    }
  })

  test("idempotent — applying twice gives same result as once", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const slug = randomSlug()
      const once = urlToSlug("/" + slug)
      const twice = urlToSlug(once)
      assert.strictEqual(once, twice, `Not idempotent for "${slug}": "${once}" → "${twice}"`)
    }
  })
})

describe("Property-based: isIndexOrHome", () => {
  test("slugs not ending with 'index' are not index pages", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const slug = randomSlug()
      // Ensure slug doesn't happen to end with "index"
      const safeSuffix = slug.endsWith("index") ? slug + "-post" : slug
      assert.strictEqual(
        isIndexOrHome(safeSuffix),
        false,
        `"${safeSuffix}" incorrectly identified as index`,
      )
    }
  })

  test("slugs ending with '/index' are always index pages", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const prefix = randomSlug()
      assert.strictEqual(
        isIndexOrHome(prefix + "/index"),
        true,
        `"${prefix}/index" not identified as index`,
      )
    }
  })
})

describe("Property-based: resolveNextUrl", () => {
  test("never returns an index or home page", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const links = Array.from(
        { length: Math.floor(Math.random() * 5) + 1 },
        () => "/" + randomSlug(),
      )
      const result = resolveNextUrl({ next: null, back: null }, links, new Set())
      if (result !== null) {
        const slug = urlToSlug(result)
        assert.ok(!isIndexOrHome(slug), `Returned index/home page: "${result}"`)
      }
    }
  })

  test("never returns an index page from nav links", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const prefix = randomSlug()
      const navLinks: NavLinks = {
        next: "/" + prefix + "/index",
        back: "/" + randomSlug() + "/index",
      }
      const result = resolveNextUrl(navLinks, [], new Set())
      assert.strictEqual(result, null, `Returned index page from nav: "${result}"`)
    }
  })

  test("never returns an already-read page", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const links = Array.from(
        { length: Math.floor(Math.random() * 5) + 1 },
        () => "/" + randomSlug(),
      )
      const readPages = new Set(links.map(urlToSlug))
      const result = resolveNextUrl({ next: null, back: null }, links, readPages)
      assert.strictEqual(result, null, `Returned already-read page from links: ${links.join(", ")}`)
    }
  })

  test("result slug is not in readPages when result is non-null", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const slug1 = randomSlug()
      const slug2 = randomSlug()
      const readPages = new Set([slug1])
      const navLinks: NavLinks = { next: "/" + slug1, back: "/" + slug2 }
      const result = resolveNextUrl(navLinks, [], readPages)
      if (result !== null) {
        assert.ok(
          !readPages.has(urlToSlug(result)),
          `Returned read page: "${result}" (slug: "${urlToSlug(result)}")`,
        )
      }
    }
  })
})

describe("Property-based: encode/decode round-trip", () => {
  test("round-trip preserves all slugs", () => {
    for (let i = 0; i < PROPERTY_ITERATIONS; i++) {
      const slugs = Array.from(
        { length: Math.floor(Math.random() * 10) },
        () => randomSlug(),
      )
      const original = new Set(slugs)
      const encoded = encodeReadPages(original)
      const decoded = decodeReadPages(encoded)
      assert.deepStrictEqual(decoded, original)
    }
  })
})
