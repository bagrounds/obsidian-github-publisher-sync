import path from "path"
import fs from "fs"
import { BuildCtx } from "../../util/ctx"
import { FilePath, FullSlug, joinSegments } from "../../util/path"
import { Readable } from "stream"

type WriteOptions = {
  ctx: BuildCtx
  slug: FullSlug
  ext: `.${string}` | ""
  content: string | Buffer | Readable
}

const mkdirPromises = new Map<string, Promise<string | undefined>>()

export const write = async ({ ctx, slug, ext, content }: WriteOptions): Promise<FilePath> => {
  const pathToPage = joinSegments(ctx.argv.output, slug + ext) as FilePath
  const dir = path.dirname(pathToPage)
  if (!mkdirPromises.has(dir)) {
    mkdirPromises.set(dir, fs.promises.mkdir(dir, { recursive: true }))
  }
  await mkdirPromises.get(dir)
  await fs.promises.writeFile(pathToPage, content)
  return pathToPage
}
