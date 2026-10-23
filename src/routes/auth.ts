import { randomUUID } from "node:crypto";
import { Router } from "express";
import { z } from "zod";
import { config } from "../config.js";
import { pool } from "../db.js";
import { hashPassword, verifyPassword } from "../password.js";
import { createRefreshToken, signAccessToken } from "../tokens.js";

export const authRouter = Router();

const loginBody = z.object({
  email: z.email(),
  password: z.string().min(1).max(128),
});

// Checked when the email doesn't exist, so that case takes as long
// as a wrong password and attackers can't tell which emails are real.
const dummyHash = hashPassword(randomUUID());

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
  await pool.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
     VALUES ($1, $2, $3, now() + $4::int * interval '1 day')`,
    [user.id, refresh.tokenHash, randomUUID(), config.REFRESH_TOKEN_TTL_DAYS],
  );

  res.json({
    accessToken,
    refreshToken: refresh.token,
    tokenType: "Bearer",
    accessTokenExpiresIn: config.ACCESS_TOKEN_TTL,
    user: { id: user.id, email: user.email, displayName: user.displayName },
  });
});