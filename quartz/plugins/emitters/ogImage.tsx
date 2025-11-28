import { QuartzEmitterPlugin } from "../types"
import { i18n } from "../../i18n"
import { unescapeHTML } from "../../util/escape"
import { FullSlug, getFileExtension, isAbsoluteURL, joinSegments, QUARTZ } from "../../util/path"
import { ImageOptions, SocialImageOptions, defaultImage, getSatoriFonts } from "../../util/og"
import sharp from "sharp"
import satori, { SatoriOptions } from "satori"
import { loadEmoji, getIconCode } from "../../util/emoji"
import { write } from "./helpers"
import { BuildCtx } from "../../util/ctx"
import { QuartzPluginData } from "../vfile"
import fs from "node:fs/promises"
import path from "path"
import chalk from "chalk"
import { createHash } from "crypto"
import { GlobalConfiguration } from "../../cfg"

// OG image cache directory
const OG_CACHE_DIR = path.join(QUARTZ, ".quartz-cache", "og-images")

/**
 * Compute a hash of the configuration that affects OG image generation
 */
function computeConfigHash(cfg: GlobalConfiguration): string {
  return createHash("sha256")
    .update(
      JSON.stringify({
        colors: cfg.theme.colors,
        typography: cfg.theme.typography,
        baseUrl: cfg.baseUrl,
      }),
    )
    .digest("hex")
    .slice(0, 8)
}

/**
 * Compute a cache key based on content that affects the OG image
 */
function computeCacheKey(
  fileData: QuartzPluginData,
  cfg: GlobalConfiguration,
  configHash: string,
): string {
  const data = {
    title: fileData.frontmatter?.title ?? "",
    description: fileData.frontmatter?.description ?? fileData.description ?? "",
    date:
      fileData.dates?.modified?.toISOString() ?? fileData.dates?.created?.toISOString() ?? null,
    tags: (fileData.frontmatter?.tags ?? []).slice(0, 3),
    textLength: (fileData.text ?? "").length,
    configVersion: configHash,
  }

  return createHash("sha256").update(JSON.stringify(data)).digest("hex").slice(0, 16)
}

/**
 * Create a short hash of the slug for cache filename
 */
function hashSlug(slug: string): string {
  return createHash("sha256").update(slug).digest("hex").slice(0, 16)
}

const defaultOptions: SocialImageOptions = {
  colorScheme: "lightMode",
  width: 1200,
  height: 630,
  imageStructure: defaultImage,
  excludeRoot: false,
}

/**
 * Generates social image (OG/twitter standard) and saves it as `.webp` inside the public folder
 * @param opts options for generating image
 */
async function generateSocialImage(
  { cfg, description, fonts, title, fileData }: ImageOptions,
  userOpts: SocialImageOptions,
): Promise<sharp.Sharp> {
  const { width, height } = userOpts
  const iconPath = joinSegments(QUARTZ, "static", "icon.png")
  let iconBase64: string | undefined = undefined
  try {
    const iconData = await fs.readFile(iconPath)
    iconBase64 = `data:image/png;base64,${iconData.toString("base64")}`
  } catch (err) {
    console.warn(chalk.yellow(`Warning: Could not find icon at ${iconPath}`))
  }

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

  return sharp(Buffer.from(svg)).webp({ quality: 40 })
}

async function processOgImage(
  ctx: BuildCtx,
  fileData: QuartzPluginData,
  fonts: SatoriOptions["fonts"],
  fullOptions: SocialImageOptions,
  configHash: string,
) {
  const cfg = ctx.cfg.configuration
  const slug = fileData.slug!
  const outputSlug = `${slug}-og-image` as FullSlug

  // Compute cache key and cache path
  const cacheKey = computeCacheKey(fileData, cfg, configHash)
  const cacheFileName = `${hashSlug(slug)}_${cacheKey}.webp`
  const cachePath = path.join(OG_CACHE_DIR, cacheFileName)

  // Check if cached version exists
  try {
    await fs.access(cachePath)
    // Cache hit: copy to output using fs.copyFile
    const outputPath = path.join(ctx.argv.output, outputSlug + ".webp")
    await fs.mkdir(path.dirname(outputPath), { recursive: true })
    await fs.copyFile(cachePath, outputPath)
    return outputPath
  } catch {
    // Cache miss: generate new image
    console.log(chalk.yellow(`[OG cache miss] ${slug}`))
  }

  // Generate image
  const titleSuffix = cfg.pageTitleSuffix ?? ""
  const title =
    (fileData.frontmatter?.title ?? i18n(cfg.locale).propertyDefaults.title) + titleSuffix
  const description =
    fileData.frontmatter?.socialDescription ??
    fileData.frontmatter?.description ??
    unescapeHTML(fileData.description?.trim() ?? i18n(cfg.locale).propertyDefaults.description)

  const stream = await generateSocialImage(
    {
      title,
      description,
      fonts,
      cfg,
      fileData,
    },
    fullOptions,
  )

  // Ensure cache directory exists
  await fs.mkdir(OG_CACHE_DIR, { recursive: true })

  // Write to cache first
  const buffer = await stream.toBuffer()
  await fs.writeFile(cachePath, buffer)

  // Write to output
  return write({
    ctx,
    content: buffer,
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

      // Compute config hash once for all images
      const configHash = computeConfigHash(cfg)

      for (const [_tree, vfile] of content) {
        if (vfile.data.frontmatter?.socialImage !== undefined) continue
        yield processOgImage(ctx, vfile.data, fonts, fullOptions, configHash)
      }
    },
    async *partialEmit(ctx, _content, _resources, changeEvents) {
      const cfg = ctx.cfg.configuration
      const headerFont = cfg.theme.typography.header
      const bodyFont = cfg.theme.typography.body
      const fonts = await getSatoriFonts(headerFont, bodyFont)

      // Compute config hash once for all images
      const configHash = computeConfigHash(cfg)

      // find all slugs that changed or were added
      for (const changeEvent of changeEvents) {
        if (!changeEvent.file) continue
        if (changeEvent.file.data.frontmatter?.socialImage !== undefined) continue
        if (changeEvent.type === "add" || changeEvent.type === "change") {
          yield processOgImage(ctx, changeEvent.file.data, fonts, fullOptions, configHash)
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
