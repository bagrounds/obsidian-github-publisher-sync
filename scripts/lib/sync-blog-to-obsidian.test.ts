import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import { copyFileToVault, resolveLocalPath, parseArgs } from "../sync-file-to-obsidian.ts";

describe("copyFileToVault", () => {
  it("copies a file to the vault", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      const srcFile = path.join(tmpDir, "test.md");
      fs.writeFileSync(srcFile, "# Hello World\n");

      assert.ok(copyFileToVault(srcFile, "blog/test.md", vaultDir));
      assert.equal(fs.readFileSync(path.join(vaultDir, "blog/test.md"), "utf-8"), "# Hello World\n");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });

  it("returns false when content is identical", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      fs.writeFileSync(path.join(tmpDir, "test.md"), "same");
      fs.mkdirSync(path.join(vaultDir, "blog"), { recursive: true });
      fs.writeFileSync(path.join(vaultDir, "blog/test.md"), "same");

      assert.equal(copyFileToVault(path.join(tmpDir, "test.md"), "blog/test.md", vaultDir), false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
      fs.rmSync(vaultDir, { recursive: true });
    }
  });

  it("returns false for non-existent local file", () => {
    const vaultDir = fs.mkdtempSync(path.join(os.tmpdir(), "vault-test-"));
    try {
      assert.equal(copyFileToVault("/tmp/nonexistent.md", "test.md", vaultDir), false);
    } finally {
      fs.rmSync(vaultDir, { recursive: true });
    }
  });
});

describe("resolveLocalPath", () => {
  it("returns absolute path unchanged", () => {
    assert.equal(resolveLocalPath("/abs/path.md", "/repo"), "/abs/path.md");
  });

  it("resolves relative path against repo root", () => {
    assert.equal(resolveLocalPath("blog/post.md", "/repo"), "/repo/blog/post.md");
  });
});

describe("parseArgs", () => {
  it("returns help for --help", () => {
    assert.equal(parseArgs(["node", "script", "--help"]), "help");
  });

  it("returns help for no args", () => {
    assert.equal(parseArgs(["node", "script"]), "help");
  });

  it("parses positional args", () => {
    const result = parseArgs(["node", "script", "local.md", "vault.md"]);
    assert.notEqual(result, "help");
    if (result !== "help") {
      assert.equal(result.localPath, "local.md");
      assert.equal(result.vaultPath, "vault.md");
      assert.equal(result.dryRun, false);
    }
  });

  it("parses --dry-run flag", () => {
    const result = parseArgs(["node", "script", "a.md", "b.md", "--dry-run"]);
    assert.notEqual(result, "help");
    if (result !== "help") {
      assert.equal(result.dryRun, true);
    }
  });
});
