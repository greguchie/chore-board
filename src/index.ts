import { config } from "./config.js";
import { app } from "./app.js";
import { logger } from './logger.js';
import { attachRealtime } from './realtime/server.js';

const server = app.listen(config.PORT, () => {
  logger.info({ port: config.PORT }, 'API listening');
});
attachRealtime(server);