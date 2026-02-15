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
import path from "node:path"
import chalk from "chalk"

const SKIP_EXISTING = process.env.SKIP_EXISTING_OG_IMAGES === "true"

// Cache manifest to track generated OG images and their source modification times
// Saved outside public/ directory to survive the clean step at build start
interface OGCacheManifest {
  [slug: string]: string // slug -> source modification date ISO string
}

let cacheManifest: OGCacheManifest | null = null

// Get manifest path in .quartz-cache directory (survives public/ clean)
function getManifestPath(): string {
  return path.join(process.cwd(), '.quartz-cache', 'og-cache-manifest.json')
}

async function loadCacheManifest(): Promise<OGCacheManifest> {
  if (cacheManifest !== null) return cacheManifest
  
  const manifestPath = getManifestPath()
  try {
    const content = await fs.readFile(manifestPath, 'utf-8')
    cacheManifest = JSON.parse(content)
    console.log(`[OG Cache] Loaded manifest with ${Object.keys(cacheManifest).length} entries`)
    return cacheManifest
  } catch {
    cacheManifest = {}
    console.log(`[OG Cache] No existing manifest found, starting fresh`)
    return cacheManifest
  }
}

async function saveCacheManifest(manifest: OGCacheManifest): Promise<void> {
  const manifestPath = getManifestPath()
  // Ensure .quartz-cache directory exists
  await fs.mkdir(path.dirname(manifestPath), { recursive: true })
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2), 'utf-8')
  console.log(`[OG Cache] Saved manifest with ${Object.keys(manifest).length} entries`)
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
) {
  const cfg = ctx.cfg.configuration
  const slug = fileData.slug!
  const outputPath = path.join(ctx.argv.output, `${slug}-og-image.webp`)
  
  // Hybrid caching strategy: GitHub Actions caches .quartz-cache directory
  // (see .github/workflows/deploy.yml), and this code performs per-file checking
  // at build time using a manifest file (.quartz-cache/og-cache-manifest.json) to track
  // which files have been processed and their source modification dates. This is more
  // reliable than filesystem mtimes which don't survive cache restoration.
  if (SKIP_EXISTING) {
    const manifest = await loadCacheManifest()
    const sourceModified = fileData.dates?.modified
    
    if (sourceModified) {
      const sourceModifiedISO = sourceModified.toISOString()
      const cachedModified = manifest[slug]
      
      // Check if OG image exists and source hasn't changed since it was generated
      try {
        await fs.stat(outputPath)
        if (cachedModified === sourceModifiedISO) {
          console.log(`[OG Cache] Skipping ${slug} - cached image is current`)
          return outputPath as FilePath
        }
        console.log(`[OG Cache] Regenerating ${slug} - source modified: ${sourceModifiedISO}, cached: ${cachedModified || 'not in manifest'}`)
      } catch {
        console.log(`[OG Cache] Generating ${slug} - no cached image found`)
      }
      
      // Update manifest with current source modification time
      manifest[slug] = sourceModifiedISO
    }
  }
  
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

  return write({
    ctx,
    content: stream,
    slug: `${slug}-og-image` as FullSlug,
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

      for (const [_tree, vfile] of content) {
        if (vfile.data.frontmatter?.socialImage !== undefined) continue
        yield processOgImage(ctx, vfile.data, fonts, fullOptions)
      }
      
      // Save the manifest after processing all files
      if (SKIP_EXISTING && cacheManifest) {
        await saveCacheManifest(cacheManifest)
      }
    },
    async *partialEmit(ctx, _content, _resources, changeEvents) {
      const cfg = ctx.cfg.configuration
      const headerFont = cfg.theme.typography.header
      const bodyFont = cfg.theme.typography.body
      const fonts = await getSatoriFonts(headerFont, bodyFont)

      // find all slugs that changed or were added
      for (const changeEvent of changeEvents) {
        if (!changeEvent.file) continue
        if (changeEvent.file.data.frontmatter?.socialImage !== undefined) continue
        if (changeEvent.type === "add" || changeEvent.type === "change") {
          yield processOgImage(ctx, changeEvent.file.data, fonts, fullOptions)
        }
      }
      
      // Save the manifest after processing changed files
      if (SKIP_EXISTING && cacheManifest) {
        await saveCacheManifest(cacheManifest)
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
