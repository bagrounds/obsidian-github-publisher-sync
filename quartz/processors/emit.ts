import { PerfTimer } from "../util/perf"
import { getStaticResourcesFromPlugins } from "../plugins"
import { ProcessedContent } from "../plugins/vfile"
import { QuartzLogger } from "../util/log"
import { trace } from "../util/trace"
import { BuildCtx } from "../util/ctx"
import chalk from "chalk"

export async function emitContent(ctx: BuildCtx, content: ProcessedContent[]) {
  const { argv, cfg } = ctx
  const perf = new PerfTimer()
  const log = new QuartzLogger(ctx.argv.verbose)

  log.start(`Emitting files`)

  let emittedFiles = 0
  const staticResources = getStaticResourcesFromPlugins(ctx)
  const emitterTimings: { name: string; files: number; timeMs: number }[] = []
  await Promise.all(
    cfg.plugins.emitters.map(async (emitter) => {
      const emitterStart = performance.now()
      let emitterFiles = 0
      try {
        const emitted = await emitter.emit(ctx, content, staticResources)
        if (Symbol.asyncIterator in emitted) {
          // Async generator case
          for await (const file of emitted) {
            emittedFiles++
            emitterFiles++
            if (ctx.argv.verbose) {
              console.log(`[emit:${emitter.name}] ${file}`)
            } else {
              log.updateText(`${emitter.name} -> ${chalk.gray(file)}`)
            }
          }
        } else {
          // Array case
          emittedFiles += emitted.length
          emitterFiles += emitted.length
          for (const file of emitted) {
            if (ctx.argv.verbose) {
              console.log(`[emit:${emitter.name}] ${file}`)
            } else {
              log.updateText(`${emitter.name} -> ${chalk.gray(file)}`)
            }
          }
        }
      } catch (err) {
        trace(`Failed to emit from plugin \`${emitter.name}\``, err as Error)
      }
      emitterTimings.push({
        name: emitter.name,
        files: emitterFiles,
        timeMs: Math.round(performance.now() - emitterStart),
      })
    }),
  )

  log.end(`Emitted ${emittedFiles} files to \`${argv.output}\` in ${perf.timeSince()}`)
  for (const timing of emitterTimings.sort((a, b) => b.timeMs - a.timeMs)) {
    console.log(
      `  ${chalk.cyan(timing.name)}: ${timing.files} files in ${chalk.yellow(`${(timing.timeMs / 1000).toFixed(1)}s`)}`,
    )
  }
}
