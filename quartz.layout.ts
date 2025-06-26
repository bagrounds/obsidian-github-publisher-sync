import { PageLayout, SharedLayout } from "./quartz/cfg"
import * as Component from "./quartz/components"

const FixedFooter = ((props: QuartzComponentProps) => {
  const { fileData } = props
  
  // Use the 'amazon' frontmatter field directly for the link
  const amazonLink = fileData.frontmatter?.amazon as string | undefined
  const bookTitle = fileData.frontmatter?.title as string | undefined

  // Only render if the 'amazon' link and 'title' are present in frontmatter
  if (!amazonLink || !bookTitle) {
    return null // Don't render if the required data is missing
  }

  const buttonText = `🛒 Get "${bookTitle}" on Amazon`
  const affiliateDisclosure = "As an Amazon Associate I earn from qualifying purchases."

  return (
    <>
      {/* Inline styles for the fixed footer */}
      <style>
        {`
        .fixed-cta-footer {
          position: fixed;
          bottom: 0;
          left: 0;
          width: 100%;
          background-color: var(--background-secondary); /* Use your theme's background color */
          border-top: 1px solid var(--border);
          padding: 0.8em 1em;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.5em;
          z-index: 1000; /* Ensure it stays above other content */
          box-shadow: 0 -2px 10px rgba(0,0,0,0.1); /* Subtle shadow */
        }

        .fixed-cta-footer .cta-button {
          display: block;
          background-color: #FF9900; /* Amazon orange or your primary brand color */
          color: white;
          padding: 0.7em 1.5em;
          border-radius: 8px; /* More rounded corners */
          text-decoration: none;
          font-weight: bold;
          font-size: 1.1em;
          text-align: center;
          transition: background-color 0.2s ease-in-out;
          width: 100%; /* Make button full width on smaller screens */
          max-width: 300px; /* Max width for desktop */
        }

        .fixed-cta-footer .cta-button:hover {
          background-color: #e68a00; /* Darker orange on hover */
        }

        .fixed-cta-footer .affiliate-text {
          font-size: 0.75em;
          color: var(--text-muted);
          text-align: center;
          margin: 0;
        }

        /* Responsive adjustments for mobile */
        @media (max-width: 768px) {
          .fixed-cta-footer {
            padding: 0.6em 0.5em; /* Reduce padding on smaller screens */
          }
          .fixed-cta-footer .cta-button {
            font-size: 1em;
            padding: 0.6em 1em;
          }
        }
        `}
      </style>
      <div class="fixed-cta-footer">
        <a href={amazonLink} class="cta-button" target="_blank" rel="noopener noreferrer">
          {buttonText}
        </a>
        <p class="affiliate-text">{affiliateDisclosure}</p>
      </div>
    </>
  )
}) as QuartzComponent

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
  ],


FixedFooter,


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
