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
      <a
        class="share-button share-mastodon"
        href={`https://mastodon.social/share?text=${encodeURIComponent(shareText)}`}
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Share on Mastodon"
        title="Share on Mastodon"
      >
        🐘 Mastodon
      </a>
      <a
        class="share-button share-twitter"
        href={`https://twitter.com/intent/tweet?text=${encodeURIComponent(shareText)}`}
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
      <a
        class="share-button share-email"
        href={`mailto:?subject=${encodeURIComponent(title)}&body=${encodeURIComponent(shareText)}`}
        aria-label="Share via email"
        title="Share via email"
      >
        📧 Email
      </a>
      <button
        class="share-button share-copy-link"
        aria-label="Copy link to clipboard"
        title="Copy link to clipboard"
      >
        🔗 Copy Link
      </button>
      <button
        class="share-button share-native"
        aria-label="Share via device share menu"
        title="Share via device share menu"
      >
        📲 Share
      </button>
    </div>
  )
}

ShareButtons.afterDOMLoaded = shareScript
ShareButtons.css = shareStyle

export default (() => ShareButtons) satisfies QuartzComponentConstructor
