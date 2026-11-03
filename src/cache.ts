import { redis } from './redis.js';
import { logger } from './logger.js';

export const TASKS_CACHE_TTL_SECONDS = 60;

const TASK_STATUSES = ['all', 'todo', 'in_progress', 'done'] as const;
type TaskStatusKey = (typeof TASK_STATUSES)[number];

// Key naming: resource:id:what:version. Bump v1 to v2 if the cached shape ever changes,
// so old entries are ignored instead of breaking the app.
export const cacheKeys = {
  boardTasks: (boardId: string, status: TaskStatusKey = 'all') =>
    `board:${boardId}:tasks:${status}:v1`,
  allBoardTasks: (boardId: string) =>
    TASK_STATUSES.map((s) => `board:${boardId}:tasks:${s}:v1`),
};

// Every helper "fails open": if Redis is down we log and carry on without the cache.

export async function cacheGetJson<T>(key: string): Promise<T | null> {
  try {
    const raw = await redis.get(key);
    return raw === null ? null : (JSON.parse(raw) as T);
  } catch (err) {
    logger.warn({ err, key }, 'Cache read failed; using database');
    return null;
  }
}

export async function cacheSetJson(key: string, value: unknown, ttlSeconds: number): Promise<void> {
  try {
    await redis.set(key, JSON.stringify(value), 'EX', ttlSeconds);
  } catch (err) {
    logger.warn({ err, key }, 'Cache write failed');
  }
}

export async function cacheDelete(keys: string[]): Promise<void> {
  if (keys.length === 0) return;
  try {
    await redis.del(...keys);
  } catch (err) {
    logger.warn({ err, keys }, 'Cache invalidation failed; entries will expire via TTL');
  }
}

export async function invalidateBoardTasks(boardId: string): Promise<void> {
  await cacheDelete(cacheKeys.allBoardTasks(boardId));
}