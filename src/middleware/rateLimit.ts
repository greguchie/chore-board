import { rateLimit } from "express-rate-limit";
import { config } from "../config.js";

// Shared settings: send the modern RateLimit-* headers so clients can see
// how many requests they have left, and drop the old X-RateLimit-* ones.
const common = {
  standardHeaders: "draft-7" as const,
  legacyHeaders: false,
};

const FIFTEEN_MINUTES = 15 * 60 * 1000;
const ONE_HOUR = 60 * 60 * 1000;

// Safety net for the whole API.
export const apiLimiter = rateLimit({
  ...common,
  windowMs: FIFTEEN_MINUTES,
  limit: config.RATE_LIMIT_API_MAX,
  message: { error: "Too many requests, please slow down" },
});

// Brute-force protection: only FAILED logins count toward the limit.
// Each blocked attempt is logged so a brute-force attack is visible.
export const loginLimiter = rateLimit({
  ...common,
  windowMs: FIFTEEN_MINUTES,
  limit: config.RATE_LIMIT_LOGIN_MAX,
  skipSuccessfulRequests: true,
  message: { error: "Too many failed login attempts, try again in 15 minutes" },
  handler: (req, res, _next, options) => {
    console.warn(`Login rate limit reached for IP ${req.ip}`);
    res.status(options.statusCode).json(options.message);
  },
});

// Stops bots from mass-creating accounts.
export const signupLimiter = rateLimit({
  ...common,
  windowMs: ONE_HOUR,
  limit: config.RATE_LIMIT_SIGNUP_MAX,
  message: { error: "Too many accounts created, try again later" },
});