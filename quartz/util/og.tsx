import { promises as fs } from "fs"
import { FontWeight, SatoriOptions } from "satori/wasm"
import { GlobalConfiguration } from "../cfg"
import { QuartzPluginData } from "../plugins/vfile"
import { JSXInternal } from "preact/src/jsx"
import { FontSpecification, getFontSpecificationName, ThemeKey } from "./theme"
import path from "path"
import { QUARTZ } from "./path"
import { formatDate, getDate } from "../components/Date"
import readingTime from "reading-time"
import { i18n } from "../i18n"
import chalk from "chalk"
import sharp from "sharp"
import { createHash } from "crypto"

const defaultHeaderWeight = [700]
const defaultBodyWeight = [400]

export async function getSatoriFonts(headerFont: FontSpecification, bodyFont: FontSpecification) {
  // Get all weights for header and body fonts
  const headerWeights: FontWeight[] = (
    typeof headerFont === "string"
      ? defaultHeaderWeight
      : (headerFont.weights ?? defaultHeaderWeight)
  ) as FontWeight[]
  const bodyWeights: FontWeight[] = (
    typeof bodyFont === "string" ? defaultBodyWeight : (bodyFont.weights ?? defaultBodyWeight)
  ) as FontWeight[]

  const headerFontName = typeof headerFont === "string" ? headerFont : headerFont.name
  const bodyFontName = typeof bodyFont === "string" ? bodyFont : bodyFont.name

  // Fetch fonts for all weights and convert to satori format in one go
  const headerFontPromises = headerWeights.map(async (weight) => {
    const data = await fetchTtf(headerFontName, weight)
    if (!data) return null
    return {
      name: headerFontName,
      data,
      weight,
      style: "normal" as const,
    }
  })

  const bodyFontPromises = bodyWeights.map(async (weight) => {
    const data = await fetchTtf(bodyFontName, weight)
    if (!data) return null
    return {
      name: bodyFontName,
      data,
      weight,
      style: "normal" as const,
    }
  })

  const [headerFonts, bodyFonts] = await Promise.all([
    Promise.all(headerFontPromises),
    Promise.all(bodyFontPromises),
  ])

  // Filter out any failed fetches and combine header and body fonts
  const fonts: SatoriOptions["fonts"] = [
    ...headerFonts.filter((font): font is NonNullable<typeof font> => font !== null),
    ...bodyFonts.filter((font): font is NonNullable<typeof font> => font !== null),
  ]

  return fonts
}

/**
 * Get the `.ttf` file of a google font
 * @param fontName name of google font
 * @param weight what font weight to fetch font
 * @returns `.ttf` file of google font
 */
export async function fetchTtf(
  rawFontName: string,
  weight: FontWeight,
): Promise<Buffer<ArrayBufferLike> | undefined> {
  const fontName = rawFontName.replaceAll(" ", "+")
  const cacheKey = `${fontName}-${weight}`
  const cacheDir = path.join(QUARTZ, ".quartz-cache", "fonts")
  const cachePath = path.join(cacheDir, cacheKey)

  // Check if font exists in cache
  try {
    await fs.access(cachePath)
    return fs.readFile(cachePath)
  } catch (error) {
    // ignore errors and fetch font
  }

  // Get css file from google fonts
  const cssResponse = await fetch(
    `https://fonts.googleapis.com/css2?family=${fontName}:wght@${weight}`,
  )
  const css = await cssResponse.text()

  // Extract .ttf url from css file
  const urlRegex = /url\((https:\/\/fonts.gstatic.com\/s\/.*?.ttf)\)/g
  const match = urlRegex.exec(css)

  if (!match) {
    console.log(
      chalk.yellow(
        `\nWarning: Failed to fetch font ${rawFontName} with weight ${weight}, got ${cssResponse.statusText}`,
      ),
    )
    return
  }

  // fontData is an ArrayBuffer containing the .ttf file data
  const fontResponse = await fetch(match[1])
  const fontData = Buffer.from(await fontResponse.arrayBuffer())
  await fs.mkdir(cacheDir, { recursive: true })
  await fs.writeFile(cachePath, fontData)

  return fontData
}

export type SocialImageOptions = {
  /**
   * What color scheme to use for image generation (uses colors from config theme)
   */
  colorScheme: ThemeKey
  /**
   * Height to generate image with in pixels (should be around 630px)
   */
  height: number
  /**
   * Width to generate image with in pixels (should be around 1200px)
   */
  width: number
  /**
   * Whether to use the auto generated image for the root path ("/", when set to false) or the default og image (when set to true).
   */
  excludeRoot: boolean
  /**
   * JSX to use for generating image. See satori docs for more info (https://github.com/vercel/satori)
   */
  imageStructure: (
    options: ImageOptions & {
      userOpts: UserOpts
      iconBase64?: string
      contentImageBase64?: string
    },
  ) => JSXInternal.Element
}

export type UserOpts = Omit<SocialImageOptions, "imageStructure">

export type ImageOptions = {
  /**
   * what title to use as header in image
   */
  title: string
  /**
   * what description to use as body in image
   */
  description: string
  /**
   * header + body font to be used when generating satori image (as promise to work around sync in component)
   */
  fonts: SatoriOptions["fonts"]
  /**
   * `GlobalConfiguration` of quartz (used for theme/typography)
   */
  cfg: GlobalConfiguration
  /**
   * full file data of current page
   */
  fileData: QuartzPluginData
  /**
   * base64-encoded content image from the note (first embedded image or YouTube thumbnail)
   */
  contentImageBase64?: string
}

const MARKDOWN_IMAGE_REGEX = /!\[[^\]]*\]\(([^)]+\.(?:jpg|jpeg|png|gif|webp))\)/i
const OBSIDIAN_IMAGE_REGEX = /!\[\[([^\]]+\.(?:jpg|jpeg|png|gif|webp))\]\]/i
const YOUTUBE_SHORT_URL_REGEX = /youtu\.be\/([a-zA-Z0-9_-]{11})/
const YOUTUBE_LONG_URL_REGEX = /youtube\.com\/watch\?v=([a-zA-Z0-9_-]{11})/

export function extractFirstLocalImageRef(text: string): string | undefined {
  const mdMatch = MARKDOWN_IMAGE_REGEX.exec(text)
  if (mdMatch) {
    const src = mdMatch[1]
    if (!src.startsWith("http://") && !src.startsWith("https://")) {
      return src
    }
  }
  const obsMatch = OBSIDIAN_IMAGE_REGEX.exec(text)
  if (obsMatch) {
    return obsMatch[1].replace(/^attachments\//, "")
  }
  return undefined
}

export function extractYouTubeVideoId(frontmatter: Record<string, unknown> | undefined, text: string): string | undefined {
  const youtubeUrl = frontmatter?.youtube as string | undefined
  if (youtubeUrl) {
    const shortMatch = YOUTUBE_SHORT_URL_REGEX.exec(youtubeUrl)
    if (shortMatch) return shortMatch[1]
    const longMatch = YOUTUBE_LONG_URL_REGEX.exec(youtubeUrl)
    if (longMatch) return longMatch[1]
  }
  const shortMatch = YOUTUBE_SHORT_URL_REGEX.exec(text)
  if (shortMatch) return shortMatch[1]
  const longMatch = YOUTUBE_LONG_URL_REGEX.exec(text)
  if (longMatch) return longMatch[1]
  return undefined
}

export function resolveImagePath(imageRef: string, markdownFilePath: string, contentDir: string): string {
  const markdownDir = path.dirname(markdownFilePath)
  const resolved = path.resolve(markdownDir, imageRef)
  if (resolved.includes(contentDir)) return resolved
  return path.join(contentDir, imageRef)
}

export async function hashImageFile(imagePath: string): Promise<string | undefined> {
  try {
    const data = await fs.readFile(imagePath)
    return createHash("sha256").update(data).digest("hex").slice(0, 16)
  } catch {
    return undefined
  }
}

const CONTENT_IMAGE_CACHE = new Map<string, string | undefined>()
const CONTENT_IMAGE_TARGET_WIDTH = 480
const CONTENT_IMAGE_TARGET_HEIGHT = 480

export async function loadContentImageBase64(imagePath: string): Promise<string | undefined> {
  const cached = CONTENT_IMAGE_CACHE.get(imagePath)
  if (cached !== undefined) return cached
  if (CONTENT_IMAGE_CACHE.has(imagePath)) return undefined

  try {
    await fs.access(imagePath)
    const resized = await sharp(imagePath)
      .resize(CONTENT_IMAGE_TARGET_WIDTH, CONTENT_IMAGE_TARGET_HEIGHT, { fit: "cover" })
      .jpeg({ quality: 80 })
      .toBuffer()
    const base64 = `data:image/jpeg;base64,${resized.toString("base64")}`
    CONTENT_IMAGE_CACHE.set(imagePath, base64)
    return base64
  } catch {
    CONTENT_IMAGE_CACHE.set(imagePath, undefined)
    return undefined
  }
}

const YOUTUBE_THUMBNAIL_CACHE_DIR = path.join(QUARTZ, ".quartz-cache", "yt-thumbnails")

export async function fetchYouTubeThumbnailBase64(videoId: string): Promise<string | undefined> {
  const cacheDir = YOUTUBE_THUMBNAIL_CACHE_DIR
  const cachePath = path.join(cacheDir, `${videoId}.jpg`)

  try {
    await fs.access(cachePath)
    const data = await fs.readFile(cachePath)
    const resized = await sharp(data)
      .resize(CONTENT_IMAGE_TARGET_WIDTH, CONTENT_IMAGE_TARGET_HEIGHT, { fit: "cover" })
      .jpeg({ quality: 80 })
      .toBuffer()
    return `data:image/jpeg;base64,${resized.toString("base64")}`
  } catch {
    // Cache miss - fetch from YouTube
  }

  const urls = [
    `https://img.youtube.com/vi/${videoId}/maxresdefault.jpg`,
    `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
  ]

  for (const url of urls) {
    try {
      const response = await fetch(url)
      if (!response.ok) continue
      const buffer = Buffer.from(await response.arrayBuffer())
      const metadata = await sharp(buffer).metadata()
      if (!metadata.width || metadata.width < 200) continue

      await fs.mkdir(cacheDir, { recursive: true })
      await fs.writeFile(cachePath, buffer)

      const resized = await sharp(buffer)
        .resize(CONTENT_IMAGE_TARGET_WIDTH, CONTENT_IMAGE_TARGET_HEIGHT, { fit: "cover" })
        .jpeg({ quality: 80 })
        .toBuffer()
      return `data:image/jpeg;base64,${resized.toString("base64")}`
    } catch {
      continue
    }
  }
  return undefined
}

// This is the default template for generated social image.
export const defaultImage: SocialImageOptions["imageStructure"] = ({
  cfg,
  userOpts,
  title,
  description,
  fileData,
  iconBase64,
  contentImageBase64,
}) => {
  const { colorScheme } = userOpts
  const hasContentImage = !!contentImageBase64
  const fontBreakPoint = hasContentImage ? 24 : 32
  const useSmallerFont = title.length > fontBreakPoint

  // Format date if available
  const rawDate = getDate(cfg, fileData)
  const date = rawDate ? formatDate(rawDate, cfg.locale) : null

  // Calculate reading time
  const { minutes } = readingTime(fileData.text ?? "")
  const readingTimeText = i18n(cfg.locale).components.contentMeta.readingTime({
    minutes: Math.ceil(minutes),
  })

  // Get tags if available
  const tags = fileData.frontmatter?.tags ?? []
  const bodyFont = getFontSpecificationName(cfg.theme.typography.body)
  const headerFont = getFontSpecificationName(cfg.theme.typography.header)

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100%",
        width: "100%",
        backgroundColor: cfg.theme.colors[colorScheme].light,
        padding: "2.5rem",
        fontFamily: bodyFont,
      }}
    >
      {/* Header Section */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "1rem",
          marginBottom: "0.5rem",
        }}
      >
        {iconBase64 && (
          <img
            src={iconBase64}
            width={56}
            height={56}
            style={{
              borderRadius: "50%",
            }}
          />
        )}
        <div
          style={{
            display: "flex",
            fontSize: 32,
            color: cfg.theme.colors[colorScheme].gray,
            fontFamily: bodyFont,
          }}
        >
          {cfg.baseUrl}
        </div>

        {/* Date and Reading Time */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "2rem",
            color: cfg.theme.colors[colorScheme].gray,
            fontSize: 28,
          }}
        >
          {date && (
            <div style={{ display: "flex", alignItems: "center" }}>
              <svg
                style={{ marginRight: "0.5rem" }}
                width="28"
                height="28"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
              >
                <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
                <line x1="16" y1="2" x2="16" y2="6"></line>
                <line x1="8" y1="2" x2="8" y2="6"></line>
                <line x1="3" y1="10" x2="21" y2="10"></line>
              </svg>
              {date}
            </div>
          )}
          <div style={{ display: "flex", alignItems: "center" }}>
            <svg
              style={{ marginRight: "0.5rem" }}
              width="28"
              height="28"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
            >
              <circle cx="12" cy="12" r="10"></circle>
              <polyline points="12 6 12 12 16 14"></polyline>
            </svg>
            {readingTimeText}
          </div>
        </div>

        {/* Tags */}
        {!hasContentImage && (
          <div
            style={{
              display: "flex",
              gap: "0.5rem",
              flexWrap: "wrap",
              justifyContent: "flex-end",
              maxWidth: "60%",
            }}
          >
            {tags.slice(0, 3).map((tag: string) => (
              <div
                style={{
                  display: "flex",
                  padding: "0.5rem 1rem",
                  backgroundColor: cfg.theme.colors[colorScheme].highlight,
                  color: cfg.theme.colors[colorScheme].secondary,
                  borderRadius: "10px",
                  fontSize: 24,
                }}
              >
                #{tag}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Main Content: side-by-side when content image present */}
      <div
        style={{
          display: "flex",
          flex: 1,
          gap: hasContentImage ? "2rem" : "0",
          marginTop: "1rem",
        }}
      >
        {/* Text Column */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            flex: hasContentImage ? "1" : "1",
            minWidth: 0,
          }}
        >
          {/* Title */}
          <div style={{ display: "flex", marginBottom: "1rem" }}>
            <h1
              style={{
                margin: 0,
                fontSize: hasContentImage ? (useSmallerFont ? 48 : 56) : (useSmallerFont ? 64 : 72),
                fontFamily: headerFont,
                fontWeight: 700,
                color: cfg.theme.colors[colorScheme].dark,
                lineHeight: 1.2,
                display: "-webkit-box",
                WebkitBoxOrient: "vertical",
                WebkitLineClamp: hasContentImage ? 3 : 2,
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {title}
            </h1>
          </div>

          {/* Description */}
          <div
            style={{
              display: "flex",
              flex: 1,
              fontSize: hasContentImage ? 28 : 36,
              color: cfg.theme.colors[colorScheme].darkgray,
              lineHeight: 1.4,
            }}
          >
            <p
              style={{
                margin: 0,
                display: "-webkit-box",
                WebkitBoxOrient: "vertical",
                WebkitLineClamp: hasContentImage ? 5 : 8,
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {description}
            </p>
          </div>

          {/* Tags row (below text when content image present) */}
          {hasContentImage && tags.length > 0 && (
            <div
              style={{
                display: "flex",
                gap: "0.5rem",
                flexWrap: "wrap",
                marginTop: "0.5rem",
              }}
            >
              {tags.slice(0, 3).map((tag: string) => (
                <div
                  style={{
                    display: "flex",
                    padding: "0.25rem 0.75rem",
                    backgroundColor: cfg.theme.colors[colorScheme].highlight,
                    color: cfg.theme.colors[colorScheme].secondary,
                    borderRadius: "8px",
                    fontSize: 20,
                  }}
                >
                  #{tag}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Content Image Column */}
        {hasContentImage && contentImageBase64 && (
          <div
            style={{
              display: "flex",
              width: "420px",
              minWidth: "420px",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <img
              src={contentImageBase64}
              width={400}
              height={400}
              style={{
                borderRadius: "16px",
                objectFit: "cover",
                border: `3px solid ${cfg.theme.colors[colorScheme].lightgray}`,
              }}
            />
          </div>
        )}
      </div>
    </div>
  )
}
