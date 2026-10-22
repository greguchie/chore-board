import express from "express";
import { pool } from "./db.js";

export const app = express();

app.use(express.json());

app.get("/health", async (_req, res) => {
  const result = await pool.query("select now() as time");
  res.json({ status: "ok", dbTime: result.rows[0].time });
});
