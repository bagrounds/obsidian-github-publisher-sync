import esbuild from "esbuild"
import remarkParse from "remark-parse"
import remarkRehype from "remark-rehype"
import { Processor, unified } from "unified"
import { Root as MDRoot } from "remark-parse/lib"
import { Root as HTMLRoot } from "hast"
import { MarkdownContent, ProcessedContent } from "../plugins/vfile"
import { PerfTimer } from "../util/perf"
import { read } from "to-vfile"
import { FilePath, QUARTZ, slugifyFilePath } from "../util/path"
import path from "path"
import workerpool, { Promise as WorkerPromise } from "workerpool"
import { QuartzLogger } from "../util/log"
import { trace } from "../util/trace"
import { BuildCtx, WorkerSerializableBuildCtx } from "../util/ctx"
import chalk from "chalk"
import os from "os"
import fs from "fs"
import { createHash } from "crypto"
import v8 from "v8"

export type QuartzMdProcessor = Processor<MDRoot, MDRoot, MDRoot>
export type QuartzHtmlProcessor = Processor<undefined, MDRoot, HTMLRoot>

export function createMdProcessor(ctx: BuildCtx): QuartzMdProcessor {
  const transformers = ctx.cfg.plugins.transformers

  return (
    unified()
      // base Markdown -> MD AST
      .use(remarkParse)
      // MD AST -> MD AST transforms
      .use(
        transformers.flatMap((plugin) => plugin.markdownPlugins?.(ctx) ?? []),
      ) as unknown as QuartzMdProcessor
    //  ^ sadly the typing of `use` is not smart enough to infer the correct type from our plugin list
  )
}

export function createHtmlProcessor(ctx: BuildCtx): QuartzHtmlProcessor {
  const transformers = ctx.cfg.plugins.transformers
  return (
    unified()
      // MD AST -> HTML AST
      .use(remarkRehype, { allowDangerousHtml: true })
      // HTML AST -> HTML AST transforms
      .use(transformers.flatMap((plugin) => plugin.htmlPlugins?.(ctx) ?? []))
  )
}

function* chunks<T>(arr: T[], n: number) {
  for (let i = 0; i < arr.length; i += n) {
    yield arr.slice(i, i + n)
  }
}

async function transpileWorkerScript() {
  // transpile worker script (skip if already pre-transpiled by handleBuild)
  const cacheFile = "./.quartz-cache/transpiled-worker.mjs"
  const outfile = path.join(QUARTZ, cacheFile)
  try {
    await import("fs").then((fs) => fs.promises.access(outfile))
    return // already transpiled
  } catch {
    // file doesn't exist, transpile it
  }
  const fp = "./quartz/worker.ts"
  return esbuild.build({
    entryPoints: [fp],
    outfile,
    bundle: true,
    keepNames: true,
    platform: "node",
    format: "esm",
    packages: "external",
    sourcemap: true,
    sourcesContent: false,
    plugins: [
      {
        name: "css-and-scripts-as-text",
        setup(build) {
          build.onLoad({ filter: /\.scss$/ }, (_) => ({
            contents: "",
            loader: "text",
          }))
          build.onLoad({ filter: /\.inline\.(ts|js)$/ }, (_) => ({
            contents: "",
            loader: "text",
          }))
        },
      },
    ],
  })
}

export function createFileParser(ctx: BuildCtx, fps: FilePath[]) {
  const { argv, cfg } = ctx
  return async (processor: QuartzMdProcessor) => {
    const res: MarkdownContent[] = []
    for (const fp of fps) {
      try {
        const perf = new PerfTimer()
        const file = await read(fp)

        // strip leading and trailing whitespace
        file.value = file.value.toString().trim()

        // Text -> Text transforms
        for (const plugin of cfg.plugins.transformers.filter((p) => p.textTransform)) {
          file.value = plugin.textTransform!(ctx, file.value.toString())
        }

        // base data properties that plugins may use
        file.data.filePath = file.path as FilePath
        file.data.relativePath = path.posix.relative(argv.directory, file.path) as FilePath
        file.data.slug = slugifyFilePath(file.data.relativePath)

        const ast = processor.parse(file)
        const newAst = await processor.run(ast, file)
        res.push([newAst, file])

        if (argv.verbose) {
          console.log(`[markdown] ${fp} -> ${file.data.slug} (${perf.timeSince()})`)
        }
      } catch (err) {
        trace(`\nFailed to process markdown \`${fp}\``, err as Error)
      }
    }

    return res
  }
}

export function createMarkdownParser(ctx: BuildCtx, mdContent: MarkdownContent[]) {
  return async (processor: QuartzHtmlProcessor) => {
    const res: ProcessedContent[] = []
    for (const [ast, file] of mdContent) {
      try {
        const perf = new PerfTimer()

        const newAst = await processor.run(ast as MDRoot, file)
        res.push([newAst, file])

        if (ctx.argv.verbose) {
          console.log(`[html] ${file.data.slug} (${perf.timeSince()})`)
        }
      } catch (err) {
        trace(`\nFailed to process html \`${file.data.filePath}\``, err as Error)
      }
    }

    return res
  }
}

const clamp = (num: number, min: number, max: number) =>
  Math.min(Math.max(Math.round(num), min), max)

// Content-hash parse cache: caches ProcessedContent per file to skip re-parsing unchanged files
const PARSE_CACHE_VERSION = 1
const PARSE_CACHE_DIR = path.join(QUARTZ, ".quartz-cache", "content-cache")

function getCacheKey(fileContent: string, gitDate: number | undefined): string {
  const input = `v${PARSE_CACHE_VERSION}:${fileContent}:${gitDate ?? ""}`
  return createHash("sha256").update(input).digest("hex").slice(0, 16)
}

async function loadCachedResult(cacheKey: string): Promise<ProcessedContent | null> {
  const cachePath = path.join(PARSE_CACHE_DIR, `${cacheKey}.bin`)
  try {
    const buf = await fs.promises.readFile(cachePath)
    return v8.deserialize(buf) as ProcessedContent
  } catch {
    return null
  }
}

async function saveCachedResult(cacheKey: string, result: ProcessedContent): Promise<void> {
  try {
    await fs.promises.mkdir(PARSE_CACHE_DIR, { recursive: true })
    const buf = v8.serialize(result)
    await fs.promises.writeFile(path.join(PARSE_CACHE_DIR, `${cacheKey}.bin`), buf)
  } catch {
    // Cache write failures are non-fatal
  }
}

export async function parseMarkdown(ctx: BuildCtx, fps: FilePath[]): Promise<ProcessedContent[]> {
  const { argv } = ctx
  const perf = new PerfTimer()
  const log = new QuartzLogger(argv.verbose)

  // Check parse cache: read file contents, compute hashes, split into cached/uncached
  perf.addEvent("cacheCheck")
  const cachedResults: Map<FilePath, ProcessedContent> = new Map()
  const uncachedFps: FilePath[] = []
  const fileHashes: Map<FilePath, string> = new Map()

  await Promise.all(
    fps.map(async (fp) => {
      try {
        const content = await fs.promises.readFile(fp, "utf-8")
        const relativePath = path.posix.relative(argv.directory, fp)
        const gitDate = ctx.gitModifiedDates?.[relativePath]
        const cacheKey = getCacheKey(content, gitDate)
        fileHashes.set(fp, cacheKey)

        const cached = await loadCachedResult(cacheKey)
        if (cached) {
          cachedResults.set(fp, cached)
        } else {
          uncachedFps.push(fp)
        }
      } catch {
        uncachedFps.push(fp)
      }
    }),
  )

  const cacheHits = cachedResults.size
  const cacheMisses = uncachedFps.length
  console.log(
    `Parse cache: ${cacheHits} hits, ${cacheMisses} misses (${((cacheHits / fps.length) * 100).toFixed(1)}% hit rate) in ${perf.timeSince("cacheCheck")}`,
  )

  // rough heuristics: 128 gives enough time for v8 to JIT and optimize parsing code paths
  const CHUNK_SIZE = 128
  const availableCores =
    typeof os.availableParallelism === "function" ? os.availableParallelism() : os.cpus().length
  const concurrency =
    ctx.argv.concurrency ?? clamp(uncachedFps.length / CHUNK_SIZE, 1, availableCores)

  let freshlyParsed: ProcessedContent[] = []
  if (uncachedFps.length > 0) {
    log.start(`Parsing ${uncachedFps.length} uncached files using ${concurrency} threads`)
    if (concurrency === 1) {
      try {
        const mdRes = await createFileParser(ctx, uncachedFps)(createMdProcessor(ctx))
        freshlyParsed = await createMarkdownParser(ctx, mdRes)(createHtmlProcessor(ctx))
      } catch (error) {
        log.end()
        throw error
      }
    } else {
      await transpileWorkerScript()
      const pool = workerpool.pool("./quartz/bootstrap-worker.mjs", {
        minWorkers: "max",
        maxWorkers: concurrency,
        workerType: "thread",
      })
      const errorHandler = (err: any) => {
        console.error(err)
        process.exit(1)
      }

      const serializableCtx: WorkerSerializableBuildCtx = {
        buildId: ctx.buildId,
        argv: ctx.argv,
        allSlugs: ctx.allSlugs,
        allFiles: ctx.allFiles,
        incremental: ctx.incremental,
        gitModifiedDates: ctx.gitModifiedDates,
      }

      const parsePromises: WorkerPromise<ProcessedContent[]>[] = []
      let processedFiles = 0
      for (const chunk of chunks(uncachedFps, CHUNK_SIZE)) {
        parsePromises.push(pool.exec("parseAndProcessMarkdown", [serializableCtx, chunk]))
      }

      const results: ProcessedContent[][] = await Promise.all(
        parsePromises.map(async (promise) => {
          const result = await promise
          processedFiles += result.length
          log.updateText(`text->html ${chalk.gray(`${processedFiles}/${uncachedFps.length}`)}`)
          return result
        }),
      ).catch(errorHandler)

      freshlyParsed = results.flat()
      await pool.terminate()
    }

    // Save freshly parsed results to cache (async, non-blocking)
    const savePromises = freshlyParsed.map((result) => {
      const [_tree, file] = result
      const fp = file.data.filePath as FilePath
      const cacheKey = fileHashes.get(fp)
      if (cacheKey) {
        return saveCachedResult(cacheKey, result)
      }
    })
    Promise.all(savePromises).catch(() => {}) // fire-and-forget

    log.end(`Parsed ${freshlyParsed.length} files in ${perf.timeSince()}`)
  }

  // Merge cached + freshly parsed results, maintaining original order
  const res: ProcessedContent[] = []
  const freshlyParsedMap = new Map<string, ProcessedContent>()
  for (const result of freshlyParsed) {
    const [_tree, file] = result
    freshlyParsedMap.set(file.data.filePath as string, result)
  }
  for (const fp of fps) {
    const cached = cachedResults.get(fp)
    if (cached) {
      res.push(cached)
    } else {
      const fresh = freshlyParsedMap.get(fp)
      if (fresh) {
        res.push(fresh)
      }
    }
  }

  console.log(
    chalk.gray(
      `Total: ${res.length} files (${cacheHits} cached + ${freshlyParsed.length} parsed) in ${perf.timeSince()}`,
    ),
  )
  return res
}
