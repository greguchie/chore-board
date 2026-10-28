# Security

How the chore-board API is protected, mapped to the OWASP Top 10:2025, plus known limitations. This is a portfolio project; please report any issue by opening a GitHub issue.

## Summary of controls

- **Authentication:** email + password (scrypt with a random salt per user). Short-lived access tokens (HS256 JWT, 15 minutes) and long-lived refresh tokens (32 random bytes, stored only as SHA-256 hashes, rotated on every use with reuse detection).
- **Authorization:** every route except sign-up, login, refresh, logout and health requires a bearer token. Board data requires membership; actions are limited by role (owner / admin / member).
- **Input:** zod schemas validate every body, path and query parameter; unknown fields are dropped; JSON bodies are capped at 10 KB.
- **Abuse:** per-IP rate limits on failed logins, sign-ups and overall traffic.
- **Headers:** helmet adds a content-security policy, HSTS, clickjacking and MIME-sniffing protection, and removes `X-Powered-By`.
- **Secrets:** loaded from environment variables and validated at startup; `.env` is git-ignored.

## OWASP Top 10:2025 mapping

| Risk | How this API addresses it | Where |
|---|---|---|
| A01 Broken Access Control | `requireAuth` on all private routes; non-members get 404; `requireRole` enforces owner/admin/member permissions; board queries filter by the caller in SQL; users can only read or change their own account; board owner comes from the token, never the request body. The server makes no outbound requests, so SSRF does not apply. | `src/middleware/auth.ts`, `src/routes/` |
| A02 Security Misconfiguration | helmet headers; config validated at startup (the app refuses to start with a weak secret); JSON-only errors and 404s; API docs not served when `NODE_ENV=production`. | `src/app.ts`, `src/config.ts` |
| A03 Software Supply Chain Failures | `package-lock.json` committed; `npm run audit:prod` checks shipped dependencies; small dependency set. Dev-only tooling is audited separately. | `package.json` |
| A04 Cryptographic Failures | scrypt with a 16-byte random salt; constant-time comparison; refresh tokens stored only as SHA-256 hashes; JWT secret of at least 32 characters from the environment; HSTS for HTTPS. | `src/password.ts`, `src/tokens.ts` |
| A05 Injection | All SQL uses parameter placeholders (`$1`, `$2`, ...). The one dynamic `UPDATE` builds column names only from a fixed allow-list. The API returns JSON only, no HTML. | `src/routes/` |
| A06 Insecure Design | Role permissions designed up front; short-lived access tokens with revocable refresh tokens; token families for theft detection; identical login errors for unknown email and wrong password. | `src/routes/auth.ts` |
| A07 Authentication Failures | Failed-login rate limit (5 per 15 minutes per IP); equal timing for unknown and known emails; password length 8 to 128; refresh rotation with whole-session revocation on reuse; logout revokes the session. | `src/routes/auth.ts`, `src/middleware/rateLimit.ts` |
| A08 Software or Data Integrity Failures | JWTs verified with a pinned algorithm (HS256), issuer and audience; refresh rotation runs in a locked database transaction; lockfile integrity hashes. | `src/tokens.ts`, `src/routes/auth.ts` |
| A09 Logging & Alerting Failures | Warnings logged for refresh-token reuse and for login rate-limit blocks; unexpected errors logged server-side only. | `src/routes/auth.ts`, `src/middleware/rateLimit.ts` |
| A10 Mishandling of Exceptional Conditions | Central error handler maps known errors to 4xx and everything else to a generic 500 with no internal detail; transactions roll back and always release their connection; database pool errors are caught instead of crashing the server; misconfiguration fails fast at startup. | `src/app.ts`, `src/db.ts`, `src/config.ts` |

## Known limitations and planned work

- **Rate limits** are per IP and held in memory: they reset on restart and aren't shared between servers. Planned: a Redis store.
- **Logging** is plain console output. Planned: structured logging and monitoring.
- **Sign-up** returns 409 when an email is already registered, which reveals that the account exists. Accepted for usability; mitigated by the sign-up rate limit.
- **Missing account features:** password change and reset, multi-factor authentication, breached-password checks.
- **Stateless access tokens** stay valid for up to 15 minutes after logout or account deletion. This is the standard JWT trade-off and the reason they are short-lived.
- **Password hashes** use Node's default scrypt cost and don't record their parameters, so raising the cost later requires re-hashing at the next login. Planned: a versioned hash format or Argon2id.
- **Sign in with Apple** is planned once an Apple Developer account is available.
- **Behind a reverse proxy**, Express's `trust proxy` setting must be configured so rate limits see the client's real IP address.

## Verifying

- `npm run audit:prod`: vulnerability check on shipped dependencies
- `npm run test:api`: end-to-end API tests (Postman / Newman)