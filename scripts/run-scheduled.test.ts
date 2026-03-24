import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

import { parseArgs, parseGitHubOutputs } from "./run-scheduled.ts";

// ---------------------------------------------------------------------------
// parseArgs
// ---------------------------------------------------------------------------

describe("parseArgs", () => {
  it("returns undefined overrides with no flags", () => {
    const result = parseArgs(["node", "run-scheduled.ts"]);
    assert.equal(result.hourOverride, undefined);
    assert.equal(result.taskOverride, undefined);
  });

  it("parses --hour flag", () => {
    const result = parseArgs(["node", "run-scheduled.ts", "--hour", "15"]);
    assert.equal(result.hourOverride, 15);
    assert.equal(result.taskOverride, undefined);
  });

  it("parses --task flag", () => {
    const result = parseArgs([
      "node",
      "run-scheduled.ts",
      "--task",
      "social-posting",
    ]);
    assert.equal(result.hourOverride, undefined);
    assert.equal(result.taskOverride, "social-posting");
  });

  it("parses both flags together", () => {
    const result = parseArgs([
      "node",
      "run-scheduled.ts",
      "--task",
      "internal-linking",
      "--hour",
      "8",
    ]);
    assert.equal(result.hourOverride, 8);
    assert.equal(result.taskOverride, "internal-linking");
  });

  it("handles --hour 0 correctly", () => {
    const result = parseArgs(["node", "run-scheduled.ts", "--hour", "0"]);
    assert.equal(result.hourOverride, 0);
  });

  it("returns NaN for non-numeric --hour", () => {
    const result = parseArgs(["node", "run-scheduled.ts", "--hour", "abc"]);
    assert.ok(Number.isNaN(result.hourOverride));
  });
});

// ---------------------------------------------------------------------------
// parseGitHubOutputs
// ---------------------------------------------------------------------------

describe("parseGitHubOutputs", () => {
  it("parses key=value pairs from file", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "gh-output-"));
    const tmpFile = path.join(tmpDir, "output");
    try {
      fs.writeFileSync(tmpFile, "post=chickie-loo/2026-03-24-test.md\n");
      const result = parseGitHubOutputs(tmpFile);
      assert.equal(result.post, "chickie-loo/2026-03-24-test.md");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("parses multiple outputs", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "gh-output-"));
    const tmpFile = path.join(tmpDir, "output");
    try {
      fs.writeFileSync(tmpFile, "post=path/to/post.md\nvault_dir=/tmp/vault\n");
      const result = parseGitHubOutputs(tmpFile);
      assert.equal(result.post, "path/to/post.md");
      assert.equal(result.vault_dir, "/tmp/vault");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("handles values containing equals signs", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "gh-output-"));
    const tmpFile = path.join(tmpDir, "output");
    try {
      fs.writeFileSync(tmpFile, "key=value=with=equals\n");
      const result = parseGitHubOutputs(tmpFile);
      assert.equal(result.key, "value=with=equals");
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns empty object for empty file", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "gh-output-"));
    const tmpFile = path.join(tmpDir, "output");
    try {
      fs.writeFileSync(tmpFile, "");
      const result = parseGitHubOutputs(tmpFile);
      assert.deepStrictEqual(result, {});
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });

  it("returns empty object for non-existent file", () => {
    const result = parseGitHubOutputs("/tmp/nonexistent-output-file");
    assert.deepStrictEqual(result, {});
  });

  it("skips blank lines", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "gh-output-"));
    const tmpFile = path.join(tmpDir, "output");
    try {
      fs.writeFileSync(tmpFile, "key=value\n\n\n");
      const result = parseGitHubOutputs(tmpFile);
      assert.deepStrictEqual(result, { key: "value" });
    } finally {
      fs.rmSync(tmpDir, { recursive: true });
    }
  });
});
