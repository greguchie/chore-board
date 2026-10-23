import { Router } from "express";
import { z } from "zod";
import { pool } from "../db.js";

export const boardsRouter = Router();

const columns = `b.id, b.name, b.description, b.owner_id AS "ownerId",
  b.created_at AS "createdAt", b.updated_at AS "updatedAt"`;

const idParams = z.object({ id: z.uuid() });

const listQuery = z.object({ userId: z.uuid().optional() });

const createBoard = z.object({
  name: z.string().trim().min(1).max(100),
  description: z.string().trim().max(500).optional(),
  ownerId: z.uuid(),
});

const updateBoard = z
  .object({
    name: z.string().trim().min(1).max(100).optional(),
    description: z.string().trim().max(500).optional(),
  })
  .refine((data) => Object.keys(data).length > 0, {
    message: "Provide at least one field to update",
  });

boardsRouter.post("/", async (req, res) => {
  const parsed = createBoard.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid input", details: parsed.error.issues });
    return;
  }
  const { name, description, ownerId } = parsed.data;

  const owner = await pool.query("SELECT 1 FROM users WHERE id = $1", [ownerId]);
  if (owner.rows.length === 0) {
    res.status(404).json({ error: "Owner not found" });
    return;
  }

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
    res.status(201).json(rows[0]);
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
});

boardsRouter.get("/", async (req, res) => {
  const query = listQuery.safeParse(req.query);
  if (!query.success) {
    res.status(400).json({ error: "Invalid userId" });
    return;
  }
  const { userId } = query.data;
  const { rows } = userId
    ? await pool.query(
        `SELECT ${columns} FROM boards b
         JOIN members m ON m.board_id = b.id
         WHERE m.user_id = $1 ORDER BY b.created_at`,
        [userId],
      )
    : await pool.query(`SELECT ${columns} FROM boards b ORDER BY b.created_at`);
  res.json(rows);
});

boardsRouter.get("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid board id" });
    return;
  }
  const { rows } = await pool.query(
    `SELECT ${columns} FROM boards b WHERE b.id = $1`,
    [params.data.id],
  );
  if (rows.length === 0) {
    res.status(404).json({ error: "Board not found" });
    return;
  }
  res.json(rows[0]);
});

boardsRouter.patch("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  const body = updateBoard.safeParse(req.body);
  if (!params.success || !body.success) {
    res.status(400).json({ error: "Invalid input" });
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
  if (rows.length === 0) {
    res.status(404).json({ error: "Board not found" });
    return;
  }
  res.json(rows[0]);
});

boardsRouter.delete("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid board id" });
    return;
  }
  const result = await pool.query("DELETE FROM boards WHERE id = $1", [
    params.data.id,
  ]);
  if (result.rowCount === 0) {
    res.status(404).json({ error: "Board not found" });
    return;
  }
  res.status(204).end();
});
