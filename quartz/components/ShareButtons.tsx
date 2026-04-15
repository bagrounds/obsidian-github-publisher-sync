import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"
import { joinSegments } from "../util/path"
// @ts-ignore
import shareScript from "./scripts/shareButtons.inline"
import shareStyle from "./styles/shareButtons.scss"

const ShareButtons: QuartzComponent = ({ cfg, fileData }: QuartzComponentProps) => {
  const title = fileData.frontmatter?.title ?? ""
  const baseUrl = cfg.baseUrl ?? "example.com"
  const pageUrl =
    fileData.slug === "404" ? `https://${baseUrl}` : joinSegments(`https://${baseUrl}`, fileData.slug!)

  const shareText = `${title}\n\n${pageUrl}`

  return (
    <div
      class="share-buttons"
      data-url={pageUrl}
      data-title={title}
      data-share-text={shareText}
    >
      <span class="share-label">Share</span>
      <a
        class="share-button share-bluesky"
        href={`https://bsky.app/intent/compose?text=${encodeURIComponent(shareText)}`}
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Share on Bluesky"
        title="Share on Bluesky"
      >
        🦋 Bluesky
      </a>
      <button
        class="share-button share-mastodon"
        aria-label="Share on Mastodon"
        title="Share on Mastodon (Shift+click to change instance)"
        data-share-text={shareText}
      >
        🐘 Mastodon
      </button>
      <a
        class="share-button share-twitter"
        href={`https://twitter.com/intent/tweet?text=${encodeURIComponent(title)}&url=${encodeURIComponent(pageUrl)}`}
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Share on Twitter"
        title="Share on Twitter"
      >
        𝕏 Twitter
      </a>
      <a
        class="share-button share-sms"
        href={`sms:?&body=${encodeURIComponent(shareText)}`}
        aria-label="Share via text message"
        title="Share via text message"
      >
        💬 Text
      </a>
    </div>
  )
}

ShareButtons.afterDOMLoaded = shareScript
ShareButtons.css = shareStyle

export default (() => ShareButtons) satisfies QuartzComponentConstructor
