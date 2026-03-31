/**
 * Broken Link Audit — samples pages from the live site and checks for broken links.
 *
 * Fetches the sitemap, samples a random subset of pages, extracts internal links
 * from each page, and verifies they resolve successfully.
 *
 * Design:
 * - Uses the sitemap as the source of truth for live pages
 * - Samples pages randomly (configurable count) to stay within time budgets
 * - Checks internal links only (same-domain href attributes)
 * - Logs results for manual review
 * - Non-blocking: always exits 0 so deploys are not gated on audit results
 *
 * @module broken-link-audit
 */

// --- Types ---

export interface AuditConfig {
  /** Base URL of the site (e.g., "https://bagrounds.org") */
  readonly siteUrl: string;
  /** Maximum number of pages to sample from the sitemap */
  readonly sampleSize: number;
  /** Timeout in milliseconds for each HTTP request */
  readonly requestTimeoutMs: number;
}

export interface BrokenLink {
  /** The page containing the broken link */
  readonly sourcePage: string;
  /** The broken link URL */
  readonly targetUrl: string;
  /** HTTP status code received (0 if connection failed) */
  readonly statusCode: number;
}

export interface AuditResult {
  /** Total pages sampled */
  readonly pagesSampled: number;
  /** Total internal links checked */
  readonly linksChecked: number;
  /** Broken links found */
  readonly brokenLinks: readonly BrokenLink[];
  /** Pages that failed to load */
  readonly failedPages: readonly string[];
}

// --- Constants ---

export const DEFAULT_SITE_URL = "https://bagrounds.org";
export const DEFAULT_SAMPLE_SIZE = 30;
export const DEFAULT_REQUEST_TIMEOUT_MS = 10_000;

// --- Sitemap Parsing ---

/**
 * Extract page URLs from a sitemap XML string.
 * Finds all <loc>...</loc> entries and returns their text content.
 */
export const parseSitemapUrls = (xml: string): readonly string[] =>
  Array.from(xml.matchAll(/<loc>([^<]+)<\/loc>/g))
    .map((match) => match[1] as string)
    .filter((url) => !url.endsWith(".xml"));

/**
 * Fetch and parse the sitemap from the live site.
 */
export const fetchSitemapUrls = async (
  siteUrl: string,
  timeoutMs: number,
): Promise<readonly string[]> => {
  const sitemapUrl = `${siteUrl}/sitemap.xml`;
  const response = await fetch(sitemapUrl, {
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!response.ok) {
    console.error(`  ❌ Failed to fetch sitemap: ${response.status} ${response.statusText}`);
    return [];
  }

  const xml = await response.text();
  return parseSitemapUrls(xml);
};

// --- Link Extraction ---

/**
 * Extract internal link hrefs from an HTML page.
 * Only includes same-domain links (starting with / or the site URL).
 * Strips anchors and query parameters for comparison.
 */
export const extractInternalLinks = (
  html: string,
  siteUrl: string,
): readonly string[] => {
  const hrefRegex = /href="([^"]+)"/g;
  const seen = new Set<string>();
  const links: string[] = [];

  Array.from(html.matchAll(hrefRegex)).forEach((match) => {
    const href = (match[1] as string).split("#")[0]?.split("?")[0] ?? "";
    if (!href) return;

    let absoluteUrl: string;
    if (href.startsWith("/")) {
      absoluteUrl = `${siteUrl}${href}`;
    } else if (href.startsWith(siteUrl)) {
      absoluteUrl = href;
    } else {
      return;
    }

    // Normalize: strip trailing slash for consistency
    const normalized = absoluteUrl.replace(/\/$/, "");
    if (!seen.has(normalized) && normalized !== siteUrl) {
      seen.add(normalized);
      links.push(normalized);
    }
  });

  return links;
};

// --- Link Checking ---

/**
 * Check if a URL is reachable via HTTP HEAD request.
 * Returns the status code (0 if connection failed).
 */
export const checkUrl = async (
  url: string,
  timeoutMs: number,
): Promise<number> => {
  try {
    const response = await fetch(url, {
      method: "HEAD",
      redirect: "follow",
      signal: AbortSignal.timeout(timeoutMs),
    });
    return response.status;
  } catch {
    return 0;
  }
};

// --- Random Sampling ---

/**
 * Select a random sample of items from an array.
 * Uses Fisher-Yates partial shuffle for unbiased sampling.
 */
export const randomSample = <T>(
  items: readonly T[],
  count: number,
): readonly T[] => {
  const arr = [...items];
  const n = Math.min(count, arr.length);

  for (let i = 0; i < n; i++) {
    const j = i + Math.floor(Math.random() * (arr.length - i));
    [arr[i], arr[j]] = [arr[j] as T, arr[i] as T];
  }

  return arr.slice(0, n);
};

// --- Orchestration ---

/**
 * Run the broken link audit.
 *
 * 1. Fetch sitemap URLs
 * 2. Sample a random subset of pages
 * 3. For each page, fetch HTML and extract internal links
 * 4. Check each internal link with HEAD request
 * 5. Report broken links
 */
export const runAudit = async (config: AuditConfig): Promise<AuditResult> => {
  console.log(`🔍 Broken link audit: site=${config.siteUrl}, sampleSize=${config.sampleSize}`);

  // 1. Fetch sitemap
  const allUrls = await fetchSitemapUrls(config.siteUrl, config.requestTimeoutMs);
  console.log(`  📋 Sitemap: ${allUrls.length} pages found`);

  if (allUrls.length === 0) {
    return { pagesSampled: 0, linksChecked: 0, brokenLinks: [], failedPages: [] };
  }

  // 2. Sample pages
  const sampledUrls = randomSample(allUrls, config.sampleSize);
  console.log(`  🎲 Sampled ${sampledUrls.length} pages for audit`);

  // 3-4. Check each page's internal links
  const brokenLinks: BrokenLink[] = [];
  const failedPages: string[] = [];
  let totalLinksChecked = 0;

  // Cache of already-checked URLs to avoid redundant requests
  const checkedUrls = new Map<string, number>();

  for (const pageUrl of sampledUrls) {
    try {
      const response = await fetch(pageUrl, {
        signal: AbortSignal.timeout(config.requestTimeoutMs),
      });

      if (!response.ok) {
        failedPages.push(pageUrl);
        console.log(`  ⚠️  Failed to load page: ${pageUrl} (${response.status})`);
        continue;
      }

      const html = await response.text();
      const internalLinks = extractInternalLinks(html, config.siteUrl);

      for (const linkUrl of internalLinks) {
        let status: number;

        if (checkedUrls.has(linkUrl)) {
          status = checkedUrls.get(linkUrl)!;
        } else {
          status = await checkUrl(linkUrl, config.requestTimeoutMs);
          checkedUrls.set(linkUrl, status);
          totalLinksChecked++;
        }

        if (status < 200 || status >= 400) {
          brokenLinks.push({
            sourcePage: pageUrl,
            targetUrl: linkUrl,
            statusCode: status,
          });
        }
      }
    } catch {
      failedPages.push(pageUrl);
      console.log(`  ⚠️  Error loading page: ${pageUrl}`);
    }
  }

  // 5. Report results
  const result: AuditResult = {
    pagesSampled: sampledUrls.length,
    linksChecked: totalLinksChecked,
    brokenLinks,
    failedPages,
  };

  console.log(`\n📊 Audit Results:`);
  console.log(`  📄 Pages sampled: ${result.pagesSampled}`);
  console.log(`  🔗 Links checked: ${result.linksChecked}`);
  console.log(`  ❌ Broken links: ${result.brokenLinks.length}`);
  console.log(`  ⚠️  Failed pages: ${result.failedPages.length}`);

  if (result.brokenLinks.length > 0) {
    console.log(`\n🔴 Broken Links:`);
    result.brokenLinks.forEach((bl) => {
      console.log(`  ${bl.sourcePage} → ${bl.targetUrl} (HTTP ${bl.statusCode})`);
    });
  }

  if (result.failedPages.length > 0) {
    console.log(`\n🟡 Failed Pages:`);
    result.failedPages.forEach((p) => console.log(`  ${p}`));
  }

  if (result.brokenLinks.length === 0 && result.failedPages.length === 0) {
    console.log(`\n✅ No broken links found!`);
  }

  return result;
};
