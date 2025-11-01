import { QuartzEmitterPlugin } from "../types"
import { i18n } from "../../i18n"
import { unescapeHTML } from "../../util/escape"
import { FullSlug, getFileExtension, isAbsoluteURL, joinSegments, QUARTZ } from "../../util/path"
import { ImageOptions, SocialImageOptions, defaultImage, getSatoriFonts } from "../../util/og"
import sharp from "sharp"
import satori, { SatoriOptions } from "satori"
import { loadEmoji, getIconCode } from "../../util/emoji"
import { Readable } from "stream"
import { write } from "./helpers"
import { BuildCtx } from "../../util/ctx"
import { QuartzPluginData } from "../vfile"
import fs from "node:fs/promises"
import chalk from "chalk"
import path from "path"

const defaultOptions: SocialImageOptions = {
  colorScheme: "lightMode",
  width: 1200,
  height: 630,
  imageStructure: defaultImage,
  excludeRoot: false,
}

type OgCacheManifest = {
  [slug: string]: {
    cacheKey: string
    mtime: number
  }
}

const CACHE_DIR = ".quartz-cache"
const OG_CACHE_DIR = path.join(CACHE_DIR, "og-images")
const MANIFEST_FILE = path.join(CACHE_DIR, "og-cache-manifest.json")
const SKIP_EXISTING = process.env.SKIP_EXISTING_OG_IMAGES === "true"

async function loadManifest(): Promise<OgCacheManifest> {
  try {
    const data = await fs.readFile(MANIFEST_FILE, "utf-8")
    const manifest = JSON.parse(data)
    console.log(chalk.cyan(`[OG Cache] Loaded manifest with ${Object.keys(manifest).length} entries`))
    return manifest
  } catch (err) {
    console.log(chalk.yellow("[OG Cache] No existing manifest found, creating new one"))
    return {}
  }
}

async function saveManifest(manifest: OgCacheManifest): Promise<void> {
  try {
    await fs.mkdir(CACHE_DIR, { recursive: true })
    await fs.writeFile(MANIFEST_FILE, JSON.stringify(manifest, null, 2), "utf-8")
    console.log(chalk.green(`[OG Cache] Saved manifest with ${Object.keys(manifest).length} entries`))
  } catch (err) {
    console.warn(chalk.yellow(`[OG Cache] Failed to save manifest: ${err}`))
  }
}

function computeCacheKey(
  fileData: QuartzPluginData,
  cfg: BuildCtx["cfg"]["configuration"],
  userOpts: SocialImageOptions,
): string {
  const titleSuffix = cfg.pageTitleSuffix ?? ""
  const title = (fileData.frontmatter?.title ?? "") + titleSuffix
  const description = fileData.frontmatter?.socialDescription ??
    fileData.frontmatter?.description ??
    (fileData.description?.trim() ?? "")
  
  return `${title}|${description}|${userOpts.width}|${userOpts.height}|${userOpts.colorScheme}`
}

async function copyCachedImage(ctx: BuildCtx, slug: string): Promise<boolean> {
  const cachedImagePath = path.join(OG_CACHE_DIR, `${slug}-og-image.webp`)
  const publicImagePath = path.join(ctx.argv.output, `${slug}-og-image.webp`)
  
  try {
    await fs.copyFile(cachedImagePath, publicImagePath)
    return true
  } catch {
    return false
  }
}

async function shouldSkipGeneration(
  ctx: BuildCtx,
  slug: string,
  fileData: QuartzPluginData,
  manifest: OgCacheManifest,
  userOpts: SocialImageOptions,
): Promise<boolean> {
  if (!SKIP_EXISTING) {
    return false
  }

  const cfg = ctx.cfg.configuration
  const currentCacheKey = computeCacheKey(fileData, cfg, userOpts)
  const cachedEntry = manifest[slug]
  
  if (!cachedEntry || cachedEntry.cacheKey !== currentCacheKey) {
    return false
  }

  const copied = await copyCachedImage(ctx, slug)
  if (copied) {
    console.log(chalk.green(`[OG Cache] ✓ Cache hit for ${slug}`))
    return true
  } else {
    console.log(chalk.yellow(`[OG Cache] Cache miss (file not found) for ${slug}`))
    return false
  }
}

/**
 * Generates social image (OG/twitter standard) and saves it as `.webp` inside the public folder
 * @param opts options for generating image
 */
async function generateSocialImage(
  { cfg, description, fonts, title, fileData }: ImageOptions,
  userOpts: SocialImageOptions,
): Promise<Readable> {
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
  manifest: OgCacheManifest,
) {
  const cfg = ctx.cfg.configuration
  const slug = fileData.slug!
  
  if (await shouldSkipGeneration(ctx, slug, fileData, manifest, fullOptions)) {
    return `${slug}-og-image.webp`
  }

  const titleSuffix = cfg.pageTitleSuffix ?? ""
  const title =
    (fileData.frontmatter?.title ?? i18n(cfg.locale).propertyDefaults.title) + titleSuffix
  const description =
    fileData.frontmatter?.socialDescription ??
    fileData.frontmatter?.description ??
    unescapeHTML(fileData.description?.trim() ?? i18n(cfg.locale).propertyDefaults.description)

  console.log(chalk.blue(`[OG Cache] Generating OG image for ${slug}`))

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

  const result = await write({
    ctx,
    content: stream,
    slug: `${slug}-og-image` as FullSlug,
    ext: ".webp",
  })

  try {
    const publicImagePath = path.join(ctx.argv.output, `${slug}-og-image.webp`)
    const cachedImagePath = path.join(OG_CACHE_DIR, `${slug}-og-image.webp`)
    await fs.mkdir(path.dirname(cachedImagePath), { recursive: true })
    await fs.copyFile(publicImagePath, cachedImagePath)
  } catch (err) {
    console.warn(chalk.yellow(`[OG Cache] Failed to cache image for ${slug}: ${err}`))
  }

  const currentCacheKey = computeCacheKey(fileData, cfg, fullOptions)
  manifest[slug] = {
    cacheKey: currentCacheKey,
    mtime: Date.now(),
  }

  return result
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

      const manifest = await loadManifest()

      for (const [_tree, vfile] of content) {
        if (vfile.data.frontmatter?.socialImage !== undefined) continue
        yield processOgImage(ctx, vfile.data, fonts, fullOptions, manifest)
      }

      await saveManifest(manifest)
    },
    async *partialEmit(ctx, _content, _resources, changeEvents) {
      const cfg = ctx.cfg.configuration
      const headerFont = cfg.theme.typography.header
      const bodyFont = cfg.theme.typography.body
      const fonts = await getSatoriFonts(headerFont, bodyFont)

      const manifest = await loadManifest()

      // find all slugs that changed or were added
      for (const changeEvent of changeEvents) {
        if (!changeEvent.file) continue
        if (changeEvent.file.data.frontmatter?.socialImage !== undefined) continue
        if (changeEvent.type === "add" || changeEvent.type === "change") {
          yield processOgImage(ctx, changeEvent.file.data, fonts, fullOptions, manifest)
        }
      }

      await saveManifest(manifest)
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
