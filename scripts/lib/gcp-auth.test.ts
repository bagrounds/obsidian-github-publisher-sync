/**
 * Tests for scripts/lib/gcp-auth.ts — GCP service account authentication.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { parseServiceAccountKey, createJwt } from "./gcp-auth.ts";

// ---------------------------------------------------------------------------
// parseServiceAccountKey
// ---------------------------------------------------------------------------

describe("parseServiceAccountKey", () => {
  const validKey = JSON.stringify({
    project_id: "my-project",
    client_email: "test@my-project.iam.gserviceaccount.com",
    private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----\n",
  });

  it("parses valid service account JSON", () => {
    const result = parseServiceAccountKey(validKey);
    assert.equal(result.project_id, "my-project");
    assert.equal(result.client_email, "test@my-project.iam.gserviceaccount.com");
    assert.ok(result.private_key.includes("BEGIN RSA PRIVATE KEY"));
  });

  it("throws on missing project_id", () => {
    const key = JSON.stringify({
      client_email: "test@example.com",
      private_key: "key",
    });
    assert.throws(() => parseServiceAccountKey(key), /project_id/);
  });

  it("throws on missing client_email", () => {
    const key = JSON.stringify({
      project_id: "proj",
      private_key: "key",
    });
    assert.throws(() => parseServiceAccountKey(key), /client_email/);
  });

  it("throws on missing private_key", () => {
    const key = JSON.stringify({
      project_id: "proj",
      client_email: "test@example.com",
    });
    assert.throws(() => parseServiceAccountKey(key), /private_key/);
  });

  it("throws on invalid JSON", () => {
    assert.throws(() => parseServiceAccountKey("not json"), /Unexpected token/);
  });
});

// ---------------------------------------------------------------------------
// createJwt
// ---------------------------------------------------------------------------

describe("createJwt", () => {
  it("produces a three-part dot-separated token", async () => {
    // Generate a real RSA key pair for testing
    const { generateKeyPairSync } = await import("node:crypto");
    const { privateKey } = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });

    const jwt = createJwt(
      {
        iss: "test@example.com",
        scope: "https://www.googleapis.com/auth/cloud-platform",
        aud: "https://oauth2.googleapis.com/token",
        iat: 1000,
        exp: 4600,
      },
      privateKey,
    );

    const parts = jwt.split(".");
    assert.equal(parts.length, 3);
  });

  it("encodes correct header", async () => {
    const { generateKeyPairSync } = await import("node:crypto");
    const { privateKey } = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });

    const jwt = createJwt(
      {
        iss: "test@example.com",
        scope: "scope",
        aud: "aud",
        iat: 0,
        exp: 1,
      },
      privateKey,
    );

    const header = JSON.parse(
      Buffer.from(jwt.split(".")[0] as string, "base64url").toString(),
    );
    assert.equal(header.alg, "RS256");
    assert.equal(header.typ, "JWT");
  });

  it("encodes claims in payload", async () => {
    const { generateKeyPairSync } = await import("node:crypto");
    const { privateKey } = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });

    const claims = {
      iss: "sa@proj.iam.gserviceaccount.com",
      scope: "https://www.googleapis.com/auth/cloud-platform",
      aud: "https://oauth2.googleapis.com/token",
      iat: 1710000000,
      exp: 1710003600,
    };

    const jwt = createJwt(claims, privateKey);
    const payload = JSON.parse(
      Buffer.from(jwt.split(".")[1] as string, "base64url").toString(),
    );
    assert.equal(payload.iss, claims.iss);
    assert.equal(payload.scope, claims.scope);
    assert.equal(payload.aud, claims.aud);
    assert.equal(payload.iat, claims.iat);
    assert.equal(payload.exp, claims.exp);
  });
});
