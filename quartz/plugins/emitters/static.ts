import { FilePath, QUARTZ, joinSegments } from "../../util/path";
import { QuartzEmitterPlugin } from "../types";
import fs from "fs";
import { glob } from "../../util/glob";
import { dirname, extname } from "path";
import {
  getStaticAssetHash,
  getStaticAssetBytes,
} from "../../util/staticAssetHash";

// Quartz emits files under `quartz/static/` verbatim to `<output>/static/`.
// For JavaScript files we additionally:
//   1. Substitute the `__WORD_METER_VERSION__` placeholder with the file's
//      content hash so the served script reports its own build identifier.
//   2. Write a second copy of the file at `<basename>.<hash>.<ext>` so the
//      CacheBustStaticAssets transformer can rewrite `<script src>` URLs
//      to a content-addressed name and the browser cannot serve a stale
//      cached copy after a deploy.
// The original filename is also written (with the same substituted bytes)
// so direct visits keep working for anyone who has the un-versioned URL.

export const Static: QuartzEmitterPlugin = () => ({
  name: "Static",
  async *emit({ argv, cfg }) {
    const staticPath = joinSegments(QUARTZ, "static");
    const fps = await glob("**", staticPath, cfg.configuration.ignorePatterns);
    const outputStaticPath = joinSegments(argv.output, "static");
    await fs.promises.mkdir(outputStaticPath, { recursive: true });
    for (const fp of fps) {
      const src = joinSegments(staticPath, fp) as FilePath;
      const dest = joinSegments(outputStaticPath, fp) as FilePath;
      await fs.promises.mkdir(dirname(dest), { recursive: true });

      const isJs = extname(fp) === ".js";
      const substituted = isJs ? getStaticAssetBytes(fp) : null;
      if (substituted) {
        await fs.promises.writeFile(dest, substituted);
        yield dest;

        const hash = getStaticAssetHash(fp);
        if (hash) {
          const hashedFp =
            fp.slice(0, fp.length - ".js".length) + `.${hash}.js`;
          const hashedDest = joinSegments(
            outputStaticPath,
            hashedFp,
          ) as FilePath;
          await fs.promises.writeFile(hashedDest, substituted);
          yield hashedDest;
        }
      } else {
        await fs.promises.copyFile(src, dest);
        yield dest;
      }
    }
  },
  async *partialEmit() {},
});
