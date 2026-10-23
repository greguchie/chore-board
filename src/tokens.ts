import { createHash, randomBytes } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import { config } from "./config.js";

const accessKey = new TextEncoder().encode(config.JWT_ACCESS_SECRET);
const ISSUER = "chore-board-api";
const AUDIENCE = "chore-board-app";

// Short-lived JWT proving who the caller is. "sub" (subject) = user id.
export async function signAccessToken(userId: string): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuer(ISSUER)
    .setAudience(AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(config.ACCESS_TOKEN_TTL)
    .sign(accessKey);
}

// Throws if the token is forged, expired, or meant for another app.
export async function verifyAccessToken(token: string): Promise<string> {
  const { payload } = await jwtVerify(token, accessKey, {
    issuer: ISSUER,
    audience: AUDIENCE,
    algorithms: ["HS256"],
  });
  if (!payload.sub) {
    throw new Error("Token has no subject");
  }
  return payload.sub;
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

// Random, unguessable refresh token. Only the hash is ever stored.
export function createRefreshToken(): { token: string; tokenHash: string } {
  const token = randomBytes(32).toString("base64url");
  return { token, tokenHash: hashToken(token) };
}