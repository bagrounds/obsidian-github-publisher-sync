import { PageLayout, SharedLayout } from "./quartz/cfg"
import * as Component from "./quartz/components"

// components shared across all pages
export const sharedPageComponents: SharedLayout = {
  head: Component.Head(),
  header: [],
  afterBody: [
    /* Previous implementation based on giscus docs
    <script src="https://giscus.app/client.js"
      data-repo="bagrounds/obsidian-github-publisher-sync"
      data-repo-id="R_kgDOLuWiLA"
      data-category="Announcements"
      data-category-id="DIC_kwDOLuWiLM4Ckd0H"
      data-mapping="pathname"
      data-strict="1"
      data-reactions-enabled="1"
      data-emit-metadata="0"
      data-input-position="top"
      data-theme="preferred_color_scheme"
      data-lang="en"
      crossorigin="anonymous"
      async>
    </script>
    */
    Component.Graph(),
    Component.Backlinks(),
    Component.Comments({
      provider: 'giscus',
      options: {
        // from data-repo
        repo: 'bagrounds/obsidian-github-publisher-sync',
        // from data-repo-id
        repoId: 'R_kgDOLuWiLA',
        // from data-category
        category: 'Announcements',
        // from data-category-id
        categoryId: 'DIC_kwDOLuWiLM4Ckd0H',
        mapping: 'pathname',
        strict: true,
        reactionsEnabled: true,
        inputPosition: 'top',
      }
    }),
    Component.FixedFooter(),
    Component.TextToSpeech(),
  ],
  footer: Component.Footer({
    links: {
      GitHub: "https://github.com/bagrounds/obsidian-github-publisher-sync"
    },
  }),
}

// components for pages that display a single page (e.g. a single note)
export const defaultContentPageLayout: PageLayout = {
  beforeBody: [
    Component.ContentMeta(),
    Component.TagList(),
  ],
  left: [
    Component.PageTitle(),
    Component.MobileOnly(Component.Spacer()),
    Component.Search(),
    Component.Darkmode(),
    Component.DesktopOnly(Component.TableOfContents()),
  ],
  right: [],
}

// components for pages that display lists of pages  (e.g. tags or folders)
export const defaultListPageLayout: PageLayout = {
  beforeBody: [Component.ContentMeta()],
  left: [
    Component.PageTitle(),
    Component.MobileOnly(Component.Spacer()),
    Component.Search(),
    Component.Darkmode(),
  ],
  right: [],
}
