import type { NextFunction, Request, Response } from "express";
import { z } from "zod";
import { pool } from "../db.js";
import { verifyAccessToken } from "../tokens.js";

export type BoardRole = "owner" | "admin" | "member";

// Gate 1: is the caller logged in?
// Reads "Authorization: Bearer <token>", verifies the JWT, and stores
// the user's id in res.locals.userId for the routes behind it.
export async function requireAuth(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  const [scheme, token] = (req.get("authorization") ?? "").split(" ");
  if (scheme !== "Bearer" || !token) {
    res.status(401).json({ error: "Not authenticated" });
    return;
  }
  try {
    res.locals.userId = await verifyAccessToken(token);
  } catch {
    res.status(401).json({ error: "Invalid or expired token" });
    return;
  }
  next();
}

const boardIdSchema = z.uuid();

// Gate 2: is the caller a member of this board?
// Non-members get 404 (not 403) so we never confirm a board exists.
// Stores their role in res.locals.boardRole for Gate 3.
export async function requireBoardMember(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  const boardId = boardIdSchema.safeParse(req.params.boardId);
  if (!boardId.success) {
    res.status(400).json({ error: "Invalid board id" });
    return;
  }
  const { rows } = await pool.query(
    "SELECT role FROM members WHERE board_id = $1 AND user_id = $2",
    [boardId.data, res.locals.userId],
  );
  if (rows.length === 0) {
    res.status(404).json({ error: "Board not found" });
    return;
  }
  res.locals.boardRole = rows[0].role;
  next();
}

// Gate 3: does the caller's role allow this action?
// Use after requireBoardMember, e.g. requireRole("owner", "admin").
export function requireRole(...allowed: BoardRole[]) {
  return (_req: Request, res: Response, next: NextFunction) => {
    if (!allowed.includes(res.locals.boardRole)) {
      res
        .status(403)
        .json({ error: "Your role on this board doesn't allow this" });
      return;
    }
    next();
  };
}