import { Redis } from 'ioredis';
import { config } from './config.js';
import { logger } from './logger.js';

// One shared connection for the whole API (like the Postgres pool).
export const redis = new Redis(config.REDIS_URL, {
  // Fail a command after 2 retries instead of hanging the request
  // if Redis is down. Callers decide what to do (e.g. skip the cache).
  maxRetriesPerRequest: 2,
});

redis.on('ready', () => logger.info('Redis connected'));
redis.on('error', (err) => logger.error({ err }, 'Redis error'));