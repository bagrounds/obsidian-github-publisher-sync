import test, { describe } from "node:test"
import assert from "node:assert"
import { extractFirstLocalImageRef, extractYouTubeVideoId, resolveImagePath, hashImageFile } from "./og"
import { promises as fs } from "fs"
import path from "path"

describe("extractFirstLocalImageRef", () => {
  test("extracts markdown image with relative path", () => {
    const text = "Some text\n![alt text](../my-image.jpg)\nMore text"
    assert.strictEqual(extractFirstLocalImageRef(text), "../my-image.jpg")
  })

  test("extracts first image when multiple present", () => {
    const text = "![first](../one.jpg)\n![second](../two.png)"
    assert.strictEqual(extractFirstLocalImageRef(text), "../one.jpg")
  })

  test("extracts obsidian wiki link image", () => {
    const text = "Some text\n![[my-image.jpg]]\nMore text"
    assert.strictEqual(extractFirstLocalImageRef(text), "my-image.jpg")
  })

  test("strips attachments prefix from obsidian wiki link", () => {
    const text = "![[attachments/my-image.png]]"
    assert.strictEqual(extractFirstLocalImageRef(text), "my-image.png")
  })

  test("ignores http URLs in markdown images", () => {
    const text = "![alt](https://example.com/image.jpg)\n![[local.png]]"
    assert.strictEqual(extractFirstLocalImageRef(text), "local.png")
  })

  test("ignores YouTube URLs in markdown images", () => {
    const text = "![Video Title](https://youtu.be/abc123def45)\nMore text"
    assert.strictEqual(extractFirstLocalImageRef(text), undefined)
  })

  test("returns undefined when no images present", () => {
    const text = "Just some text\nwith no images"
    assert.strictEqual(extractFirstLocalImageRef(text), undefined)
  })

  test("handles various extensions", () => {
    assert.strictEqual(extractFirstLocalImageRef("![a](./test.webp)"), "./test.webp")
    assert.strictEqual(extractFirstLocalImageRef("![a](./test.gif)"), "./test.gif")
    assert.strictEqual(extractFirstLocalImageRef("![a](./test.jpeg)"), "./test.jpeg")
    assert.strictEqual(extractFirstLocalImageRef("![a](./test.PNG)"), "./test.PNG")
  })

  test("prefers markdown image over obsidian wiki link", () => {
    const text = "![md](../first.jpg)\n![[second.png]]"
    assert.strictEqual(extractFirstLocalImageRef(text), "../first.jpg")
  })

  test("handles real blog post content format", () => {
    const text = `[Home](../index.md) > [AI Blog](./index.md)
# Title
![ai-blog-2026-03-14-the-spa-that-cried-404](../ai-blog-2026-03-14-the-spa-that-cried-404.jpg)

Some content`
    assert.strictEqual(
      extractFirstLocalImageRef(text),
      "../ai-blog-2026-03-14-the-spa-that-cried-404.jpg",
    )
  })
})

describe("extractYouTubeVideoId", () => {
  test("extracts from youtu.be frontmatter URL", () => {
    const fm = { youtube: "https://youtu.be/m2rAkLIyBJg" }
    assert.strictEqual(extractYouTubeVideoId(fm, ""), "m2rAkLIyBJg")
  })

  test("extracts from youtube.com/watch frontmatter URL", () => {
    const fm = { youtube: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }
    assert.strictEqual(extractYouTubeVideoId(fm, ""), "dQw4w9WgXcQ")
  })

  test("extracts from youtu.be in text when no frontmatter", () => {
    const text = "Check out https://youtu.be/abc123def45 for more"
    assert.strictEqual(extractYouTubeVideoId(undefined, text), "abc123def45")
  })

  test("extracts from youtube.com/watch in text", () => {
    const text = "Watch https://youtube.com/watch?v=xyz789abcde here"
    assert.strictEqual(extractYouTubeVideoId(undefined, text), "xyz789abcde")
  })

  test("prefers frontmatter over text", () => {
    const fm = { youtube: "https://youtu.be/FRONTMATTER" }
    const text = "https://youtu.be/TEXTVERSION"
    assert.strictEqual(extractYouTubeVideoId(fm, text), "FRONTMATTER")
  })

  test("returns undefined when no YouTube URL found", () => {
    assert.strictEqual(extractYouTubeVideoId(undefined, "no video here"), undefined)
    assert.strictEqual(extractYouTubeVideoId({}, "no video here"), undefined)
  })

  test("handles markdown image embed with YouTube URL", () => {
    const text = "![Video Title](https://youtu.be/m2rAkLIyBJg)"
    assert.strictEqual(extractYouTubeVideoId(undefined, text), "m2rAkLIyBJg")
  })
})

describe("resolveImagePath", () => {
  test("resolves relative path from markdown file directory", () => {
    const result = resolveImagePath(
      "../my-image.jpg",
      "/home/user/content/ai-blog/post.md",
      "/home/user/content",
    )
    assert.strictEqual(result, "/home/user/content/my-image.jpg")
  })

  test("resolves sibling path", () => {
    const result = resolveImagePath(
      "./image.jpg",
      "/home/user/content/posts/post.md",
      "/home/user/content",
    )
    assert.strictEqual(result, "/home/user/content/posts/image.jpg")
  })

  test("resolves path outside content dir", () => {
    const result = resolveImagePath(
      "../../outside.jpg",
      "/home/user/content/posts/post.md",
      "/home/user/content",
    )
    assert.strictEqual(result, "/home/outside.jpg")
  })

  test("uses contentDir fallback when resolved path is outside content", () => {
    const result = resolveImagePath(
      "bare-image.jpg",
      "/tmp/unrelated/file.md",
      "/home/user/content",
    )
    assert.strictEqual(result, "/home/user/content/bare-image.jpg")
  })

  test("resolves real blog post image reference", () => {
    const result = resolveImagePath(
      "../ai-blog-2026-03-14-the-spa-that-cried-404.jpg",
      "/home/user/content/ai-blog/2026-03-14-the-spa-that-cried-404.md",
      "/home/user/content",
    )
    assert.strictEqual(result, "/home/user/content/ai-blog-2026-03-14-the-spa-that-cried-404.jpg")
  })
})

describe("hashImageFile", () => {
  const tmpDir = path.join("/tmp", "og-test-images")

  test("returns a 16-char hex hash for a valid file", async () => {
    await fs.mkdir(tmpDir, { recursive: true })
    const filePath = path.join(tmpDir, "test-image.bin")
    await fs.writeFile(filePath, "fake image data")
    const hash = await hashImageFile(filePath)
    assert.ok(hash)
    assert.strictEqual(hash!.length, 16)
    assert.match(hash!, /^[0-9a-f]{16}$/)
  })

  test("returns undefined for a missing file", async () => {
    const hash = await hashImageFile(path.join(tmpDir, "nonexistent.jpg"))
    assert.strictEqual(hash, undefined)
  })

  test("returns different hashes for different content", async () => {
    await fs.mkdir(tmpDir, { recursive: true })
    const fileA = path.join(tmpDir, "a.bin")
    const fileB = path.join(tmpDir, "b.bin")
    await fs.writeFile(fileA, "content A")
    await fs.writeFile(fileB, "content B")
    const hashA = await hashImageFile(fileA)
    const hashB = await hashImageFile(fileB)
    assert.ok(hashA)
    assert.ok(hashB)
    assert.notStrictEqual(hashA, hashB)
  })

  test("returns same hash for identical content", async () => {
    await fs.mkdir(tmpDir, { recursive: true })
    const fileA = path.join(tmpDir, "same1.bin")
    const fileB = path.join(tmpDir, "same2.bin")
    await fs.writeFile(fileA, "identical content")
    await fs.writeFile(fileB, "identical content")
    const hashA = await hashImageFile(fileA)
    const hashB = await hashImageFile(fileB)
    assert.strictEqual(hashA, hashB)
  })
})
