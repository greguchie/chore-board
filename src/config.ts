import { z } from "zod";

// Every setting the app needs, validated once at startup.
// If anything is missing or invalid, the app refuses to start.
const envSchema = z.object({
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z
    .string()
    .regex(/^postgres(ql)?:\/\//, "must be a postgres:// connection string"),
  // Signs access tokens (JWTs). Must be long and random.
  JWT_ACCESS_SECRET: z
    .string()
    .min(32, "must be at least 32 characters (use: openssl rand -base64 48)"),
  ACCESS_TOKEN_TTL: z.string().default("15m"),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  // Rate limits (per IP address).
  RATE_LIMIT_API_MAX: z.coerce.number().int().positive().default(300), // per 15 min
  RATE_LIMIT_LOGIN_MAX: z.coerce.number().int().positive().default(5), // failed, per 15 min
  RATE_LIMIT_SIGNUP_MAX: z.coerce.number().int().positive().default(10), // per hour
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error("Invalid environment configuration:");
  for (const issue of parsed.error.issues) {
    // Prints the variable name and the problem, never the secret value.
    console.error(`  ${issue.path.join(".")}: ${issue.message}`);
  }
  process.exit(1);
}

export const config = parsed.data;