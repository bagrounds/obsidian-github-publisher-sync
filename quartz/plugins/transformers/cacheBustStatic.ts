import { QuartzTransformerPlugin } from "../types";
import { visit } from "unist-util-visit";
import { Root, Element } from "hast";
import { hashedAssetPath } from "../../util/staticAssetHash";

// Rewrites `<script src="/static/foo.js">` references in rendered HTML so
// that the browser fetches a content-addressed URL (`/static/foo.<hash>.js`)
// instead of the un-versioned one. This makes browser caching a feature
// rather than a hazard: every change to the underlying script produces a
// new URL, so the cached old copy is never used after a deploy. The Static
// emitter writes both filenames with identical bytes, so direct visits to
// the un-versioned URL keep working too.
//
// The transformer is intentionally narrow: it only touches `<script>` and
// `<link rel="stylesheet">` tags whose `src`/`href` points at `/static/...`
// with a `.js` extension. Anything else is left alone, which keeps the
// blast radius small and means non-cache-bust-aware HTML keeps rendering
// exactly as before.

const STATIC_PREFIX = "/static/";

export const rewriteStaticScriptSrc = (attribute: unknown): string | null => {
  if (typeof attribute !== "string") return null;
  if (!attribute.startsWith(STATIC_PREFIX)) return null;
  const [pathPart, queryPart] = attribute.split("?", 2);
  const relative = pathPart.slice(STATIC_PREFIX.length);
  if (!relative.endsWith(".js")) return null;
  const hashed = hashedAssetPath(relative);
  if (hashed === relative) return null;
  const rewritten = STATIC_PREFIX + hashed;
  return queryPart === undefined ? rewritten : `${rewritten}?${queryPart}`;
};

export const CacheBustStaticAssets: QuartzTransformerPlugin = () => ({
  name: "CacheBustStaticAssets",
  htmlPlugins() {
    return [
      () => (tree: Root) => {
        visit(tree, "element", (node: Element) => {
          if (node.tagName === "script") {
            const rewritten = rewriteStaticScriptSrc(node.properties?.src);
            if (rewritten !== null && node.properties) {
              node.properties.src = rewritten;
            }
          }
        });
      },
    ];
  },
});
