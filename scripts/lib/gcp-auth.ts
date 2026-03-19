/**
 * Google Cloud Platform authentication via service account JWT.
 *
 * Creates short-lived OAuth2 access tokens from a service account JSON key
 * using Node.js built-in crypto — zero external dependencies.
 *
 * @module gcp-auth
 */

import crypto from "node:crypto";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ServiceAccountKey {
  readonly project_id: string;
  readonly client_email: string;
  readonly private_key: string;
}

interface JwtClaims {
  readonly iss: string;
  readonly scope: string;
  readonly aud: string;
  readonly iat: number;
  readonly exp: number;
}

interface TokenResponse {
  readonly access_token: string;
  readonly token_type: string;
  readonly expires_in: number;
}

// ---------------------------------------------------------------------------
// JWT creation
// ---------------------------------------------------------------------------

const base64url = (data: string | Buffer): string =>
  Buffer.from(data).toString("base64url");

export const createJwt = (claims: JwtClaims, privateKey: string): string => {
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify(claims));
  const signingInput = `${header}.${payload}`;

  const signer = crypto.createSign("RSA-SHA256");
  signer.update(signingInput);
  const signature = signer.sign(privateKey, "base64url");

  return `${signingInput}.${signature}`;
};

// ---------------------------------------------------------------------------
// Service account parsing
// ---------------------------------------------------------------------------

export const parseServiceAccountKey = (raw: string): ServiceAccountKey => {
  const parsed = JSON.parse(raw) as Record<string, unknown>;
  const project_id = String(parsed.project_id ?? "");
  const client_email = String(parsed.client_email ?? "");
  const private_key = String(parsed.private_key ?? "");

  if (!project_id || !client_email || !private_key) {
    throw new Error(
      "Service account key must contain project_id, client_email, and private_key",
    );
  }

  return { project_id, client_email, private_key };
};

// ---------------------------------------------------------------------------
// Token exchange
// ---------------------------------------------------------------------------

const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const TOKEN_LIFETIME_SECONDS = 3600;
const CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform";

export const getAccessToken = async (
  serviceAccount: ServiceAccountKey,
): Promise<string> => {
  const now = Math.floor(Date.now() / 1000);
  const claims: JwtClaims = {
    iss: serviceAccount.client_email,
    scope: CLOUD_PLATFORM_SCOPE,
    aud: TOKEN_ENDPOINT,
    iat: now,
    exp: now + TOKEN_LIFETIME_SECONDS,
  };

  const jwt = createJwt(claims, serviceAccount.private_key);

  const response = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Token exchange failed (${response.status}): ${body}`);
  }

  const data = (await response.json()) as TokenResponse;
  return data.access_token;
};
