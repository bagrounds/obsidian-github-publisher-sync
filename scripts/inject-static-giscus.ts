/**
 * Post-build script: inject static Giscus comments into generated HTML pages.
 *
 * Fetches all Giscus discussion comments via GitHub GraphQL API, then walks
 * the public/ directory injecting static HTML comments before each page's
 * .giscus div. This makes comments visible to search engines (SEO) while
 * the client-side script swaps them for live Giscus iframes when loaded.
 *
 * Usage: GITHUB_TOKEN=... npx tsx scripts/inject-static-giscus.ts [publicDir]
 */

import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import {
  fetchAllDiscussions,
  buildCommentsMap,
  injectStaticComments,
  type CommentsMap,
} from "./lib/static-giscus.ts";

const OWNER = "bagrounds";
const REPO = "obsidian-github-publisher-sync";
const CATEGORY_ID = "DIC_kwDOLuWiLM4Ckd0H";

const walkHtmlFiles = (dir: string): readonly string[] =>
  readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".html"))
    .map((entry) => join(entry.parentPath, entry.name));

const injectCommentsIntoFiles = (
  publicDir: string,
  commentsMap: CommentsMap,
): number =>
  walkHtmlFiles(publicDir).reduce((injected, filePath) => {
    const original = readFileSync(filePath, "utf-8");
    const modified = injectStaticComments(original, commentsMap);
    if (modified !== original) {
      writeFileSync(filePath, modified, "utf-8");
      return injected + 1;
    }
    return injected;
  }, 0);

const main = async (): Promise<void> => {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    console.log(JSON.stringify({ event: "skip_static_giscus", reason: "no GITHUB_TOKEN" }));
    return;
  }

  console.log(JSON.stringify({ event: "static_giscus_start" }));

  const discussions = await fetchAllDiscussions(token, OWNER, REPO, CATEGORY_ID);
  console.log(
    JSON.stringify({ event: "static_giscus_fetched", discussionCount: discussions.length }),
  );

  const commentsMap = buildCommentsMap(discussions);
  const pathnames = Object.keys(commentsMap);
  console.log(JSON.stringify({ event: "static_giscus_mapped", pathnames: pathnames.length, sample: pathnames.slice(0, 5) }));

  const publicDir = process.argv[2] ?? join(process.cwd(), "public");
  const injected = injectCommentsIntoFiles(publicDir, commentsMap);
  console.log(JSON.stringify({ event: "static_giscus_done", injectedPages: injected }));
};

main().catch((err) => {
  console.error(
    JSON.stringify({
      event: "static_giscus_error",
      message: err instanceof Error ? err.message : String(err),
    }),
  );
  process.exit(1);
});
