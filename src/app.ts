import { readFileSync } from "node:fs";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import swaggerUi from "swagger-ui-express";
import { parse } from "yaml";
import { pool } from "./db.js";
import { boardsRouter } from "./routes/boards.js";
import { membersRouter } from "./routes/members.js";
import { tasksRouter } from "./routes/tasks.js";
import { usersRouter } from "./routes/users.js";

export const app = express();

const openApiDocument = parse(
  readFileSync(new URL("../openapi.yaml", import.meta.url), "utf8"),
);

app.use(express.json());

app.get("/health", async (_req, res) => {
  const result = await pool.query("select now() as time");
  res.json({ status: "ok", dbTime: result.rows[0].time });
});

app.use("/docs", swaggerUi.serve, swaggerUi.setup(openApiDocument));

app.use("/users", usersRouter);
app.use("/boards", boardsRouter);
app.use("/boards/:boardId/members", membersRouter);
app.use("/boards/:boardId/tasks", tasksRouter);

app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  const { code, type } = err as { code?: string; type?: string };
  if (type === "entity.parse.failed") {
    res.status(400).json({ error: "Malformed JSON" });
    return;
  }
  if (code === "23505") {
    res.status(409).json({ error: "That value is already in use" });
    return;
  }
  if (code === "23503" || code === "23001") {
    res.status(409).json({ error: "Conflicts with related data" });
    return;
  }
  console.error(err);
  res.status(500).json({ error: "Internal server error" });
});
