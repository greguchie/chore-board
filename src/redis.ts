import { Redis } from 'ioredis';
import { config } from './config.js';
import { logger } from './logger.js';

// One shared connection for the whole API (like the Postgres pool).
export const redis = new Redis(config.REDIS_URL, {
  // A cache must never slow requests down. If Redis isn't connected,
  // fail commands immediately instead of queueing them until it returns.
  enableOfflineQueue: false,
  maxRetriesPerRequest: 1,
  connectTimeout: 2000,
});

// Log state changes only, not every reconnect attempt.
let isDown = false;

redis.on('ready', () => {
  isDown = false;
  logger.info('Redis connected');
});

redis.on('error', (err) => {
  if (isDown) return;
  isDown = true;
  logger.error({ err }, 'Redis unavailable; reconnecting in the background');
});