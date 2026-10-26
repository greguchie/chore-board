import { readFileSync } from "node:fs";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import swaggerUi from "swagger-ui-express";
import { parse } from "yaml";
import { pool } from "./db.js";
import { requireAuth, requireBoardMember } from "./middleware/auth.js";
import { authRouter } from "./routes/auth.js";
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

// Public: login/refresh/logout. Users router handles its own auth per route
// (sign-up is public, everything else requires login).
app.use("/auth", authRouter);
app.use("/users", usersRouter);

// Board sub-resources: must be logged in AND a member of that board.
app.use(
  "/boards/:boardId/members",
  requireAuth,
  requireBoardMember,
  membersRouter,
);
app.use("/boards/:boardId/tasks", requireAuth, requireBoardMember, tasksRouter);

// Boards: must be logged in; each route checks membership itself.
app.use("/boards", requireAuth, boardsRouter);

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