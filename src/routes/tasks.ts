import { Router } from "express";
import { z } from "zod";
import { pool } from "../db.js";
import { requireRole } from "../middleware/auth.js";

export const tasksRouter = Router({ mergeParams: true });

const columns = `t.id, t.board_id AS "boardId", t.title, t.description, t.status,
  t.assignee_id AS "assigneeId",
  to_char(t.due_date, 'YYYY-MM-DD') AS "dueDate",
  t.completed_at AS "completedAt",
  t.created_at AS "createdAt", t.updated_at AS "updatedAt"`;

const statusValues = ["todo", "in_progress", "done"] as const;

const boardParams = z.object({ boardId: z.uuid() });
const taskParams = z.object({ boardId: z.uuid(), taskId: z.uuid() });

const listQuery = z.object({
  status: z.enum(statusValues).optional(),
  assigneeId: z.uuid().optional(),
});

const createTask = z.object({
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(2000).optional(),
  assigneeId: z.uuid().optional(),
  dueDate: z.iso.date().optional(),
});

const updateTask = z
  .object({
    title: z.string().trim().min(1).max(200).optional(),
    description: z.string().trim().max(2000).nullable().optional(),
    status: z.enum(statusValues).optional(),
    assigneeId: z.uuid().nullable().optional(),
    dueDate: z.iso.date().nullable().optional(),
  })
  .refine((data) => Object.keys(data).length > 0, {
    message: "Provide at least one field to update",
  });

const fieldColumns = {
  title: "title",
  description: "description",
  status: "status",
  assigneeId: "assignee_id",
  dueDate: "due_date",
} as const;

async function isBoardMember(memberId: string, boardId: string) {
  const { rows } = await pool.query(
    "SELECT 1 FROM members WHERE id = $1 AND board_id = $2",
    [memberId, boardId],
  );
  return rows.length > 0;
}

tasksRouter.post("/", async (req, res) => {
  const params = boardParams.safeParse(req.params);
  const body = createTask.safeParse(req.body);
  if (!params.success || !body.success) {
    res.status(400).json({
      error: "Invalid input",
      details: body.success ? undefined : body.error.issues,
    });
    return;
  }
  const { boardId } = params.data;
  const { title, description, assigneeId, dueDate } = body.data;

  const board = await pool.query("SELECT 1 FROM boards WHERE id = $1", [boardId]);
  if (board.rows.length === 0) {
    res.status(404).json({ error: "Board not found" });
    return;
  }
  if (assigneeId && !(await isBoardMember(assigneeId, boardId))) {
    res.status(400).json({ error: "Assignee is not a member of this board" });
    return;
  }

  const { rows } = await pool.query(
    `INSERT INTO tasks AS t (board_id, title, description, assignee_id, due_date)
     VALUES ($1, $2, $3, $4, $5) RETURNING ${columns}`,
    [boardId, title, description ?? null, assigneeId ?? null, dueDate ?? null],
  );
  res.status(201).json(rows[0]);
});

tasksRouter.get("/", async (req, res) => {
  const params = boardParams.safeParse(req.params);
  const query = listQuery.safeParse(req.query);
  if (!params.success || !query.success) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }
  const { boardId } = params.data;

  const board = await pool.query("SELECT 1 FROM boards WHERE id = $1", [boardId]);
  if (board.rows.length === 0) {
    res.status(404).json({ error: "Board not found" });
    return;
  }

  const conditions = ["t.board_id = $1"];
  const values: unknown[] = [boardId];
  if (query.data.status) {
    values.push(query.data.status);
    conditions.push(`t.status = $${values.length}`);
  }
  if (query.data.assigneeId) {
    values.push(query.data.assigneeId);
    conditions.push(`t.assignee_id = $${values.length}`);
  }

  const { rows } = await pool.query(
    `SELECT ${columns} FROM tasks t
     WHERE ${conditions.join(" AND ")}
     ORDER BY t.created_at`,
    values,
  );
  res.json(rows);
});

tasksRouter.get("/:taskId", async (req, res) => {
  const params = taskParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid id" });
    return;
  }
  const { rows } = await pool.query(
    `SELECT ${columns} FROM tasks t WHERE t.id = $1 AND t.board_id = $2`,
    [params.data.taskId, params.data.boardId],
  );
  if (rows.length === 0) {
    res.status(404).json({ error: "Task not found" });
    return;
  }
  res.json(rows[0]);
});

tasksRouter.patch("/:taskId", async (req, res) => {
  const params = taskParams.safeParse(req.params);
  const body = updateTask.safeParse(req.body);
  if (!params.success || !body.success) {
    res.status(400).json({
      error: "Invalid input",
      details: body.success ? undefined : body.error.issues,
    });
    return;
  }
  const { boardId, taskId } = params.data;
  const data = body.data;

  if (data.assigneeId && !(await isBoardMember(data.assigneeId, boardId))) {
    res.status(400).json({ error: "Assignee is not a member of this board" });
    return;
  }

  const values: unknown[] = [taskId, boardId];
  const sets: string[] = [];
  for (const [key, column] of Object.entries(fieldColumns)) {
    if (!(key in data)) continue;
    values.push(data[key as keyof typeof data]);
    sets.push(`${column} = $${values.length}`);
    if (key === "status") {
      sets.push(
        `completed_at = CASE WHEN $${values.length}::text = 'done'
           THEN COALESCE(t.completed_at, now()) ELSE NULL END`,
      );
    }
  }
  sets.push("updated_at = now()");

  const { rows } = await pool.query(
    `UPDATE tasks AS t SET ${sets.join(", ")}
     WHERE t.id = $1 AND t.board_id = $2
     RETURNING ${columns}`,
    values,
  );
  if (rows.length === 0) {
    res.status(404).json({ error: "Task not found" });
    return;
  }
  res.json(rows[0]);
});

tasksRouter.delete("/:taskId", requireRole("owner", "admin"), async (req, res) => {
  const params = taskParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: "Invalid id" });
    return;
  }
  const result = await pool.query(
    "DELETE FROM tasks WHERE id = $1 AND board_id = $2",
    [params.data.taskId, params.data.boardId],
  );
  if (result.rowCount === 0) {
    res.status(404).json({ error: "Task not found" });
    return;
  }
  res.status(204).end();
});
