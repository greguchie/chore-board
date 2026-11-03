import { randomUUID } from 'node:crypto';
import type { IncomingMessage, Server } from 'node:http';
import type { Duplex } from 'node:stream';
import { decodeJwt } from 'jose';
import { WebSocketServer, type WebSocket } from 'ws';
import { z } from 'zod';
import { pool } from '../db.js';
import { logger } from '../logger.js';
import { verifyAccessToken } from '../tokens.js';

const HEARTBEAT_INTERVAL_MS = 30_000;
const MAX_MESSAGE_BYTES = 16 * 1024;
const MAX_SUBSCRIPTIONS_PER_CONNECTION = 50;

// Close codes 4000-4999 are reserved for apps to define their own meanings.
export const CLOSE_TOKEN_EXPIRED = 4001;

type Client = WebSocket & {
  isAlive: boolean;
  userId: string;
  connectionId: string;
  boards: Set<string>;
  expiryTimer?: NodeJS.Timeout;
};

type Auth = { userId: string; expiresAt: number };

// boardId -> open connections subscribed to it. Step 5 broadcasts through this.
const boardSubscribers = new Map<string, Set<Client>>();

// Every message from a client must match one of these shapes.
const clientMessage = z.discriminatedUnion('type', [
  z.object({ type: z.literal('ping') }),
  z.object({ type: z.literal('subscribe'), boardId: z.uuid() }),
  z.object({ type: z.literal('unsubscribe'), boardId: z.uuid() }),
]);

function send(ws: WebSocket, message: Record<string, unknown>) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(message));
}

// Same check as requireAuth: "Authorization: Bearer <token>", verified by verifyAccessToken.
async function authenticate(req: IncomingMessage): Promise<Auth | null> {
  const [scheme, token] = (req.headers.authorization ?? '').split(' ');
  if (scheme !== 'Bearer' || !token) return null;
  try {
    const userId = await verifyAccessToken(token);
    const { exp } = decodeJwt(token); // safe: the token was verified on the line above
    return { userId, expiresAt: (exp ?? 0) * 1000 };
  } catch {
    return null;
  }
}

// Before the upgrade we're still speaking plain HTTP, so we reply with a normal status line.
function rejectUpgrade(socket: Duplex, status: number, reason: string) {
  socket.write(`HTTP/1.1 ${status} ${reason}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
  socket.destroy();
}

async function isBoardMember(userId: string, boardId: string): Promise<boolean> {
  const { rows } = await pool.query(
    'SELECT 1 FROM members WHERE board_id = $1 AND user_id = $2',
    [boardId, userId],
  );
  return rows.length > 0;
}

function addSubscription(ws: Client, boardId: string) {
  ws.boards.add(boardId);
  let subscribers = boardSubscribers.get(boardId);
  if (!subscribers) {
    subscribers = new Set();
    boardSubscribers.set(boardId, subscribers);
  }
  subscribers.add(ws);
}

function removeSubscription(ws: Client, boardId: string) {
  ws.boards.delete(boardId);
  const subscribers = boardSubscribers.get(boardId);
  if (!subscribers) return;
  subscribers.delete(ws);
  if (subscribers.size === 0) boardSubscribers.delete(boardId);
}

export function attachRealtime(server: Server) {
  // noServer: we handle the HTTP "upgrade" ourselves so we can check the token first.
  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES });

  server.on('upgrade', (req, socket, head) => {
    socket.on('error', (err) => logger.warn({ err }, 'WebSocket upgrade socket error'));

    const { pathname } = new URL(req.url ?? '/', 'http://localhost');
    if (pathname !== '/ws') {
      socket.destroy();
      return;
    }

    authenticate(req)
      .then((auth) => {
        if (!auth) {
          logger.warn({ ip: req.socket.remoteAddress }, 'WebSocket rejected: missing or invalid token');
          rejectUpgrade(socket, 401, 'Unauthorized');
          return;
        }
        wss.handleUpgrade(req, socket, head, (ws) => onConnection(ws, auth));
      })
      .catch((err) => {
        logger.error({ err }, 'WebSocket upgrade failed');
        rejectUpgrade(socket, 500, 'Internal Server Error');
      });
  });

  function onConnection(socket: WebSocket, auth: Auth) {
    const ws = socket as Client;
    ws.isAlive = true;
    ws.userId = auth.userId;
    ws.connectionId = randomUUID();
    ws.boards = new Set();
    const log = logger.child({ userId: ws.userId, connectionId: ws.connectionId });

    ws.on('pong', () => {
      ws.isAlive = true;
    });

    // Close the socket the moment the access token expires; the app reconnects with a fresh one.
    ws.expiryTimer = setTimeout(
      () => ws.close(CLOSE_TOKEN_EXPIRED, 'Token expired'),
      Math.max(auth.expiresAt - Date.now(), 0),
    );

    log.info({ clients: wss.clients.size }, 'WebSocket connected');
    send(ws, { type: 'welcome', userId: ws.userId });

    ws.on('message', async (data) => {
      let parsed: unknown;
      try {
        parsed = JSON.parse(data.toString());
      } catch {
        send(ws, { type: 'error', message: 'Messages must be JSON' });
        return;
      }
      const message = clientMessage.safeParse(parsed);
      if (!message.success) {
        send(ws, { type: 'error', message: 'Invalid message' });
        return;
      }
      const msg = message.data;

      switch (msg.type) {
        case 'ping':
          send(ws, { type: 'pong' });
          return;

        case 'subscribe': {
          if (ws.boards.has(msg.boardId)) {
            send(ws, { type: 'subscribed', boardId: msg.boardId });
            return;
          }
          if (ws.boards.size >= MAX_SUBSCRIPTIONS_PER_CONNECTION) {
            send(ws, { type: 'error', message: 'Too many subscriptions' });
            return;
          }
          try {
            if (!(await isBoardMember(ws.userId, msg.boardId))) {
              // Same rule as REST: never confirm that a board exists to a non-member.
              send(ws, { type: 'error', message: 'Board not found', boardId: msg.boardId });
              return;
            }
          } catch (err) {
            log.error({ err, boardId: msg.boardId }, 'Subscribe failed');
            send(ws, { type: 'error', message: 'Could not subscribe, try again', boardId: msg.boardId });
            return;
          }
          if (ws.readyState !== ws.OPEN) return; // closed while we were checking
          addSubscription(ws, msg.boardId);
          log.info({ boardId: msg.boardId }, 'Subscribed to board');
          send(ws, { type: 'subscribed', boardId: msg.boardId });
          return;
        }

        case 'unsubscribe':
          removeSubscription(ws, msg.boardId);
          send(ws, { type: 'unsubscribed', boardId: msg.boardId });
          return;
      }
    });

    ws.on('close', (code) => {
      clearTimeout(ws.expiryTimer);
      for (const boardId of [...ws.boards]) removeSubscription(ws, boardId);
      log.info({ code, clients: wss.clients.size }, 'WebSocket disconnected');
    });

    ws.on('error', (err) => log.warn({ err }, 'WebSocket error'));
  }

  // Heartbeat: phones lose signal without closing the connection cleanly.
  // Every 30s, ping each client; any that didn't answer the last ping is dropped.
  const heartbeat = setInterval(() => {
    for (const socket of wss.clients) {
      const ws = socket as Client;
      if (!ws.isAlive) {
        ws.terminate();
        continue;
      }
      ws.isAlive = false;
      ws.ping();
    }
  }, HEARTBEAT_INTERVAL_MS);
  wss.on('close', () => clearInterval(heartbeat));

  return wss;
}