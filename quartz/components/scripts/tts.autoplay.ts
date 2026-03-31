/**
 * Pure utility functions for TTS auto-play feature.
 *
 * Auto-play automatically navigates to the next page when TTS finishes
 * reading the current page. It follows series nav links (⏭️/⏮️),
 * tracks read pages in localStorage, and falls back to BFS over
 * article links when series navigation is exhausted.
 */

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const AUTOPLAY_READ_KEY = "tts-autoplay-read"
export const AUTOPLAY_ENABLED_KEY = "tts-autoplay-enabled"
export const AUTOPLAY_PENDING_KEY = "tts-autoplay-pending"

/** Emoji markers used to identify forward / back nav links. */
export const NEXT_MARKER = "⏭"
export const BACK_MARKER = "⏮"

// ---------------------------------------------------------------------------
// Nav-link detection
// ---------------------------------------------------------------------------

export interface NavLinks {
  next: string | null
  back: string | null
}

export interface LinkInfo {
  text: string
  href: string
}

/**
 * Given an array of {text, href} link descriptors, identify the
 * series-navigation next and back links by their marker emoji.
 */
export function extractNavLinks(links: ReadonlyArray<LinkInfo>): NavLinks {
  return {
    next: links.find((l) => l.text.includes(NEXT_MARKER))?.href ?? null,
    back: links.find((l) => l.text.includes(BACK_MARKER))?.href ?? null,
  }
}

// ---------------------------------------------------------------------------
// Slug helpers
// ---------------------------------------------------------------------------

/**
 * Normalise a URL (absolute or relative path) to a slug string
 * suitable for storage and comparison.
 *
 * Strips the origin, leading slash, trailing slash, and hash fragment.
 */
export function urlToSlug(href: string): string {
  try {
    const url = new URL(href, "https://placeholder.local")
    return url.pathname
      .replace(/^\//, "")
      .replace(/\/$/, "")
      .replace(/#.*$/, "")
  } catch {
    return href
      .replace(/^\//, "")
      .replace(/\/$/, "")
      .replace(/#.*$/, "")
  }
}

/**
 * Return true when a slug represents an index page or the site root.
 * These are excluded from auto-play BFS candidates.
 */
export function isIndexOrHome(slug: string): boolean {
  const normalized = slug.replace(/^\//, "").replace(/\/$/, "")
  return !normalized || normalized === "index" || normalized.endsWith("/index")
}

// ---------------------------------------------------------------------------
// Read-page tracking (pure wrappers — callers supply the storage backend)
// ---------------------------------------------------------------------------

/** Decode a JSON array of slugs from a storage string. */
export function decodeReadPages(stored: string | null): Set<string> {
  try {
    const parsed: unknown = JSON.parse(stored ?? "[]")
    return new Set(Array.isArray(parsed) ? (parsed as string[]) : [])
  } catch {
    return new Set()
  }
}

/** Encode a set of slugs to a JSON string for storage. */
export function encodeReadPages(pages: Set<string>): string {
  return JSON.stringify([...pages])
}

// ---------------------------------------------------------------------------
// Next-URL resolution
// ---------------------------------------------------------------------------

/**
 * Determine the next URL to auto-play.
 *
 * Priority order:
 * 1. Series ⏭️ link (if not already read)
 * 2. Series ⏮️ link (if not already read)
 * 3. First article link (BFS depth-1) that is not an index page,
 *    not the home page, and has not been read.
 * 4. null — nothing left to play.
 */
export function resolveNextUrl(
  navLinks: NavLinks,
  articleLinks: ReadonlyArray<string>,
  readPages: Set<string>,
): string | null {
  // 1. Next in series
  if (
    navLinks.next &&
    !isIndexOrHome(urlToSlug(navLinks.next)) &&
    !readPages.has(urlToSlug(navLinks.next))
  ) {
    return navLinks.next
  }

  // 2. Back in series
  if (
    navLinks.back &&
    !isIndexOrHome(urlToSlug(navLinks.back)) &&
    !readPages.has(urlToSlug(navLinks.back))
  ) {
    return navLinks.back
  }

  // 3. BFS depth-1: first eligible article link
  for (const href of articleLinks) {
    const slug = urlToSlug(href)
    if (!isIndexOrHome(slug) && !readPages.has(slug)) {
      return href
    }
  }

  return null
}
