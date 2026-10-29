import { Router } from "express";
import { z } from "zod";
import { pool } from "../db.js";

export const boardsRouter = Router();

const columns = `b.id, b.name, b.description, b.owner_id AS "ownerId",
  b.created_at AS "createdAt", b.updated_at AS "updatedAt"`;

const idParams = z.object({ id: z.uuid() });

const createBoard = z.object({
  name: z.string().trim().min(1).max(100),
  description: z.string().trim().max(500).optional(),
});

const updateBoard = z
  .object({
    name: z.string().trim().min(1).max(100).optional(),
    description: z.string().trim().max(500).optional(),
  })
  .refine((data) => Object.keys(data).length > 0, {
    message: "Provide at least one field to update",
  });

const forbidden = { error: "Your role on this board doesn't allow this" };

// The caller's role on a board, or null if they're not a member.
async function getRole(boardId: string, userId: string): Promise<string | null> {
  const { rows } = await pool.query(
    "SELECT role FROM members WHERE board_id = $1 AND user_id = $2",
    [boardId, userId],
  );
  return rows[0]?.role ?? null;
}

// The logged-in user becomes the owner. No ownerId in the body.
boardsRouter.post("/", async (req, res) => {
  const parsed = createBoard.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid input", details: parsed.error.issues });
    return;
  }
  const { name, description } = parsed.data;
  const ownerId: string = res.locals.userId;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const { rows } = await client.query(
      `INSERT INTO boards AS b (name, description, owner_id)
       VALUES ($1, $2, $3) RETURNING ${columns}`,
      [name, description ?? null, ownerId],
    );
    await client.query(
      `INSERT INTO members (board_id, user_id, role) VALUES ($1, $2, 'owner')`,
      [rows[0].id, ownerId],
    );
    await client.query("COMMIT");
    res.status(201).json({ ...rows[0], myRole: "owner" });
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
});

// Only boards you belong to, with your role on each.
boardsRouter.get("/", async (_req, res) => {
  const { rows } = await pool.query(
    `SELECT ${columns}, m.role AS "myRole"
     FROM boards b
     JOIN members m ON m.board_id = b.id
     WHERE m.user_id = $1
     ORDER BY b.created_at`,
    [res.locals.userId],
  );
  res.json(rows);
});

// Any member can view.
boardsRouter.get("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid board id" });
    return;
  }
  const { rows } = await pool.query(
    `SELECT ${columns}, m.role AS "myRole"
     FROM boards b
     JOIN members m ON m.board_id = b.id AND m.user_id = $2
     WHERE b.id = $1`,
    [params.data.id, res.locals.userId],
  );
  if (rows.length === 0) {
    res.status(404).json({ error: "Board not found" });
    return;
  }
  res.json(rows[0]);
});

// Owner or admin can edit.
boardsRouter.patch("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  const body = updateBoard.safeParse(req.body);
  if (!params.success || !body.success) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }
  const role = await getRole(params.data.id, res.locals.userId);
  if (!role) {
    res.status(404).json({ error: "Board not found" });
    return;
  }
  if (role !== "owner" && role !== "admin") {
    res.status(403).json(forbidden);
    return;
  }
  const { name, description } = body.data;
  const { rows } = await pool.query(
    `UPDATE boards AS b
     SET name = COALESCE($2, b.name),
         description = COALESCE($3, b.description),
         updated_at = now()
     WHERE b.id = $1
     RETURNING ${columns}`,
    [params.data.id, name ?? null, description ?? null],
  );
  // Include the caller's role, like every other board response.
  res.json({ ...rows[0], myRole: role });
});

// Only the owner can delete.
boardsRouter.delete("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid board id" });
    return;
  }
  const role = await getRole(params.data.id, res.locals.userId);
  if (!role) {
    res.status(404).json({ error: "Board not found" });
    return;
  }
  if (role !== "owner") {
    res.status(403).json(forbidden);
    return;
  }
  await pool.query("DELETE FROM boards WHERE id = $1", [params.data.id]);
  res.status(204).end();
});