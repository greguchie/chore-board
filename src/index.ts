import { config } from "./config.js";
import { app } from "./app.js";
import { logger } from './logger.js';

app.listen(config.PORT, () => {
  logger.info({ port: config.PORT }, 'API listening');
});