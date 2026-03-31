/**
 * Tests for the broken link audit library.
 *
 * Covers: sitemap parsing, internal link extraction, random sampling,
 * and URL normalization.
 *
 * @module broken-link-audit.test
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  parseSitemapUrls,
  extractInternalLinks,
  randomSample,
} from "./broken-link-audit.ts";

// --- parseSitemapUrls ---

describe("parseSitemapUrls", () => {
  it("extracts URLs from sitemap XML", () => {
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://bagrounds.org/books/thinking-fast-and-slow</loc></url>
  <url><loc>https://bagrounds.org/reflections/2025-01-01</loc></url>
</urlset>`;

    const urls = parseSitemapUrls(xml);
    assert.equal(urls.length, 2);
    assert.ok(urls.includes("https://bagrounds.org/books/thinking-fast-and-slow"));
    assert.ok(urls.includes("https://bagrounds.org/reflections/2025-01-01"));
  });

  it("returns empty array for empty sitemap", () => {
    const xml = `<?xml version="1.0"?><urlset></urlset>`;
    assert.deepEqual(parseSitemapUrls(xml), []);
  });

  it("filters out XML sitemap index references", () => {
    const xml = `<loc>https://bagrounds.org/sitemap-index.xml</loc>
<loc>https://bagrounds.org/books/test</loc>`;

    const urls = parseSitemapUrls(xml);
    assert.equal(urls.length, 1);
    assert.equal(urls[0], "https://bagrounds.org/books/test");
  });
});

// --- extractInternalLinks ---

describe("extractInternalLinks", () => {
  const siteUrl = "https://bagrounds.org";

  it("extracts absolute internal links", () => {
    const html = `<a href="https://bagrounds.org/books/test">Test</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 1);
    assert.equal(links[0], "https://bagrounds.org/books/test");
  });

  it("extracts relative internal links", () => {
    const html = `<a href="/books/test">Test</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 1);
    assert.equal(links[0], "https://bagrounds.org/books/test");
  });

  it("excludes external links", () => {
    const html = `<a href="https://example.com/page">External</a>
<a href="/books/test">Internal</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 1);
    assert.equal(links[0], "https://bagrounds.org/books/test");
  });

  it("strips anchors from URLs", () => {
    const html = `<a href="/books/test#chapter-1">Link</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 1);
    assert.equal(links[0], "https://bagrounds.org/books/test");
  });

  it("strips query parameters", () => {
    const html = `<a href="/books/test?page=2">Link</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 1);
    assert.equal(links[0], "https://bagrounds.org/books/test");
  });

  it("deduplicates links", () => {
    const html = `<a href="/books/test">Link 1</a>
<a href="/books/test">Link 2</a>
<a href="/books/test#anchor">Link 3</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 1);
  });

  it("excludes the site root URL", () => {
    const html = `<a href="/">Home</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 0);
  });

  it("strips trailing slashes for normalization", () => {
    const html = `<a href="/books/test/">Link</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 1);
    assert.equal(links[0], "https://bagrounds.org/books/test");
  });

  it("handles empty href gracefully", () => {
    const html = `<a href="">Empty</a><a href="#">Anchor</a>`;
    const links = extractInternalLinks(html, siteUrl);
    assert.equal(links.length, 0);
  });
});

// --- randomSample ---

describe("randomSample", () => {
  it("returns requested number of items", () => {
    const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    const sample = randomSample(items, 3);
    assert.equal(sample.length, 3);
  });

  it("returns all items when sample size exceeds array length", () => {
    const items = [1, 2, 3];
    const sample = randomSample(items, 10);
    assert.equal(sample.length, 3);
  });

  it("returns empty array for empty input", () => {
    const sample = randomSample([], 5);
    assert.equal(sample.length, 0);
  });

  it("does not modify original array", () => {
    const items = [1, 2, 3, 4, 5];
    const original = [...items];
    randomSample(items, 3);
    assert.deepEqual(items, original);
  });

  it("returns items from the original array", () => {
    const items = ["a", "b", "c", "d", "e"];
    const sample = randomSample(items, 3);
    sample.forEach((item) => {
      assert.ok(items.includes(item));
    });
  });

  it("returns unique items (no duplicates)", () => {
    const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    const sample = randomSample(items, 5);
    const uniqueSet = new Set(sample);
    assert.equal(uniqueSet.size, sample.length);
  });
});
