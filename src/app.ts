import { readFileSync } from "node:fs";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import helmet from "helmet";
import swaggerUi from "swagger-ui-express";
import { parse } from "yaml";
import { pool } from "./db.js";
import { requireAuth, requireBoardMember } from "./middleware/auth.js";
import {
  apiLimiter,
  loginLimiter,
  signupLimiter,
} from "./middleware/rateLimit.js";
import { authRouter } from "./routes/auth.js";
import { boardsRouter } from "./routes/boards.js";
import { membersRouter } from "./routes/members.js";
import { tasksRouter } from "./routes/tasks.js";
import { usersRouter } from "./routes/users.js";

export const app = express();

const openApiDocument = parse(
  readFileSync(new URL("../openapi.yaml", import.meta.url), "utf8"),
);

// API docs: security headers on, but Swagger UI needs inline scripts,
// so its content-security policy is relaxed. Registered before the
// strict helmet() below so that one never applies here.
app.use(
  "/docs",
  helmet({ contentSecurityPolicy: false }),
  swaggerUi.serve,
  swaggerUi.setup(openApiDocument),
);

// Everything else: full security headers + a global rate limit.
app.use(helmet());
app.use(apiLimiter);

// JSON bodies only, capped at 10 KB. Nothing in this API needs more,
// and a cap stops oversized requests from tying up the server.
app.use(express.json({ limit: "10kb" }));

app.get("/health", async (_req, res) => {
  const result = await pool.query("select now() as time");
  res.json({ status: "ok", dbTime: result.rows[0].time });
});

// Extra limits on the endpoints attackers target most.
app.use("/auth/login", loginLimiter);
app.post("/users", signupLimiter);

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

// Boards: must be logged in; each route checks membership and role itself.
app.use("/boards", requireAuth, boardsRouter);

// Unknown routes: a JSON 404 instead of Express's default HTML page.
app.use((_req, res) => {
  res.status(404).json({ error: "Not found" });
});

// Central error handler: map known problems to clear 4xx responses;
// anything unexpected is logged here and returned as a generic 500
// so internal details never reach the client.
app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  const { code, type } = err as { code?: string; type?: string };
  if (type === "entity.parse.failed") {
    res.status(400).json({ error: "Malformed JSON" });
    return;
  }
  if (type === "entity.too.large") {
    res.status(413).json({ error: "Request body too large" });
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
  // Postgres "data exception" errors (class 22): bad value that slipped
  // past validation, e.g. an invalid date or a string that's too long.
  if (typeof code === "string" && code.startsWith("22")) {
    res.status(400).json({ error: "Invalid input" });
    return;
  }
  console.error(err);
  res.status(500).json({ error: "Internal server error" });
});