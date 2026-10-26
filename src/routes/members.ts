import { Router } from "express";
import { z } from "zod";
import { pool } from "../db.js";
import { requireRole } from "../middleware/auth.js";

// The board-membership gate in app.ts runs before every route here,
// so res.locals.boardRole is always set.
export const membersRouter = Router({ mergeParams: true });

const columns = `m.id, m.board_id AS "boardId", m.user_id AS "userId",
  m.role, m.joined_at AS "joinedAt"`;

const boardParams = z.object({ boardId: z.uuid() });
const memberParams = z.object({ boardId: z.uuid(), memberId: z.uuid() });

const addMember = z.object({
  userId: z.uuid(),
  role: z.enum(["admin", "member"]).default("member"),
});

const updateMember = z.object({
  role: z.enum(["admin", "member"]),
});

// Owners and admins can add people; only the owner can add admins.
membersRouter.post("/", requireRole("owner", "admin"), async (req, res) => {
  const params = boardParams.safeParse(req.params);
  const body = addMember.safeParse(req.body);
  if (!params.success || !body.success) {
    res.status(400).json({
      error: "Invalid input",
      details: body.success ? undefined : body.error.issues,
    });
    return;
  }
  const { boardId } = params.data;
  const { userId, role } = body.data;

  if (role === "admin" && res.locals.boardRole !== "owner") {
    res.status(403).json({ error: "Only the board owner can add admins" });
    return;
  }

  const user = await pool.query("SELECT 1 FROM users WHERE id = $1", [userId]);
  if (user.rows.length === 0) {
    res.status(404).json({ error: "User not found" });
    return;
  }

  const { rows } = await pool.query(
    `INSERT INTO members AS m (board_id, user_id, role)
     VALUES ($1, $2, $3) RETURNING ${columns}`,
    [boardId, userId, role],
  );
  res.status(201).json(rows[0]);
});

// Any member can see who's on the board.
membersRouter.get("/", async (req, res) => {
  const params = boardParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid board id" });
    return;
  }
  const { rows } = await pool.query(
    `SELECT m.id, m.user_id AS "userId", u.display_name AS "displayName",
            u.email, m.role, m.joined_at AS "joinedAt"
     FROM members m
     JOIN users u ON u.id = m.user_id
     WHERE m.board_id = $1
     ORDER BY m.joined_at`,
    [params.data.boardId],
  );
  res.json(rows);
});

// Only the owner can change roles.
membersRouter.patch("/:memberId", requireRole("owner"), async (req, res) => {
  const params = memberParams.safeParse(req.params);
  const body = updateMember.safeParse(req.body);
  if (!params.success || !body.success) {
    res.status(400).json({
      error: "Invalid input",
      details: body.success ? undefined : body.error.issues,
    });
    return;
  }
  const { boardId, memberId } = params.data;

  const existing = await pool.query(
    "SELECT role FROM members WHERE id = $1 AND board_id = $2",
    [memberId, boardId],
  );
  if (existing.rows.length === 0) {
    res.status(404).json({ error: "Member not found" });
    return;
  }
  if (existing.rows[0].role === "owner") {
    res.status(409).json({ error: "The owner's role can't be changed" });
    return;
  }

  const { rows } = await pool.query(
    `UPDATE members AS m SET role = $3
     WHERE m.id = $1 AND m.board_id = $2
     RETURNING ${columns}`,
    [memberId, boardId, body.data.role],
  );
  res.json(rows[0]);
});

// Owner can remove anyone (except themselves); admins can remove plain
// members; anyone except the owner can remove themselves (leave).
membersRouter.delete("/:memberId", async (req, res) => {
  const params = memberParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid id" });
    return;
  }
  const { boardId, memberId } = params.data;

  const existing = await pool.query(
    `SELECT role, user_id AS "userId" FROM members
     WHERE id = $1 AND board_id = $2`,
    [memberId, boardId],
  );
  if (existing.rows.length === 0) {
    res.status(404).json({ error: "Member not found" });
    return;
  }
  const target = existing.rows[0];
  if (target.role === "owner") {
    res
      .status(409)
      .json({ error: "The owner can't be removed; delete the board instead" });
    return;
  }

  const callerRole = res.locals.boardRole;
  const isSelf = target.userId === res.locals.userId;
  const allowed =
    isSelf ||
    callerRole === "owner" ||
    (callerRole === "admin" && target.role === "member");
  if (!allowed) {
    res.status(403).json({ error: "Your role on this board doesn't allow this" });
    return;
  }

  await pool.query("DELETE FROM members WHERE id = $1 AND board_id = $2", [
    memberId,
    boardId,
  ]);
  res.status(204).end();
});