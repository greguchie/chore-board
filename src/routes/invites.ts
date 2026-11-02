import { randomBytes } from "node:crypto";
import { Router } from "express";
import { z } from "zod";
import { pool } from "../db.js";
import { requireRole } from "../middleware/auth.js";
import { hashToken } from "../tokens.js";

const INVITE_TTL_DAYS = 7;
const APP_SCHEME = "choreboard";

const boardParams = z.object({ boardId: z.uuid() });
const createInvite = z.object({
  role: z.enum(["admin", "member"]).default("member"),
});
const acceptInvite = z.object({
  token: z.string().min(1).max(200),
});

// Mounted at /boards/:boardId/invites behind requireAuth + requireBoardMember,
// so res.locals.boardRole is always set here.
export const boardInvitesRouter = Router({ mergeParams: true });

// Owners and admins create links; only the owner can create admin links.
boardInvitesRouter.post("/", requireRole("owner", "admin"), async (req, res) => {
  const params = boardParams.safeParse(req.params);
  const body = createInvite.safeParse(req.body ?? {});
  if (!params.success || !body.success) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }
  if (body.data.role === "admin" && res.locals.boardRole !== "owner") {
    res.status(403).json({ error: "Only the board owner can invite admins" });
    return;
  }

  // Same format as refresh tokens: 32 random bytes, only the hash is stored.
  const token = randomBytes(32).toString("base64url");
  const { rows } = await pool.query(
    `INSERT INTO invites (board_id, token_hash, role, created_by, expires_at)
     VALUES ($1, $2, $3, $4, now() + $5::int * interval '1 day')
     RETURNING board_id AS "boardId", role, expires_at AS "expiresAt"`,
    [params.data.boardId, hashToken(token), body.data.role, res.locals.userId, INVITE_TTL_DAYS],
  );

  // The plain token is returned once, here, and never stored.
  res.status(201).json({ ...rows[0], token, url: `${APP_SCHEME}://invite/${token}` });
});

// Mounted at /invites behind requireAuth.
export const invitesRouter = Router();

// The token travels in the body, not the URL, so it stays out of access logs.
invitesRouter.post("/accept", async (req, res) => {
  const body = acceptInvite.safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }
  const userId: string = res.locals.userId;

  const invite = await pool.query(
    `SELECT board_id AS "boardId", role FROM invites
     WHERE token_hash = $1 AND expires_at > now()`,
    [hashToken(body.data.token)],
  );
  if (invite.rows.length === 0) {
    res.status(404).json({ error: "This invite link is invalid or has expired" });
    return;
  }
  const { boardId, role } = invite.rows[0];

  // Idempotent: if you're already a member, your role stays as it is.
  await pool.query(
    `INSERT INTO members (board_id, user_id, role) VALUES ($1, $2, $3)
     ON CONFLICT (board_id, user_id) DO NOTHING`,
    [boardId, userId, role],
  );

  // Same shape as GET /boards/:id, so the app can open the board right away.
  const { rows } = await pool.query(
    `SELECT b.id, b.name, b.description, b.owner_id AS "ownerId",
            b.created_at AS "createdAt", b.updated_at AS "updatedAt", m.role AS "myRole"
     FROM boards b
     JOIN members m ON m.board_id = b.id AND m.user_id = $2
     WHERE b.id = $1`,
    [boardId, userId],
  );
  res.json(rows[0]);
});