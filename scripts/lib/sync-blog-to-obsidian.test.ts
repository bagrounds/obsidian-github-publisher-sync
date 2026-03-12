/**
 * Tests for scripts/sync-blog-to-obsidian.ts — File copy and series sync.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import { copyFileToVault, syncSeries } from "../sync-blog-to-obsidian.ts";
import { BLOG_SERIES } from "./blog-series.ts";

// --- copyFileToVault ---

describe("copyFileToVault", () => {
  it("copies a file to the vault", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const srcFile = path.join(tmpDir, "test.md");
      fs.writeFileSync(srcFile, "# Hello World\n");

      const written = copyFileToVault(srcFile, "blog/test.md", vaultDir);
      assert.ok(written);
      assert.ok(fs.existsSync(path.join(vaultDir, "blog/test.md")));
      assert.equal(fs.readFileSync(path.join(vaultDir, "blog/test.md"), "utf-8"), "# Hello World\n");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });

  it("creates parent directories", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const srcFile = path.join(tmpDir, "test.md");
      fs.writeFileSync(srcFile, "content");

      copyFileToVault(srcFile, "deep/nested/dir/test.md", vaultDir);
      assert.ok(fs.existsSync(path.join(vaultDir, "deep/nested/dir/test.md")));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });

  it("returns false when content is identical", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const srcFile = path.join(tmpDir, "test.md");
      fs.writeFileSync(srcFile, "same content");

      const destDir = path.join(vaultDir, "blog");
      fs.mkdirSync(destDir, { recursive: true });
      fs.writeFileSync(path.join(destDir, "test.md"), "same content");

      const written = copyFileToVault(srcFile, "blog/test.md", vaultDir);
      assert.equal(written, false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });

  it("returns true when content differs", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const srcFile = path.join(tmpDir, "test.md");
      fs.writeFileSync(srcFile, "new content");

      const destDir = path.join(vaultDir, "blog");
      fs.mkdirSync(destDir, { recursive: true });
      fs.writeFileSync(path.join(destDir, "test.md"), "old content");

      const written = copyFileToVault(srcFile, "blog/test.md", vaultDir);
      assert.ok(written);
      assert.equal(fs.readFileSync(path.join(vaultDir, "blog/test.md"), "utf-8"), "new content");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });

  it("returns false for non-existent local file", () => {
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const written = copyFileToVault("/tmp/does-not-exist.md", "test.md", vaultDir);
      assert.equal(written, false);
    } finally {
      fs.rmSync(vaultDir, { recursive: true });
    }
  });
});

// --- syncSeries ---

describe("syncSeries", () => {
  it("returns 0 for non-existent series directory", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const series = BLOG_SERIES.get("auto-blog-zero")!;
      const count = syncSeries(series, tmpDir, vaultDir);
      assert.equal(count, 0);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });

  it("syncs posts and generates index", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const seriesDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(seriesDir);
      fs.writeFileSync(
        path.join(seriesDir, "2026-03-12-test.md"),
        "---\ntitle: Test Post\n---\n# Test\n\nBody text",
      );

      const series = BLOG_SERIES.get("auto-blog-zero")!;
      const count = syncSeries(series, tmpDir, vaultDir);

      // 1 post + 1 index = 2 files
      assert.equal(count, 2);

      // Check post exists
      const postPath = path.join(vaultDir, "auto-blog-zero/2026-03-12-test.md");
      assert.ok(fs.existsSync(postPath));

      // Check index exists and contains dataview query
      const indexPath = path.join(vaultDir, "auto-blog-zero/index.md");
      assert.ok(fs.existsSync(indexPath));
      const indexContent = fs.readFileSync(indexPath, "utf-8");
      assert.ok(indexContent.includes("```dataview"));
      assert.ok(indexContent.includes("auto-blog-zero"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });

  it("skips unchanged files on re-sync", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const seriesDir = path.join(tmpDir, "auto-blog-zero");
      fs.mkdirSync(seriesDir);
      fs.writeFileSync(
        path.join(seriesDir, "2026-03-12-test.md"),
        "---\ntitle: Test Post\n---\n# Test\n\nBody",
      );

      const series = BLOG_SERIES.get("auto-blog-zero")!;

      // First sync
      const firstCount = syncSeries(series, tmpDir, vaultDir);
      assert.equal(firstCount, 2); // post + index

      // Second sync — nothing changed
      const secondCount = syncSeries(series, tmpDir, vaultDir);
      assert.equal(secondCount, 0);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });
});
