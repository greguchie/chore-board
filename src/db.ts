import pg from "pg";
import { config } from "./config.js";

export const pool = new pg.Pool({
  connectionString: config.DATABASE_URL,
});

// An idle connection can fail (for example, if the database restarts).
// Without this listener Node treats the 'error' event as unhandled and
// crashes the whole server. The pool replaces the broken connection.
pool.on("error", (err) => {
  console.error("Unexpected database pool error:", err.message);
});