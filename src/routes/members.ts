import { Router } from "express";
import { z } from "zod";
import { pool } from "../db.js";

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

membersRouter.post("/", async (req, res) => {
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

  const board = await pool.query("SELECT 1 FROM boards WHERE id = $1", [boardId]);
  if (board.rows.length === 0) {
    res.status(404).json({ error: "Board not found" });
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

membersRouter.get("/", async (req, res) => {
  const params = boardParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid board id" });
    return;
  }
  const board = await pool.query("SELECT 1 FROM boards WHERE id = $1", [
    params.data.boardId,
  ]);
  if (board.rows.length === 0) {
    res.status(404).json({ error: "Board not found" });
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

membersRouter.patch("/:memberId", async (req, res) => {
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

membersRouter.delete("/:memberId", async (req, res) => {
  const params = memberParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid id" });
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
    res.status(409).json({ error: "The owner can't be removed; delete the board instead" });
    return;
  }

  await pool.query("DELETE FROM members WHERE id = $1 AND board_id = $2", [
    memberId,
    boardId,
  ]);
  res.status(204).end();
});
