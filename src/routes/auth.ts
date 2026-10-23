import { randomUUID } from "node:crypto";
import { Router } from "express";
import { z } from "zod";
import { config } from "../config.js";
import { pool } from "../db.js";
import { hashPassword, verifyPassword } from "../password.js";
import { createRefreshToken, hashToken, signAccessToken } from "../tokens.js";

export const authRouter = Router();

const loginBody = z.object({
  email: z.email(),
  password: z.string().min(1).max(128),
});

const refreshBody = z.object({
  refreshToken: z.string().min(1).max(200),
});

// Checked when the email doesn't exist, so that case takes as long
// as a wrong password and attackers can't tell which emails are real.
const dummyHash = hashPassword(randomUUID());

const insertRefreshToken = `
  INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
  VALUES ($1, $2, $3, now() + $4::int * interval '1 day')
  RETURNING id`;

authRouter.post("/login", async (req, res) => {
  const parsed = loginBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }
  const { email, password } = parsed.data;

  const { rows } = await pool.query(
    `SELECT id, email, display_name AS "displayName",
            password_hash AS "passwordHash"
     FROM users WHERE email = $1`,
    [email.toLowerCase()],
  );
  const user = rows[0];

  const valid = await verifyPassword(
    password,
    user?.passwordHash ?? (await dummyHash),
  );
  if (!user || !valid) {
    res.status(401).json({ error: "Invalid email or password" });
    return;
  }

  const accessToken = await signAccessToken(user.id);
  const refresh = createRefreshToken();
  // Each login starts a new token family (one family = one session).
  await pool.query(insertRefreshToken, [
    user.id,
    refresh.tokenHash,
    randomUUID(),
    config.REFRESH_TOKEN_TTL_DAYS,
  ]);

  res.json({
    accessToken,
    refreshToken: refresh.token,
    tokenType: "Bearer",
    accessTokenExpiresIn: config.ACCESS_TOKEN_TTL,
    user: { id: user.id, email: user.email, displayName: user.displayName },
  });
});

authRouter.post("/refresh", async (req, res) => {
  const parsed = refreshBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    // FOR UPDATE locks this row so two simultaneous refreshes can't both win.
    const { rows } = await client.query(
      `SELECT id, user_id AS "userId", family_id AS "familyId",
                revoked_at AS "revokedAt", replaced_by AS "replacedBy",
                expires_at <= now() AS "expired"
                revoked_at AS "revokedAt", expires_at <= now() AS "expired"
       FROM refresh_tokens
       WHERE token_hash = $1
       FOR UPDATE`,
      [hashToken(parsed.data.refreshToken)],
    );
    const current = rows[0];

    if (!current) {
      await client.query("ROLLBACK");
      res.status(401).json({ error: "Invalid refresh token" });
      return;
    }

    if (current.revokedAt && current.replacedBy) {
      // A rotated token came back: assume it was stolen and end the whole session.
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = now()
         WHERE family_id = $1 AND revoked_at IS NULL`,
        [current.familyId],
      );
      await client.query("COMMIT");
      console.warn(
        `Refresh token reuse detected for user ${current.userId}; session revoked`,
      );
      res.status(401).json({ error: "Invalid refresh token" });
      return;
    }

    if (current.revokedAt || current.expired) {
      // Logged out, already killed, or expired: quiet 401, no alarm.
      await client.query("ROLLBACK");
      res.status(401).json({ error: "Invalid refresh token" });
      return;
    }

    // Rotate: issue a new token in the same family, retire the old one.
    const next = createRefreshToken();
    const inserted = await client.query(insertRefreshToken, [
      current.userId,
      next.tokenHash,
      current.familyId,
      config.REFRESH_TOKEN_TTL_DAYS,
    ]);
    await client.query(
      `UPDATE refresh_tokens SET revoked_at = now(), replaced_by = $2
       WHERE id = $1`,
      [current.id, inserted.rows[0].id],
    );
    await client.query("COMMIT");

    const accessToken = await signAccessToken(current.userId);
    res.json({
      accessToken,
      refreshToken: next.token,
      tokenType: "Bearer",
      accessTokenExpiresIn: config.ACCESS_TOKEN_TTL,
    });
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
});

authRouter.post("/logout", async (req, res) => {
  const parsed = refreshBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }
  // Revoke every token in this session. Always 204 so the response
  // never reveals whether the token was valid.
  await pool.query(
    `UPDATE refresh_tokens SET revoked_at = now()
     WHERE revoked_at IS NULL
       AND family_id = (SELECT family_id FROM refresh_tokens WHERE token_hash = $1)`,
    [hashToken(parsed.data.refreshToken)],
  );
  res.status(204).end();
});