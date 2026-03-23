import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import { syncFileToVault, readPreviousPostFilename } from "./sync-series-to-vault.ts";

describe("readPreviousPostFilename", () => {
  it("returns undefined when metadata file does not exist", () => {
    assert.equal(readPreviousPostFilename("/tmp/nonexistent-metadata.json"), undefined);
  });

  it("reads previousPostFilename from metadata JSON", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    try {
      const metaPath = path.join(tmpDir, ".last-generate-metadata.json");
      fs.writeFileSync(metaPath, JSON.stringify({
        previousPostFilename: "2026-03-22-previous-post.md",
        newPostFilename: "2026-03-23-new-post.md",
      }));
      assert.equal(readPreviousPostFilename(metaPath), "2026-03-22-previous-post.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns undefined when previousPostFilename is missing from JSON", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    try {
      const metaPath = path.join(tmpDir, ".last-generate-metadata.json");
      fs.writeFileSync(metaPath, JSON.stringify({ newPostFilename: "post.md" }));
      assert.equal(readPreviousPostFilename(metaPath), undefined);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});

describe("syncFileToVault", () => {
  it("copies file to vault when destination does not exist", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    try {
      const localPath = path.join(tmpDir, "local.md");
      const vaultDir = path.join(tmpDir, "vault");
      fs.writeFileSync(localPath, "# Hello\n\nContent here.");
      fs.mkdirSync(vaultDir);

      const result = syncFileToVault(localPath, "series/post.md", vaultDir);
      assert.equal(result, true);
      assert.equal(fs.readFileSync(path.join(vaultDir, "series/post.md"), "utf-8"), "# Hello\n\nContent here.");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns false when file is already in sync", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    try {
      const content = "# Same Content";
      const localPath = path.join(tmpDir, "local.md");
      const vaultDir = path.join(tmpDir, "vault");
      fs.writeFileSync(localPath, content);
      fs.mkdirSync(path.join(vaultDir, "series"), { recursive: true });
      fs.writeFileSync(path.join(vaultDir, "series/post.md"), content);

      const result = syncFileToVault(localPath, "series/post.md", vaultDir);
      assert.equal(result, false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns false when local file does not exist", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    try {
      const result = syncFileToVault(path.join(tmpDir, "nonexistent.md"), "post.md", tmpDir);
      assert.equal(result, false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("overwrites when vault content differs", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-test-"));
    try {
      const localPath = path.join(tmpDir, "local.md");
      const vaultDir = path.join(tmpDir, "vault");
      fs.writeFileSync(localPath, "# Updated");
      fs.mkdirSync(path.join(vaultDir, "series"), { recursive: true });
      fs.writeFileSync(path.join(vaultDir, "series/post.md"), "# Old");

      const result = syncFileToVault(localPath, "series/post.md", vaultDir);
      assert.equal(result, true);
      assert.equal(fs.readFileSync(path.join(vaultDir, "series/post.md"), "utf-8"), "# Updated");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});
