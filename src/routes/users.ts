import { Router } from "express";
import { z } from "zod";
import { pool } from "../db.js";
import { hashPassword } from "../password.js";

export const usersRouter = Router();

const columns = `id, email, display_name AS "displayName",
  created_at AS "createdAt", updated_at AS "updatedAt"`;

const idParams = z.object({ id: z.uuid() });

const createUser = z.object({
  email: z.email(),
  displayName: z.string().trim().min(1).max(100),
  password: z.string().min(8).max(128),
});

const updateUser = z
  .object({
    email: z.email().optional(),
    displayName: z.string().trim().min(1).max(100).optional(),
  })
  .refine((data) => Object.keys(data).length > 0, {
    message: "Provide at least one field to update",
  });

usersRouter.post("/", async (req, res) => {
  const parsed = createUser.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid input", details: parsed.error.issues });
    return;
  }
  const { email, displayName, password } = parsed.data;
  const passwordHash = await hashPassword(password);
  const { rows } = await pool.query(
    `INSERT INTO users (email, display_name, password_hash)
     VALUES ($1, $2, $3) RETURNING ${columns}`,
    [email.toLowerCase(), displayName, passwordHash],
  );
  res.status(201).json(rows[0]);
});

usersRouter.get("/", async (_req, res) => {
  const { rows } = await pool.query(
    `SELECT ${columns} FROM users ORDER BY created_at`,
  );
  res.json(rows);
});

usersRouter.get("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid user id" });
    return;
  }
  const { rows } = await pool.query(
    `SELECT ${columns} FROM users WHERE id = $1`,
    [params.data.id],
  );
  if (rows.length === 0) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json(rows[0]);
});

usersRouter.patch("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  const body = updateUser.safeParse(req.body);
  if (!params.success || !body.success) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }
  const { email, displayName } = body.data;
  const { rows } = await pool.query(
    `UPDATE users
     SET email = COALESCE($2, email),
         display_name = COALESCE($3, display_name),
         updated_at = now()
     WHERE id = $1
     RETURNING ${columns}`,
    [params.data.id, email?.toLowerCase() ?? null, displayName ?? null],
  );
  if (rows.length === 0) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json(rows[0]);
});

usersRouter.delete("/:id", async (req, res) => {
  const params = idParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid user id" });
    return;
  }
  const result = await pool.query("DELETE FROM users WHERE id = $1", [
    params.data.id,
  ]);
  if (result.rowCount === 0) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.status(204).end();
});
