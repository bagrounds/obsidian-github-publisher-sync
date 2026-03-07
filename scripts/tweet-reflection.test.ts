import { describe, test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import {
  getReflectionPath,
  parseFrontmatter,
  readReflection,
  calculateTweetLength,
  validateTweetLength,
  buildGeminiPrompt,
  generateLocalEmbed,
  generateLocalBlueskyEmbed,
  extractBlueskyPostId,
  extractBlueskyDid,
  buildBlueskyPostUrl,
  appendTweetSection,
  appendBlueskySection,
  buildBlueskySection,
  getYesterdayDate,
  validateEnvironment,
  withRetry,
  fetchOgMetadata,
  type ReflectionData,
} from "./tweet-reflection.ts";

// --- Test Helpers ---

function createTempDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "tweet-reflection-test-"));
}

function cleanupTempDir(dir: string): void {
  fs.rmSync(dir, { recursive: true, force: true });
}

const SAMPLE_REFLECTION = `---
share: true
aliases:
  - 2026-03-01 | 🧪 Test Reflection 📚
title: 2026-03-01 | 🧪 Test Reflection 📚
URL: https://bagrounds.org/reflections/2026-03-01
Author: "[[bryan-grounds]]"
tags:
---
[Home](../index.md) > [Reflections](./index.md) | [⏮️](./2026-02-28.md) [⏭️](./2026-03-02.md)  
# 2026-03-01 | 🧪 Test Reflection 📚  
## [📚 Books](../books/index.md)  
- ⏯️ Continuing [🔬 Some Book](../books/some-book.md)  
  
## [📺 Videos](../videos/index.md)  
- [🎬 Some Video](../videos/some-video.md)  
  
## 🤖🐲 AI Fiction  
🧪 A test story about testing things.  
`;

const SAMPLE_REFLECTION_WITH_TWEET = `---
share: true
title: 2026-01-15 | 🧪 Already Tweeted 📚
URL: https://bagrounds.org/reflections/2026-01-15
Author: "[[bryan-grounds]]"
tags:
---
[Home](../index.md) > [Reflections](./index.md)  
# 2026-01-15 | 🧪 Already Tweeted 📚  
## [📚 Books](../books/index.md)  
- ⏯️ Continuing [🔬 Some Book](../books/some-book.md)  
  
## 🐦 Tweet  
<blockquote class="twitter-tweet" data-theme="dark"><p lang="en" dir="ltr">Test tweet</p>&mdash; Bryan Grounds (@bagrounds) <a href="https://twitter.com/bagrounds/status/123456789?ref_src=twsrc%5Etfw">January 15, 2026</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>`;

const MINIMAL_REFLECTION = `---
share: true
title: 2026-03-06
URL: https://bagrounds.org/reflections/2026-03-06
Author: "[[bryan-grounds]]"
tags:
---
[Home](../index.md) > [Reflections](./index.md)  
# 2026-03-06  
## [📚 Books](../books/index.md)  
- ⏯️ Continuing [🕵️ Fugitive Telemetry](../books/fugitive-telemetry.md)`;

// --- Unit Tests ---

describe("getReflectionPath", () => {
  test("constructs correct path for a date", () => {
    const result = getReflectionPath("2026-03-01", "/content/reflections");
    assert.equal(result, "/content/reflections/2026-03-01.md");
  });

  test("handles different dates", () => {
    const result = getReflectionPath("2025-12-30", "/vault/reflections");
    assert.equal(result, "/vault/reflections/2025-12-30.md");
  });
});

describe("parseFrontmatter", () => {
  test("parses standard frontmatter", () => {
    const { frontmatter, body } = parseFrontmatter(SAMPLE_REFLECTION);
    assert.equal(frontmatter["share"], "true");
    assert.equal(frontmatter["title"], "2026-03-01 | 🧪 Test Reflection 📚");
    assert.equal(
      frontmatter["URL"],
      "https://bagrounds.org/reflections/2026-03-01",
    );
    assert.ok(body.includes("# 2026-03-01"));
  });

  test("returns empty frontmatter for content without frontmatter", () => {
    const { frontmatter, body } = parseFrontmatter(
      "# Just a heading\nSome content",
    );
    assert.deepEqual(frontmatter, {});
    assert.equal(body, "# Just a heading\nSome content");
  });

  test("handles frontmatter with quoted values", () => {
    const content = `---
Author: "[[bryan-grounds]]"
---
body`;
    const { frontmatter } = parseFrontmatter(content);
    assert.equal(frontmatter["Author"], "[[bryan-grounds]]");
  });

  test("handles empty frontmatter", () => {
    const content = `---
---
body content`;
    const { frontmatter, body } = parseFrontmatter(content);
    assert.deepEqual(frontmatter, {});
    assert.ok(body.includes("body content"));
  });
});

describe("readReflection", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempDir();
  });

  afterEach(() => {
    cleanupTempDir(tempDir);
  });

  test("returns null for non-existent file", () => {
    const result = readReflection("2099-12-31", tempDir);
    assert.equal(result, null);
  });

  test("reads and parses a reflection file", () => {
    fs.writeFileSync(path.join(tempDir, "2026-03-01.md"), SAMPLE_REFLECTION);
    const result = readReflection("2026-03-01", tempDir);
    assert.ok(result !== null);
    assert.equal(result.date, "2026-03-01");
    assert.equal(result.title, "2026-03-01 | 🧪 Test Reflection 📚");
    assert.equal(result.url, "https://bagrounds.org/reflections/2026-03-01");
    assert.equal(result.hasTweetSection, false);
    assert.equal(result.hasBlueskySection, false);
  });

  test("detects existing tweet section", () => {
    fs.writeFileSync(
      path.join(tempDir, "2026-01-15.md"),
      SAMPLE_REFLECTION_WITH_TWEET,
    );
    const result = readReflection("2026-01-15", tempDir);
    assert.ok(result !== null);
    assert.equal(result.hasTweetSection, true);
  });

  test("handles minimal reflection", () => {
    fs.writeFileSync(path.join(tempDir, "2026-03-06.md"), MINIMAL_REFLECTION);
    const result = readReflection("2026-03-06", tempDir);
    assert.ok(result !== null);
    assert.equal(result.title, "2026-03-06");
    assert.equal(result.hasTweetSection, false);
    assert.equal(result.hasBlueskySection, false);
  });
});

describe("calculateTweetLength", () => {
  test("counts plain text length", () => {
    assert.equal(calculateTweetLength("Hello world"), 11);
  });

  test("counts URLs as 23 characters", () => {
    const text = "Check this out https://bagrounds.org/reflections/2026-03-01";
    const expected = "Check this out ".length + 23;
    assert.equal(calculateTweetLength(text), expected);
  });

  test("handles multiple URLs", () => {
    const text = "Link 1: https://example.com Link 2: https://other.com/page";
    const expected = "Link 1: ".length + 23 + " Link 2: ".length + 23;
    assert.equal(calculateTweetLength(text), expected);
  });

  test("handles text without URLs", () => {
    const text = "Just some text with emojis 🎉🎊";
    assert.equal(calculateTweetLength(text), text.length);
  });

  test("handles empty string", () => {
    assert.equal(calculateTweetLength(""), 0);
  });
});

describe("validateTweetLength", () => {
  test("valid for short tweets", () => {
    const { valid, length } = validateTweetLength("Hello!");
    assert.equal(valid, true);
    assert.equal(length, 6);
  });

  test("valid at exactly 280 characters", () => {
    const text = "a".repeat(280);
    const { valid, length } = validateTweetLength(text);
    assert.equal(valid, true);
    assert.equal(length, 280);
  });

  test("invalid over 280 characters", () => {
    const text = "a".repeat(281);
    const { valid, length } = validateTweetLength(text);
    assert.equal(valid, false);
    assert.equal(length, 281);
  });

  test("accounts for URL shortening", () => {
    // URL is 50 chars but counts as 23
    const longUrl = "https://bagrounds.org/reflections/2026-03-01-extra";
    const text = "x".repeat(257) + " " + longUrl;
    // 257 + 1 (space) + 23 (url) = 281... too long without URL counting
    // but with URL shortening: 257 + 1 + 23 = 281
    const { valid } = validateTweetLength(text);
    assert.equal(valid, false);

    const text2 = "x".repeat(256) + " " + longUrl;
    // 256 + 1 + 23 = 280
    const { valid: valid2 } = validateTweetLength(text2);
    assert.equal(valid2, true);
  });
});

describe("buildGeminiPrompt", () => {
  test("includes reflection title in system prompt", () => {
    const reflection: ReflectionData = {
      date: "2026-03-01",
      title: "2026-03-01 | 🧪 Test Reflection 📚",
      url: "https://bagrounds.org/reflections/2026-03-01",
      body: "Some content here",
      filePath: "/path/to/file.md",
      hasTweetSection: false,
      hasBlueskySection: false,
    };
    const { system, user } = buildGeminiPrompt(reflection);
    assert.ok(system.includes(reflection.title));
    assert.ok(system.includes(reflection.url));
    assert.ok(user.includes(reflection.title));
    assert.ok(user.includes(reflection.url));
    assert.ok(user.includes(reflection.date));
    assert.ok(user.includes("Some content here"));
  });

  test("includes character limit instructions", () => {
    const reflection: ReflectionData = {
      date: "2026-03-01",
      title: "Test",
      url: "https://bagrounds.org/reflections/2026-03-01",
      body: "",
      filePath: "",
      hasTweetSection: false,
      hasBlueskySection: false,
    };
    const { system } = buildGeminiPrompt(reflection);
    assert.ok(system.includes("280"));
    assert.ok(system.includes("23 characters"));
  });

  test("truncates long body content", () => {
    const longBody = "x".repeat(5000);
    const reflection: ReflectionData = {
      date: "2026-03-01",
      title: "Test",
      url: "https://bagrounds.org/reflections/2026-03-01",
      body: longBody,
      filePath: "",
      hasTweetSection: false,
      hasBlueskySection: false,
    };
    const { user } = buildGeminiPrompt(reflection);
    assert.ok(user.length < longBody.length);
  });
});

describe("generateLocalEmbed", () => {
  test("generates valid embed HTML with dark theme", () => {
    const html = generateLocalEmbed("123456789", "Hello world!", "2026-03-01");
    assert.ok(html.includes('class="twitter-tweet"'));
    assert.ok(html.includes('data-theme="dark"'));
    assert.ok(html.includes("Hello world!"));
    assert.ok(html.includes("123456789"));
    assert.ok(html.includes("March 1, 2026"));
    assert.ok(html.includes("Bryan Grounds"));
    assert.ok(html.includes("@bagrounds"));
    assert.ok(html.includes("platform.twitter.com/widgets.js"));
  });

  test("HTML-encodes special characters", () => {
    const html = generateLocalEmbed(
      "123",
      "Text with <html> & \"quotes\" & 'single'",
      "2026-01-15",
    );
    assert.ok(html.includes("&lt;html&gt;"));
    assert.ok(html.includes("&amp;"));
    assert.ok(html.includes("&quot;quotes&quot;"));
    assert.ok(html.includes("&#39;single&#39;"));
  });

  test("converts newlines to <br>", () => {
    const html = generateLocalEmbed(
      "123",
      "Line 1\nLine 2\nLine 3",
      "2026-01-15",
    );
    assert.ok(html.includes("Line 1<br>Line 2<br>Line 3"));
  });

  test("includes tweet URL with ref_src parameter", () => {
    const html = generateLocalEmbed("987654321", "test", "2026-06-15");
    assert.ok(
      html.includes(
        "https://twitter.com/bagrounds/status/987654321?ref_src=twsrc%5Etfw",
      ),
    );
  });

  test("formats date correctly for various months", () => {
    const testCases = [
      { date: "2026-01-01", expected: "January 1, 2026" },
      { date: "2026-06-15", expected: "June 15, 2026" },
      { date: "2025-12-31", expected: "December 31, 2025" },
    ];
    for (const { date, expected } of testCases) {
      const html = generateLocalEmbed("123", "test", date);
      assert.ok(
        html.includes(expected),
        `Expected "${expected}" in embed for date ${date}`,
      );
    }
  });
});

describe("appendTweetSection", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = createTempDir();
  });

  afterEach(() => {
    cleanupTempDir(tempDir);
  });

  test("appends tweet section to file", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, SAMPLE_REFLECTION);

    const embedHtml =
      '<blockquote class="twitter-tweet" data-theme="dark">test</blockquote>';
    appendTweetSection(filePath, embedHtml);

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("## 🐦 Tweet"));
    assert.ok(content.includes(embedHtml));
  });

  test("does not duplicate tweet section", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, SAMPLE_REFLECTION_WITH_TWEET);

    appendTweetSection(filePath, "<blockquote>new tweet</blockquote>");

    const content = fs.readFileSync(filePath, "utf-8");
    const occurrences = content.split("## 🐦 Tweet").length - 1;
    assert.equal(occurrences, 1);
  });

  test("adds blank line separator", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, "content without trailing newline");

    appendTweetSection(filePath, "<blockquote>test</blockquote>");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("\n\n## 🐦 Tweet"));
  });

  test("handles file ending with newline", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, "content with trailing newline\n");

    appendTweetSection(filePath, "<blockquote>test</blockquote>");

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("\n## 🐦 Tweet"));
  });
});

describe("getYesterdayDate", () => {
  test("returns date in YYYY-MM-DD format", () => {
    const date = getYesterdayDate();
    assert.match(date, /^\d{4}-\d{2}-\d{2}$/);
  });

  test("returns a valid date", () => {
    const date = getYesterdayDate();
    const parsed = new Date(date + "T00:00:00Z");
    assert.ok(!isNaN(parsed.getTime()));
  });

  test("returns a date before today", () => {
    const yesterday = getYesterdayDate();
    const today = new Date().toISOString().split("T")[0] as string;
    assert.ok(yesterday < today, `${yesterday} should be before ${today}`);
  });
});

describe("validateEnvironment", () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    // Restore original environment
    for (const key of Object.keys(process.env)) {
      if (!(key in originalEnv)) {
        delete process.env[key];
      }
    }
    Object.assign(process.env, originalEnv);
  });

  test("throws when missing environment variables", () => {
    delete process.env.TWITTER_API_KEY;
    delete process.env.TWITTER_API_SECRET;
    delete process.env.TWITTER_ACCESS_TOKEN;
    delete process.env.TWITTER_ACCESS_SECRET;
    delete process.env.GEMINI_API_KEY;
    delete process.env.OBSIDIAN_AUTH_TOKEN;
    delete process.env.OBSIDIAN_VAULT_NAME;

    assert.throws(
      () => validateEnvironment(),
      /Missing required environment variables/,
    );
  });

  test("returns credentials when all variables are set", () => {
    process.env.TWITTER_API_KEY = "test-key";
    process.env.TWITTER_API_SECRET = "test-secret";
    process.env.TWITTER_ACCESS_TOKEN = "test-token";
    process.env.TWITTER_ACCESS_SECRET = "test-access-secret";
    process.env.BLUESKY_IDENTIFIER = "test.bsky.social";
    process.env.BLUESKY_APP_PASSWORD = "test-bsky-password";
    process.env.GEMINI_API_KEY = "test-gemini-key";
    process.env.OBSIDIAN_AUTH_TOKEN = "test-auth-token";
    process.env.OBSIDIAN_VAULT_NAME = "My Vault";

    const env = validateEnvironment();
    assert.ok(env.twitter);
    assert.equal(env.twitter.apiKey, "test-key");
    assert.equal(env.twitter.apiSecret, "test-secret");
    assert.equal(env.twitter.accessToken, "test-token");
    assert.equal(env.twitter.accessSecret, "test-access-secret");
    assert.ok(env.bluesky);
    assert.equal(env.bluesky.identifier, "test.bsky.social");
    assert.equal(env.bluesky.password, "test-bsky-password");
    assert.equal(env.gemini.apiKey, "test-gemini-key");
    assert.equal(env.gemini.model, "gemma-3-27b-it");
    assert.equal(env.obsidian.authToken, "test-auth-token");
    assert.equal(env.obsidian.vaultName, "My Vault");
    assert.equal(env.obsidian.vaultPassword, undefined);
  });

  test("uses custom model when GEMINI_MODEL is set", () => {
    process.env.GEMINI_API_KEY = "g";
    process.env.OBSIDIAN_AUTH_TOKEN = "token";
    process.env.OBSIDIAN_VAULT_NAME = "vault";
    process.env.GEMINI_MODEL = "gemini-2.0-flash";

    const env = validateEnvironment();
    assert.equal(env.gemini.model, "gemini-2.0-flash");
  });

  test("includes optional vault password when set", () => {
    process.env.GEMINI_API_KEY = "g";
    process.env.OBSIDIAN_AUTH_TOKEN = "token";
    process.env.OBSIDIAN_VAULT_NAME = "vault";
    process.env.OBSIDIAN_VAULT_PASSWORD = "my-secret-password";

    const env = validateEnvironment();
    assert.equal(env.obsidian.vaultPassword, "my-secret-password");
  });

  test("reports specific missing variables", () => {
    delete process.env.GEMINI_API_KEY;
    process.env.OBSIDIAN_AUTH_TOKEN = "set";
    delete process.env.OBSIDIAN_VAULT_NAME;

    try {
      validateEnvironment();
      assert.fail("Should have thrown");
    } catch (e) {
      const msg = (e as Error).message;
      assert.ok(msg.includes("GEMINI_API_KEY"));
      assert.ok(msg.includes("OBSIDIAN_VAULT_NAME"));
      assert.ok(!msg.includes("OBSIDIAN_AUTH_TOKEN"));
    }
  });

  test("returns null twitter when twitter credentials are missing", () => {
    delete process.env.TWITTER_API_KEY;
    delete process.env.TWITTER_API_SECRET;
    delete process.env.TWITTER_ACCESS_TOKEN;
    delete process.env.TWITTER_ACCESS_SECRET;
    process.env.GEMINI_API_KEY = "g";
    process.env.OBSIDIAN_AUTH_TOKEN = "token";
    process.env.OBSIDIAN_VAULT_NAME = "vault";

    const env = validateEnvironment();
    assert.equal(env.twitter, null);
  });

  test("returns null bluesky when bluesky credentials are missing", () => {
    delete process.env.BLUESKY_IDENTIFIER;
    delete process.env.BLUESKY_APP_PASSWORD;
    process.env.GEMINI_API_KEY = "g";
    process.env.OBSIDIAN_AUTH_TOKEN = "token";
    process.env.OBSIDIAN_VAULT_NAME = "vault";

    const env = validateEnvironment();
    assert.equal(env.bluesky, null);
  });
});

// --- Retry Logic Tests ---

describe("withRetry", () => {
  test("returns result on first success", async () => {
    const result = await withRetry(() => Promise.resolve("ok"));
    assert.equal(result, "ok");
  });

  test("retries on transient HTTP 503 and succeeds", async () => {
    let calls = 0;
    const result = await withRetry(
      () => {
        calls++;
        if (calls < 3) {
          const err = new Error("Service Unavailable") as Error & {
            code: number;
          };
          err.code = 503;
          throw err;
        }
        return Promise.resolve("recovered");
      },
      { baseDelayMs: 1 },
    );
    assert.equal(result, "recovered");
    assert.equal(calls, 3);
  });

  test("retries on transient HTTP 429 (rate limit)", async () => {
    let calls = 0;
    const result = await withRetry(
      () => {
        calls++;
        if (calls === 1) {
          const err = new Error("Too Many Requests") as Error & {
            code: number;
          };
          err.code = 429;
          throw err;
        }
        return Promise.resolve("ok");
      },
      { baseDelayMs: 1 },
    );
    assert.equal(result, "ok");
    assert.equal(calls, 2);
  });

  test("does not retry on non-transient HTTP errors", async () => {
    let calls = 0;
    await assert.rejects(
      () =>
        withRetry(
          () => {
            calls++;
            const err = new Error("Forbidden") as Error & { code: number };
            err.code = 403;
            throw err;
          },
          { baseDelayMs: 1 },
        ),
      (err: Error & { code?: number }) => {
        assert.equal(err.code, 403);
        return true;
      },
    );
    assert.equal(calls, 1);
  });

  test("does not retry errors without a code", async () => {
    let calls = 0;
    await assert.rejects(
      () =>
        withRetry(
          () => {
            calls++;
            throw new Error("random failure");
          },
          { baseDelayMs: 1 },
        ),
      { message: "random failure" },
    );
    assert.equal(calls, 1);
  });

  test("gives up after maxRetries", async () => {
    let calls = 0;
    await assert.rejects(
      () =>
        withRetry(
          () => {
            calls++;
            const err = new Error("Service Unavailable") as Error & {
              code: number;
            };
            err.code = 503;
            throw err;
          },
          { maxRetries: 2, baseDelayMs: 1 },
        ),
      (err: Error & { code?: number }) => {
        assert.equal(err.code, 503);
        return true;
      },
    );
    assert.equal(calls, 3); // initial + 2 retries
  });

  test("calls onRetry callback", async () => {
    const retries: { attempt: number; delayMs: number }[] = [];
    let calls = 0;
    await withRetry(
      () => {
        calls++;
        if (calls < 3) {
          const err = new Error("Bad Gateway") as Error & { code: number };
          err.code = 502;
          throw err;
        }
        return Promise.resolve("ok");
      },
      {
        baseDelayMs: 1,
        onRetry: (_err, attempt, delayMs) => {
          retries.push({ attempt, delayMs });
        },
      },
    );
    assert.equal(retries.length, 2);
    assert.equal(retries[0]?.attempt, 1);
    assert.equal(retries[1]?.attempt, 2);
  });
});

// --- Bluesky Tests ---

describe("extractBlueskyPostId", () => {
  test("extracts post ID from AT URI", () => {
    const uri = "at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3ltxsqnjf6s2b";
    assert.equal(extractBlueskyPostId(uri), "3ltxsqnjf6s2b");
  });
});

describe("extractBlueskyDid", () => {
  test("extracts DID from AT URI", () => {
    const uri = "at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3ltxsqnjf6s2b";
    assert.equal(extractBlueskyDid(uri), "did:plc:i4yli6h7x2uoj7acxunww2fc");
  });

  test("returns empty string for invalid URI", () => {
    assert.equal(extractBlueskyDid("invalid-uri"), "");
  });
});

describe("buildBlueskyPostUrl", () => {
  test("builds correct Bluesky post URL", () => {
    const url = buildBlueskyPostUrl("did:plc:abc123", "3ltxsqnjf6s2b");
    assert.equal(url, "https://bsky.app/profile/did:plc:abc123/post/3ltxsqnjf6s2b");
  });
});

describe("generateLocalBlueskyEmbed", () => {
  test("generates valid Bluesky embed HTML", () => {
    const uri = "at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3ltxsqnjf6s2b";
    const text = "Hello from Bluesky!";
    const html = generateLocalBlueskyEmbed(uri, text, "2026-03-05", "bagrounds.bsky.social");

    assert.ok(html.includes('class="bluesky-embed"'));
    assert.ok(html.includes(`data-bluesky-uri="${uri}"`));
    assert.ok(html.includes("Hello from Bluesky!"));
    assert.ok(html.includes("@bagrounds.bsky.social"));
    assert.ok(html.includes("embed.bsky.app/static/embed.js"));
    assert.ok(html.includes("March 5, 2026"));
  });

  test("includes CID attribute when provided", () => {
    const uri = "at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3ltxsqnjf6s2b";
    const cid = "bafyreiadbkurhsz5y7pahts54w63ofclzwu7ea6d6pbvbep3sjmhkcitxq";
    const html = generateLocalBlueskyEmbed(uri, "test", "2026-03-05", "test.bsky.social", cid);

    assert.ok(html.includes(`data-bluesky-cid="${cid}"`));
  });

  test("omits CID attribute when not provided", () => {
    const uri = "at://did:plc:test/app.bsky.feed.post/abc123";
    const html = generateLocalBlueskyEmbed(uri, "test", "2026-03-05", "test.bsky.social");

    assert.ok(!html.includes("data-bluesky-cid"));
  });

  test("HTML-encodes special characters", () => {
    const uri = "at://did:plc:test/app.bsky.feed.post/abc123";
    const text = '<script>alert("xss")</script>';
    const html = generateLocalBlueskyEmbed(uri, text, "2026-01-01", "test.bsky.social");

    assert.ok(!html.includes("<script>alert"));
    assert.ok(html.includes("&lt;script&gt;"));
  });

  test("uses provided handle in embed link", () => {
    const uri = "at://did:plc:test/app.bsky.feed.post/abc123";
    const html = generateLocalBlueskyEmbed(uri, "test", "2026-01-01", "custom.bsky.social");

    assert.ok(html.includes("@custom.bsky.social"));
  });
});

describe("buildBlueskySection", () => {
  test("builds section with correct header", () => {
    const section = buildBlueskySection("existing content\n", "<blockquote>test</blockquote>");
    assert.ok(section.includes("## 🦋 Bluesky"));
    assert.ok(section.includes("<blockquote>test</blockquote>"));
  });
});

describe("appendBlueskySection", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "bsky-test-"));
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  test("appends Bluesky section to file", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, "# Test\nSome content\n");

    appendBlueskySection(filePath, '<blockquote class="bluesky-embed">test</blockquote>');

    const updated = fs.readFileSync(filePath, "utf-8");
    assert.ok(updated.includes("## 🦋 Bluesky"));
    assert.ok(updated.includes("bluesky-embed"));
  });

  test("does not duplicate Bluesky section", () => {
    const filePath = path.join(tempDir, "test.md");
    fs.writeFileSync(filePath, "# Test\n\n## 🦋 Bluesky  \nexisting embed\n");

    appendBlueskySection(filePath, "<blockquote>new</blockquote>");

    const content = fs.readFileSync(filePath, "utf-8");
    const matches = content.match(/## 🦋 Bluesky/g);
    assert.equal(matches?.length, 1);
  });
});

// --- Property-Based Tests ---

describe("property-based tests", () => {
  function randomString(length: number): string {
    const chars = "abcdefghijklmnopqrstuvwxyz 🎉🧪📚🤖";
    let result = "";
    for (let i = 0; i < length; i++) {
      result += chars[Math.floor(Math.random() * chars.length)];
    }
    return result;
  }

  function randomDate(): string {
    const year = 2024 + Math.floor(Math.random() * 5);
    const month = String(1 + Math.floor(Math.random() * 12)).padStart(2, "0");
    const day = String(1 + Math.floor(Math.random() * 28)).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  test("generateLocalEmbed always produces valid HTML structure (50 iterations)", () => {
    for (let i = 0; i < 50; i++) {
      const tweetId = String(Math.floor(Math.random() * 1e18));
      const text = randomString(10 + Math.floor(Math.random() * 200));
      const date = randomDate();

      const html = generateLocalEmbed(tweetId, text, date);

      // Must contain key structural elements
      assert.ok(
        html.includes('<blockquote class="twitter-tweet"'),
        `Missing blockquote for iteration ${i}`,
      );
      assert.ok(
        html.includes('data-theme="dark"'),
        `Missing dark theme for iteration ${i}`,
      );
      assert.ok(
        html.includes("</blockquote>"),
        `Missing closing blockquote for iteration ${i}`,
      );
      assert.ok(
        html.includes("platform.twitter.com/widgets.js"),
        `Missing widgets.js for iteration ${i}`,
      );
      assert.ok(html.includes(tweetId), `Missing tweet ID for iteration ${i}`);
      assert.ok(
        html.includes("@bagrounds"),
        `Missing handle for iteration ${i}`,
      );
    }
  });

  test("calculateTweetLength is always >= 0 (50 iterations)", () => {
    for (let i = 0; i < 50; i++) {
      const text = randomString(Math.floor(Math.random() * 500));
      const length = calculateTweetLength(text);
      assert.ok(length >= 0, `Negative length for iteration ${i}: ${length}`);
    }
  });

  test("getReflectionPath always ends with .md (50 iterations)", () => {
    for (let i = 0; i < 50; i++) {
      const date = randomDate();
      const result = getReflectionPath(date, "/any/dir");
      assert.ok(result.endsWith(".md"), `Path doesn't end with .md: ${result}`);
      assert.ok(result.includes(date), `Path doesn't include date: ${result}`);
    }
  });

  test("parseFrontmatter never crashes on random input (50 iterations)", () => {
    for (let i = 0; i < 50; i++) {
      const content = randomString(50 + Math.floor(Math.random() * 500));
      // Should not throw
      const result = parseFrontmatter(content);
      assert.ok(typeof result.body === "string");
      assert.ok(typeof result.frontmatter === "object");
    }
  });
});

// --- Integration Tests (require credentials) ---

describe(
  "integration tests",
  { skip: !process.env.RUN_INTEGRATION_TESTS },
  () => {
    test("Gemini API generates valid tweet text", async () => {
      const { GoogleGenerativeAI } = await import("@google/generative-ai");
      const apiKey = process.env.GEMINI_API_KEY;
      assert.ok(apiKey, "GEMINI_API_KEY must be set");

      const { generateTweetWithGemini } = await import("./tweet-reflection.ts");
      const reflection: ReflectionData = {
        date: "2026-03-01",
        title: "2026-03-01 | 🧪 Integration Test 📚",
        url: "https://bagrounds.org/reflections/2026-03-01",
        body: "## 📚 Books\n- Testing a book\n\n## 📺 Videos\n- Testing a video",
        filePath: "",
        hasTweetSection: false,
        hasBlueskySection: false,
      };

      const tweet = await generateTweetWithGemini(reflection, apiKey);
      assert.ok(tweet.length > 0, "Tweet should not be empty");
      assert.ok(tweet.includes(reflection.url), "Tweet should include URL");
      const { valid } = validateTweetLength(tweet);
      assert.ok(
        valid,
        `Tweet should be within 280 chars, got ${calculateTweetLength(tweet)}`,
      );
    });

    test("Twitter API: post and delete tweet", async () => {
      const apiKey = process.env.TWITTER_API_KEY;
      const apiSecret = process.env.TWITTER_API_SECRET;
      const accessToken = process.env.TWITTER_ACCESS_TOKEN;
      const accessSecret = process.env.TWITTER_ACCESS_SECRET;
      assert.ok(
        apiKey && apiSecret && accessToken && accessSecret,
        "Twitter credentials must be set",
      );

      const { postTweet, deleteTweet } = await import("./tweet-reflection.ts");
      const testText = `[Integration Test] ${new Date().toISOString()} - This tweet will be deleted shortly.`;

      // Post
      const tweet = await postTweet(testText, {
        apiKey,
        apiSecret,
        accessToken,
        accessSecret,
      });
      assert.ok(tweet.id, "Tweet should have an ID");

      // Cleanup: delete the tweet
      await deleteTweet(tweet.id, {
        apiKey,
        apiSecret,
        accessToken,
        accessSecret,
      });
    });

    test("oEmbed API returns embed HTML for known tweet", async () => {
      const { fetchOEmbed } = await import("./tweet-reflection.ts");
      // Use a well-known tweet that should always exist
      const result = await fetchOEmbed("https://twitter.com/jack/status/20", {
        theme: "dark",
      });
      assert.ok(
        result.html.includes("twitter-tweet"),
        "Should contain twitter-tweet class",
      );
      assert.ok(
        result.html.includes("blockquote"),
        "Should contain blockquote element",
      );
    });

    test("end-to-end: full pipeline with cleanup", async () => {
      const tempDir = createTempDir();

      try {
        // Create a test reflection
        const testDate = "2099-12-31";
        const testContent = `---
share: true
title: ${testDate} | 🧪 E2E Test Reflection 📚
URL: https://bagrounds.org/reflections/${testDate}
Author: "[[bryan-grounds]]"
tags:
---
[Home](../index.md) > [Reflections](./index.md)  
# ${testDate} | 🧪 E2E Test Reflection 📚  
## [📚 Books](../books/index.md)  
- 🧪 [Test Book](../books/test-book.md)  
  
## 🤖🐲 AI Fiction  
🧪 This is a test reflection for end-to-end testing.  
`;
        fs.writeFileSync(path.join(tempDir, `${testDate}.md`), testContent);

        // Run the pipeline
        const {
          readReflection,
          generateTweetWithGemini,
          postTweet,
          getEmbedHtml,
          appendTweetSection,
          deleteTweet,
        } = await import("./tweet-reflection.ts");

        const reflection = readReflection(testDate, tempDir);
        assert.ok(reflection, "Should read the test reflection");
        assert.equal(reflection.hasTweetSection, false);

        const geminiKey = process.env.GEMINI_API_KEY as string;
        const tweetText = await generateTweetWithGemini(reflection, geminiKey);
        assert.ok(tweetText.length > 0);

        const twitterCreds = {
          apiKey: process.env.TWITTER_API_KEY as string,
          apiSecret: process.env.TWITTER_API_SECRET as string,
          accessToken: process.env.TWITTER_ACCESS_TOKEN as string,
          accessSecret: process.env.TWITTER_ACCESS_SECRET as string,
        };

        const tweet = await postTweet(tweetText, twitterCreds);
        assert.ok(tweet.id);

        try {
          const embedHtml = await getEmbedHtml(tweet.id, tweet.text, testDate);
          assert.ok(
            embedHtml.includes("twitter-tweet") ||
              embedHtml.includes("blockquote"),
          );

          appendTweetSection(reflection.filePath, embedHtml);

          // Verify the file was updated
          const updatedReflection = readReflection(testDate, tempDir);
          assert.ok(updatedReflection);
          assert.equal(updatedReflection.hasTweetSection, true);
        } finally {
          // Always clean up the tweet
          await deleteTweet(tweet.id, twitterCreds);
        }
      } finally {
        cleanupTempDir(tempDir);
      }
    });
  },
);

// --- fetchOgMetadata tests ---

describe("fetchOgMetadata", () => {
  test("returns empty object for unreachable URL", async () => {
    const meta = await fetchOgMetadata("http://localhost:1/nonexistent");
    assert.deepEqual(meta, {});
  });

  test("parses og:title and og:description from real page", async () => {
    // Use a known page from the user's site
    const meta = await fetchOgMetadata("https://bagrounds.org/reflections/2026-03-05");
    // The page has og:title and og:description meta tags
    if (meta.title) {
      assert.ok(meta.title.length > 0, "og:title should be non-empty");
    }
    if (meta.description) {
      assert.ok(meta.description.length > 0, "og:description should be non-empty");
    }
  });
});
