import { QuartzEmitterPlugin } from "../types"
import { i18n } from "../../i18n"
import { unescapeHTML } from "../../util/escape"
import { FilePath, FullSlug, getFileExtension, isAbsoluteURL, joinSegments, QUARTZ } from "../../util/path"
import { ImageOptions, SocialImageOptions, defaultImage, getSatoriFonts } from "../../util/og"
import sharp from "sharp"
import satori, { SatoriOptions } from "satori"
import { loadEmoji, getIconCode } from "../../util/emoji"
import { Readable } from "stream"
import { write } from "./helpers"
import { BuildCtx } from "../../util/ctx"
import { QuartzPluginData } from "../vfile"
import fs from "node:fs/promises"
import path from "path"
import { createHash } from "crypto"
import chalk from "chalk"

const defaultOptions: SocialImageOptions = {
  colorScheme: "lightMode",
  width: 1200,
  height: 630,
  imageStructure: defaultImage,
  excludeRoot: false,
}

const OG_CACHE_DIR = path.join(QUARTZ, ".quartz-cache", "og-images")
const OG_CONCURRENCY = 20

/**
 * Compute a content hash for cache keying of OG images.
 * Captures all inputs that affect the generated image.
 */
function computeOgHash(
  title: string,
  description: string,
  tags: string[],
  date: string | undefined,
  colorScheme: string,
  width: number,
  height: number,
): string {
  const hash = createHash("sha256")
  hash.update(
    JSON.stringify({ title, description, tags, date, colorScheme, width, height, version: 1 }),
  )
  return hash.digest("hex").slice(0, 16)
}

/**
 * Load the icon file once and cache it in memory
 */
let cachedIconBase64: string | undefined | null = null
async function getIconBase64(): Promise<string | undefined> {
  if (cachedIconBase64 !== null) return cachedIconBase64
  const iconPath = joinSegments(QUARTZ, "static", "icon.png")
  try {
    const iconData = await fs.readFile(iconPath)
    cachedIconBase64 = `data:image/png;base64,${iconData.toString("base64")}`
  } catch (err) {
    console.warn(chalk.yellow(`Warning: Could not find icon at ${iconPath}`))
    cachedIconBase64 = undefined
  }
  return cachedIconBase64
}

/**
 * Generates social image (OG/twitter standard) and saves it as `.webp` inside the public folder
 * @param opts options for generating image
 */
async function generateSocialImage(
  { cfg, description, fonts, title, fileData }: ImageOptions,
  userOpts: SocialImageOptions,
): Promise<Buffer> {
  const { width, height } = userOpts
  const iconBase64 = await getIconBase64()

  const imageComponent = userOpts.imageStructure({
    cfg,
    userOpts,
    title,
    description,
    fonts,
    fileData,
    iconBase64,
  })

  const svg = await satori(imageComponent, {
    width,
    height,
    fonts,
    loadAdditionalAsset: async (languageCode: string, segment: string) => {
      if (languageCode === "emoji") {
        return await loadEmoji(getIconCode(segment))
      }

      return languageCode
    },
  })

  return sharp(Buffer.from(svg)).webp({ quality: 40 }).toBuffer()
}

async function processOgImage(
  ctx: BuildCtx,
  fileData: QuartzPluginData,
  fonts: SatoriOptions["fonts"],
  fullOptions: SocialImageOptions,
): Promise<FilePath> {
  const cfg = ctx.cfg.configuration
  const slug = fileData.slug!
  const titleSuffix = cfg.pageTitleSuffix ?? ""
  const title =
    (fileData.frontmatter?.title ?? i18n(cfg.locale).propertyDefaults.title) + titleSuffix
  const description =
    fileData.frontmatter?.socialDescription ??
    fileData.frontmatter?.description ??
    unescapeHTML(fileData.description?.trim() ?? i18n(cfg.locale).propertyDefaults.description)
  const tags = fileData.frontmatter?.tags ?? []
  const date = fileData.frontmatter?.date?.toString()

  const cacheKey = computeOgHash(
    title,
    description,
    tags,
    date,
    fullOptions.colorScheme,
    fullOptions.width,
    fullOptions.height,
  )
  const cachePath = path.join(OG_CACHE_DIR, `${cacheKey}.webp`)
  const outputSlug = `${slug}-og-image` as FullSlug

  // Check cache
  try {
    await fs.access(cachePath)
    // Cache hit — copy to output
    const cached = await fs.readFile(cachePath)
    return write({
      ctx,
      content: cached,
      slug: outputSlug,
      ext: ".webp",
    })
  } catch {
    // Cache miss — generate
  }

  const imageBuffer = await generateSocialImage(
    {
      title,
      description,
      fonts,
      cfg,
      fileData,
    },
    fullOptions,
  )

  // Write to cache
  await fs.mkdir(OG_CACHE_DIR, { recursive: true })
  await fs.writeFile(cachePath, imageBuffer)

  return write({
    ctx,
    content: imageBuffer,
    slug: outputSlug,
    ext: ".webp",
  })
}

export const CustomOgImagesEmitterName = "CustomOgImages"
export const CustomOgImages: QuartzEmitterPlugin<Partial<SocialImageOptions>> = (userOpts) => {
  const fullOptions = { ...defaultOptions, ...userOpts }

  return {
    name: CustomOgImagesEmitterName,
    getQuartzComponents() {
      return []
    },
    async *emit(ctx, content, _resources) {
      const cfg = ctx.cfg.configuration
      const headerFont = cfg.theme.typography.header
      const bodyFont = cfg.theme.typography.body
      const fonts = await getSatoriFonts(headerFont, bodyFont)

      // Process OG images in parallel batches for better throughput
      const items = content.filter(
        ([_tree, vfile]) => vfile.data.frontmatter?.socialImage === undefined,
      )

      for (let i = 0; i < items.length; i += OG_CONCURRENCY) {
        const batch = items.slice(i, i + OG_CONCURRENCY)
        const results = await Promise.all(
          batch.map(([_tree, vfile]) => processOgImage(ctx, vfile.data, fonts, fullOptions)),
        )
        for (const result of results) {
          yield result
        }
      }
    },
    async *partialEmit(ctx, _content, _resources, changeEvents) {
      const cfg = ctx.cfg.configuration
      const headerFont = cfg.theme.typography.header
      const bodyFont = cfg.theme.typography.body
      const fonts = await getSatoriFonts(headerFont, bodyFont)

      // find all slugs that changed or were added
      const items = changeEvents.filter(
        (e) =>
          e.file &&
          e.file.data.frontmatter?.socialImage === undefined &&
          (e.type === "add" || e.type === "change"),
      )

      for (let i = 0; i < items.length; i += OG_CONCURRENCY) {
        const batch = items.slice(i, i + OG_CONCURRENCY)
        const results = await Promise.all(
          batch.map((changeEvent) =>
            processOgImage(ctx, changeEvent.file!.data, fonts, fullOptions),
          ),
        )
        for (const result of results) {
          yield result
        }
      }
    },
    externalResources: (ctx) => {
      if (!ctx.cfg.configuration.baseUrl) {
        return {}
      }

      const baseUrl = ctx.cfg.configuration.baseUrl
      return {
        additionalHead: [
          (pageData) => {
            const isRealFile = pageData.filePath !== undefined
            let userDefinedOgImagePath = pageData.frontmatter?.socialImage

            if (userDefinedOgImagePath) {
              userDefinedOgImagePath = isAbsoluteURL(userDefinedOgImagePath)
                ? userDefinedOgImagePath
                : `https://${baseUrl}/static/${userDefinedOgImagePath}`
            }

            const generatedOgImagePath = isRealFile
              ? `https://${baseUrl}/${pageData.slug!}-og-image.webp`
              : undefined
            const defaultOgImagePath = `https://${baseUrl}/static/og-image.png`
            const ogImagePath = userDefinedOgImagePath ?? generatedOgImagePath ?? defaultOgImagePath
            const ogImageMimeType = `image/${getFileExtension(ogImagePath) ?? "png"}`
            return (
              <>
                {!userDefinedOgImagePath && (
                  <>
                    <meta property="og:image:width" content={fullOptions.width.toString()} />
                    <meta property="og:image:height" content={fullOptions.height.toString()} />
                  </>
                )}

                <meta property="og:image" content={ogImagePath} />
                <meta property="og:image:url" content={ogImagePath} />
                <meta name="twitter:image" content={ogImagePath} />
                <meta property="og:image:type" content={ogImageMimeType} />
              </>
            )
          },
        ],
      }
    },
  }
}
