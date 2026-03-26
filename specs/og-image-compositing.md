# 🖼️ OG Image Compositing — Product & Engineering Design Spec

## 📋 Overview

🎯 The OG image compositing system enhances auto-generated Open Graph social preview images by incorporating content-specific images from notes alongside branded metadata.

🏗️ When a note contains an embedded image or references a YouTube video, the OG preview combines:
1. **Branded text metadata** — title, description, date, reading time, tags, site icon
2. **Content image** — the first embedded image from the note or a YouTube video thumbnail

📐 Notes without embedded images continue to use the existing text-only OG template.

---

## 🧩 Architecture

```
                    processOgImage()
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
    extractFirstLocal  extractYouTube  (no image)
    ImageRef()         VideoId()
            │            │            │
            ▼            ▼            │
    loadContentImage   fetchYouTube   │
    Base64()           ThumbnailBase64()
            │            │            │
            └────────────┼────────────┘
                         ▼
               generateSocialImage()
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
    defaultImage (with image) defaultImage (text-only)
    ┌──────────────┬──────┐  ┌──────────────────┐
    │ Title/Meta   │ IMG  │  │ Title/Meta       │
    │ Description  │      │  │ Description      │
    │ Tags         │      │  │ Tags             │
    └──────────────┴──────┘  └──────────────────┘
```

---

## 🔄 Content Image Resolution

### 📎 Local Image Extraction

🔍 The system scans `fileData.text` (raw markdown) for the first local image reference:

1. **Markdown image syntax**: `![alt](../relative/path.jpg)` — must not be an HTTP URL
2. **Obsidian wiki-link syntax**: `![[image.jpg]]` or `![[attachments/image.png]]`

📌 Priority: markdown images are checked first, then Obsidian wiki-links.

🚫 HTTP/HTTPS URLs in markdown image syntax are skipped (these are typically YouTube embeds, not local files).

### 🎬 YouTube Thumbnail Extraction

🔍 For video pages, the system extracts the YouTube video ID:

1. **Frontmatter field**: `youtube: https://youtu.be/{VIDEO_ID}` (checked first)
2. **Text content**: any `youtu.be/{ID}` or `youtube.com/watch?v={ID}` URL in the markdown body

📸 Thumbnail URLs tried in order:
1. `https://img.youtube.com/vi/{ID}/maxresdefault.jpg` (1280×720 when available)
2. `https://img.youtube.com/vi/{ID}/hqdefault.jpg` (480×360 fallback)

🔒 Thumbnails with width less than 200px are rejected (placeholder detection).

### 🗂️ Path Resolution

📁 Local image references are resolved relative to the markdown file's directory, matching how Quartz resolves asset paths during build. For example:

- File: `content/ai-blog/2026-03-14-post.md`
- Reference: `../ai-blog-2026-03-14-post.jpg`
- Resolved: `content/ai-blog-2026-03-14-post.jpg`

---

## 🎨 Template Layout

### 📐 With Content Image (1200×630 px)

```
┌──────────────────────────────────────────────────────┐
│ [🌐 icon] bagrounds.org   📅 date   ⏱ reading time │
├──────────────────────────────────┬───────────────────┤
│                                  │                   │
│  Title (up to 3 lines, 48-56px) │   ┌───────────┐   │
│                                  │   │           │   │
│  Description (up to 5 lines)     │   │  Content  │   │
│                                  │   │   Image   │   │
│  #tag1 #tag2 #tag3               │   │  400×400  │   │
│                                  │   └───────────┘   │
└──────────────────────────────────┴───────────────────┘
          ~55% width                    ~45% width
```

### 📐 Without Content Image (1200×630 px)

```
┌──────────────────────────────────────────────────────┐
│ [🌐 icon] bagrounds.org  📅 date  ⏱ time  #tags    │
│                                                      │
│  Title (up to 2 lines, 64-72px)                      │
│                                                      │
│  Description (up to 8 lines)                         │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

## 🗃️ Caching

### 🔑 Cache Key

The OG image cache hash includes:
- Title, description, tags, date
- Color scheme, width, height
- **Content image reference** (local path or `yt:{videoId}`)
- Cache version number

📝 When a note's embedded image changes, the cache key changes, triggering regeneration.

### 💾 Cache Layers

1. **OG image cache**: `.quartz-cache/og-images/{hash}.webp` — final composited OG images
2. **Content image cache**: in-memory `Map<string, string>` for base64-encoded resized images (per build)
3. **YouTube thumbnail cache**: `.quartz-cache/yt-thumbnails/{videoId}.jpg` — raw downloaded thumbnails (persists across builds)

---

## 🖼️ Image Processing

### 📏 Content Image Sizing

- Target: 480×480 pixels (pre-resize before base64 encoding)
- Fit strategy: `cover` (crops to fill, preserving aspect ratio)
- Format: JPEG at 80% quality
- Encoding: base64 data URI for Satori rendering

### 🖥️ Final OG Image

- Dimensions: 1200×630 pixels
- Format: WebP at 40% quality (Satori SVG → Sharp WebP)
- Content image rendered at 400×400 with 16px border radius and a subtle border

---

## 📁 Files

| What | Path |
|------|------|
| OG utilities + template | `quartz/util/og.tsx` |
| OG emitter plugin | `quartz/plugins/emitters/ogImage.tsx` |
| OG utility tests | `quartz/util/og.test.ts` |
| This spec | `specs/og-image-compositing.md` |

---

## 🧪 Testing

21 unit tests covering:
- `extractFirstLocalImageRef`: markdown images, wiki-links, HTTP filtering, extension handling
- `extractYouTubeVideoId`: frontmatter extraction, text extraction, URL format variants
- `resolveImagePath`: relative path resolution, content directory boundaries
