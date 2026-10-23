import { config } from "./config.js";
import { app } from "./app.js";

app.listen(config.PORT, () => {
  console.log(`API listening on http://localhost:${config.PORT}`);
});