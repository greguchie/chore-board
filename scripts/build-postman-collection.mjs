// Generates postman/chore-board.postman_collection.json.
// Run: npm run postman:build   Then test: npm run test:api
// Start the server first with: npm run dev:test (relaxed rate limits).
import { writeFileSync } from "node:fs";

const PASSWORD = "correct-horse-1";
const ROLE_FORBIDDEN = "Your role on this board doesn't allow this";

// ---------- helpers that write Postman test lines ----------
const status = (code) =>
  `pm.test("status is ${code}", () => pm.response.to.have.status(${code}));`;
const errorIs = (msg) =>
  `pm.test(${JSON.stringify(`error is: ${msg}`)}, () => pm.expect(pm.response.json().error).to.eql(${JSON.stringify(msg)}));`;
const check = (title, code) => `pm.test(${JSON.stringify(title)}, () => { ${code} });`;
const save = (name, expr) => `pm.collectionVariables.set(${JSON.stringify(name)}, ${expr});`;
const v = (name) => `pm.collectionVariables.get(${JSON.stringify(name)})`;
const email = (who) => `${who}.{{runId}}@example.com`;

// One request. `as` = name of a token variable; `token` = a literal token.
function req(name, method, path, opts = {}) {
  const { as, token, body, raw, tests = [], pre = [] } = opts;
  const bearer = as ? `{{${as}}}` : token;
  const item = {
    name,
    request: {
      method,
      auth: bearer
        ? { type: "bearer", bearer: [{ key: "token", value: bearer, type: "string" }] }
        : { type: "noauth" },
      header: [],
      url: `{{baseUrl}}${path}`,
    },
    event: [],
  };
  if (body !== undefined || raw !== undefined) {
    item.request.header.push({ key: "Content-Type", value: "application/json" });
    item.request.body = { mode: "raw", raw: raw ?? JSON.stringify(body, null, 2) };
  }
  if (pre.length) {
    item.event.push({ listen: "prerequest", script: { type: "text/javascript", exec: pre } });
  }
  if (tests.length) {
    item.event.push({ listen: "test", script: { type: "text/javascript", exec: tests } });
  }
  return item;
}

const folder = (name, item) => ({ name, item });

const BOARD = "/boards/{{boardId}}";

const folders = [
  folder("1. Health", [
    req("Health check", "GET", "/health", {
      pre: ['pm.collectionVariables.set("runId", String(Date.now()));'],
      tests: [status(200), check("database is up", 'pm.expect(pm.response.json().status).to.eql("ok");')],
    }),
  ]),

  folder("2. Sign-up", [
    ...[
      ["owner", "ownerUserId"],
      ["member", "memberUserId"],
      ["admin", "adminUserId"],
    ].map(([who, idVar]) =>
      req(`Sign up ${who}`, "POST", "/users", {
        body: { email: email(who), displayName: who, password: PASSWORD },
        tests: [
          status(201),
          check("password is never returned",
            'const u = pm.response.json(); pm.expect(u).to.not.have.property("password"); pm.expect(u).to.not.have.property("passwordHash");'),
          save(idVar, "pm.response.json().id"),
        ],
      }),
    ),
    req("Duplicate email is rejected", "POST", "/users", {
      body: { email: email("owner"), displayName: "dup", password: PASSWORD },
      tests: [status(409)],
    }),
    req("Too-short password is rejected", "POST", "/users", {
      body: { email: email("short"), displayName: "short", password: "short" },
      tests: [status(400)],
    }),
  ]),

  folder("3. Auth", [
    req("Wrong password", "POST", "/auth/login", {
      body: { email: email("owner"), password: "wrong-password" },
      tests: [status(401), errorIs("Invalid email or password")],
    }),
    req("Unknown email gives the same error", "POST", "/auth/login", {
      body: { email: email("nobody"), password: PASSWORD },
      tests: [status(401), errorIs("Invalid email or password")],
    }),
    ...[
      ["owner", "ownerToken", "ownerRefresh"],
      ["member", "memberToken", null],
      ["admin", "adminToken", null],
    ].map(([who, tokenVar, refreshVar]) =>
      req(`Log in ${who}`, "POST", "/auth/login", {
        body: { email: email(who), password: PASSWORD },
        tests: [
          status(200),
          check("token type is Bearer", 'pm.expect(pm.response.json().tokenType).to.eql("Bearer");'),
          save(tokenVar, "pm.response.json().accessToken"),
          ...(refreshVar ? [save(refreshVar, "pm.response.json().refreshToken")] : []),
        ],
      }),
    ),
    req("No token is rejected", "GET", "/users/me", {
      tests: [status(401), errorIs("Not authenticated")],
    }),
    req("Fake token is rejected", "GET", "/users/me", {
      token: "not-a-real-token",
      tests: [status(401), errorIs("Invalid or expired token")],
    }),
    req("Who am I", "GET", "/users/me", {
      as: "ownerToken",
      tests: [
        status(200),
        check("returns the logged-in user",
          `pm.expect(pm.response.json().email).to.eql("owner." + ${v("runId")} + "@example.com");`),
      ],
    }),
    req("Refresh rotates the token pair", "POST", "/auth/refresh", {
      body: { refreshToken: "{{ownerRefresh}}" },
      tests: [
        status(200),
        check("new refresh token differs from the old one",
          `pm.expect(pm.response.json().refreshToken).to.not.eql(${v("ownerRefresh")});`),
        save("oldRefresh", v("ownerRefresh")),
        save("ownerRefresh", "pm.response.json().refreshToken"),
        save("ownerToken", "pm.response.json().accessToken"),
      ],
    }),
    req("Reusing an old refresh token is rejected", "POST", "/auth/refresh", {
      body: { refreshToken: "{{oldRefresh}}" },
      tests: [status(401), errorIs("Invalid refresh token")],
    }),
    req("Reuse revoked the whole session", "POST", "/auth/refresh", {
      body: { refreshToken: "{{ownerRefresh}}" },
      tests: [status(401), errorIs("Invalid refresh token")],
    }),
    req("Log in again for logout test", "POST", "/auth/login", {
      body: { email: email("owner"), password: PASSWORD },
      tests: [status(200), save("logoutRefresh", "pm.response.json().refreshToken")],
    }),
    req("Logout", "POST", "/auth/logout", {
      body: { refreshToken: "{{logoutRefresh}}" },
      tests: [status(204)],
    }),
    req("Refresh after logout is rejected", "POST", "/auth/refresh", {
      body: { refreshToken: "{{logoutRefresh}}" },
      tests: [status(401), errorIs("Invalid refresh token")],
    }),
    req("Logout with a bogus token still returns 204", "POST", "/auth/logout", {
      body: { refreshToken: "not-a-real-token" },
      tests: [status(204)],
    }),
  ]),

  folder("4. Users", [
    req("Read own account", "GET", "/users/{{ownerUserId}}", {
      as: "ownerToken",
      tests: [status(200)],
    }),
    req("Can't read someone else's account", "GET", "/users/{{ownerUserId}}", {
      as: "memberToken",
      tests: [status(403), errorIs("You can only access your own account")],
    }),
    req("Can't delete someone else's account", "DELETE", "/users/{{ownerUserId}}", {
      as: "memberToken",
      tests: [status(403)],
    }),
    req("Update own display name", "PATCH", "/users/{{ownerUserId}}", {
      as: "ownerToken",
      body: { displayName: "Owner Renamed" },
      tests: [status(200), check("name updated", 'pm.expect(pm.response.json().displayName).to.eql("Owner Renamed");')],
    }),
    req("Listing all users is not available", "GET", "/users", {
      as: "ownerToken",
      tests: [status(404), errorIs("Not found")],
    }),
  ]),

  folder("5. Boards", [
    req("Create board (injected ownerId and id are ignored)", "POST", "/boards", {
      as: "ownerToken",
      body: {
        name: "Test board {{runId}}",
        ownerId: "{{memberUserId}}",
        id: "00000000-0000-0000-0000-000000000000",
      },
      tests: [
        status(201),
        check("owner comes from the token", `pm.expect(pm.response.json().ownerId).to.eql(${v("ownerUserId")});`),
        check("caller is owner", 'pm.expect(pm.response.json().myRole).to.eql("owner");'),
        check("id was generated by the server", 'pm.expect(pm.response.json().id).to.not.eql("00000000-0000-0000-0000-000000000000");'),
        save("boardId", "pm.response.json().id"),
      ],
    }),
    req("Empty board name is rejected", "POST", "/boards", {
      as: "ownerToken",
      body: { name: "" },
      tests: [status(400)],
    }),
    req("Owner sees the board in their list", "GET", "/boards", {
      as: "ownerToken",
      tests: [status(200), check("board is listed", `pm.expect(pm.response.json().map((b) => b.id)).to.include(${v("boardId")});`)],
    }),
    req("Non-member gets 404 for the board", "GET", BOARD, {
      as: "memberToken",
      tests: [status(404), errorIs("Board not found")],
    }),
    req("Non-member gets 404 for its tasks", "GET", `${BOARD}/tasks`, {
      as: "memberToken",
      tests: [status(404), errorIs("Board not found")],
    }),
    req("Non-member's list excludes the board", "GET", "/boards", {
      as: "memberToken",
      tests: [status(200), check("board not listed", `pm.expect(pm.response.json().map((b) => b.id)).to.not.include(${v("boardId")});`)],
    }),
  ]),

  folder("6. Members and roles", [
    req("Owner adds a member", "POST", `${BOARD}/members`, {
      as: "ownerToken",
      body: { userId: "{{memberUserId}}" },
      tests: [status(201), check("role defaults to member", 'pm.expect(pm.response.json().role).to.eql("member");'),
        save("memberMembershipId", "pm.response.json().id")],
    }),
    req("Owner adds an admin", "POST", `${BOARD}/members`, {
      as: "ownerToken",
      body: { userId: "{{adminUserId}}", role: "admin" },
      tests: [status(201), save("adminMembershipId", "pm.response.json().id")],
    }),
    req("Adding the same user twice is rejected", "POST", `${BOARD}/members`, {
      as: "ownerToken",
      body: { userId: "{{memberUserId}}" },
      tests: [status(409)],
    }),
    req("Any member can list members", "GET", `${BOARD}/members`, {
      as: "memberToken",
      tests: [
        status(200),
        check("three members", "pm.expect(pm.response.json()).to.have.length(3);"),
        save("ownerMembershipId", 'pm.response.json().find((m) => m.role === "owner").id'),
      ],
    }),
    req("Member can't add members", "POST", `${BOARD}/members`, {
      as: "memberToken",
      body: { userId: "{{adminUserId}}" },
      tests: [status(403), errorIs(ROLE_FORBIDDEN)],
    }),
    req("Admin can't add admins", "POST", `${BOARD}/members`, {
      as: "adminToken",
      body: { userId: "{{memberUserId}}", role: "admin" },
      tests: [status(403), errorIs("Only the board owner can add admins")],
    }),
    req("Admin can't change roles", "PATCH", `${BOARD}/members/{{memberMembershipId}}`, {
      as: "adminToken",
      body: { role: "admin" },
      tests: [status(403), errorIs(ROLE_FORBIDDEN)],
    }),
    req("Owner promotes member to admin", "PATCH", `${BOARD}/members/{{memberMembershipId}}`, {
      as: "ownerToken",
      body: { role: "admin" },
      tests: [status(200), check("now admin", 'pm.expect(pm.response.json().role).to.eql("admin");')],
    }),
    req("Owner demotes them back to member", "PATCH", `${BOARD}/members/{{memberMembershipId}}`, {
      as: "ownerToken",
      body: { role: "member" },
      tests: [status(200), check("member again", 'pm.expect(pm.response.json().role).to.eql("member");')],
    }),
    req("Owner's own role can't change", "PATCH", `${BOARD}/members/{{ownerMembershipId}}`, {
      as: "ownerToken",
      body: { role: "member" },
      tests: [status(409)],
    }),
    req("Member can't edit the board", "PATCH", BOARD, {
      as: "memberToken",
      body: { name: "Member rename" },
      tests: [status(403), errorIs(ROLE_FORBIDDEN)],
    }),
    req("Admin can edit the board", "PATCH", BOARD, {
      as: "adminToken",
      body: { name: "Admin rename" },
      tests: [status(200), check("renamed", 'pm.expect(pm.response.json().name).to.eql("Admin rename");')],
    }),
    req("Admin can't delete the board", "DELETE", BOARD, {
      as: "adminToken",
      tests: [status(403), errorIs(ROLE_FORBIDDEN)],
    }),
  ]),

  folder("7. Tasks", [
    req("Member creates a task", "POST", `${BOARD}/tasks`, {
      as: "memberToken",
      body: { title: "Wash dishes" },
      tests: [
        status(201),
        check("starts as todo", 'pm.expect(pm.response.json().status).to.eql("todo");'),
        save("taskId", "pm.response.json().id"),
      ],
    }),
    req("Owner creates an assigned task", "POST", `${BOARD}/tasks`, {
      as: "ownerToken",
      body: { title: "Take out recycling", assigneeId: "{{memberMembershipId}}", dueDate: "2026-12-31" },
      tests: [
        status(201),
        check("assignee saved", `pm.expect(pm.response.json().assigneeId).to.eql(${v("memberMembershipId")});`),
        check("due date saved", 'pm.expect(pm.response.json().dueDate).to.eql("2026-12-31");'),
      ],
    }),
    req("Assignee must be a board member", "POST", `${BOARD}/tasks`, {
      as: "ownerToken",
      body: { title: "Nobody's job", assigneeId: "00000000-0000-4000-8000-000000000000" },
      tests: [status(400), errorIs("Assignee is not a member of this board")],
    }),
    req("List tasks", "GET", `${BOARD}/tasks`, {
      as: "memberToken",
      tests: [status(200), check("two tasks", "pm.expect(pm.response.json()).to.have.length(2);")],
    }),
    req("Filter tasks by status", "GET", `${BOARD}/tasks?status=todo`, {
      as: "memberToken",
      tests: [status(200), check("all are todo", 'pm.response.json().forEach((t) => pm.expect(t.status).to.eql("todo"));')],
    }),
    req("Mark task done", "PATCH", `${BOARD}/tasks/{{taskId}}`, {
      as: "memberToken",
      body: { status: "done" },
      tests: [status(200), check("completedAt is set", "pm.expect(pm.response.json().completedAt).to.not.eql(null);")],
    }),
    req("Reopen task", "PATCH", `${BOARD}/tasks/{{taskId}}`, {
      as: "memberToken",
      body: { status: "todo" },
      tests: [status(200), check("completedAt is cleared", "pm.expect(pm.response.json().completedAt).to.eql(null);")],
    }),
    req("Member can't delete tasks", "DELETE", `${BOARD}/tasks/{{taskId}}`, {
      as: "memberToken",
      tests: [status(403), errorIs(ROLE_FORBIDDEN)],
    }),
    req("Admin deletes the task", "DELETE", `${BOARD}/tasks/{{taskId}}`, {
      as: "adminToken",
      tests: [status(204)],
    }),
    req("Deleted task is gone", "GET", `${BOARD}/tasks/{{taskId}}`, {
      as: "ownerToken",
      tests: [status(404), errorIs("Task not found")],
    }),
  ]),

  folder("8. Leaving and removal", [
    req("Member can't remove the admin", "DELETE", `${BOARD}/members/{{adminMembershipId}}`, {
      as: "memberToken",
      tests: [status(403), errorIs(ROLE_FORBIDDEN)],
    }),
    req("Owner can't be removed", "DELETE", `${BOARD}/members/{{ownerMembershipId}}`, {
      as: "ownerToken",
      tests: [status(409)],
    }),
    req("Admin removes the member", "DELETE", `${BOARD}/members/{{memberMembershipId}}`, {
      as: "adminToken",
      tests: [status(204)],
    }),
    req("Removed member loses access", "GET", BOARD, {
      as: "memberToken",
      tests: [status(404), errorIs("Board not found")],
    }),
    req("Admin leaves the board", "DELETE", `${BOARD}/members/{{adminMembershipId}}`, {
      as: "adminToken",
      tests: [status(204)],
    }),
  ]),

  folder("9. Validation and errors", [
    req("Malformed JSON", "POST", "/auth/login", {
      raw: '{"email": broken',
      tests: [status(400), errorIs("Malformed JSON")],
    }),
    req("Body over 10 KB is rejected", "POST", "/boards", {
      as: "ownerToken",
      pre: ['pm.variables.set("bigName", "x".repeat(20000));'],
      raw: '{"name":"{{bigName}}"}',
      tests: [status(413), errorIs("Request body too large")],
    }),
    req("Unknown route returns JSON 404", "GET", "/does-not-exist", {
      tests: [status(404), errorIs("Not found")],
    }),
    req("Security headers are present", "GET", "/health", {
      tests: [
        status(200),
        check("nosniff header", 'pm.expect(pm.response.headers.get("X-Content-Type-Options")).to.eql("nosniff");'),
        check("no X-Powered-By header", 'pm.expect(pm.response.headers.has("X-Powered-By")).to.eql(false);'),
      ],
    }),
  ]),

  folder("10. Cleanup", [
    req("Owner deletes the board", "DELETE", BOARD, {
      as: "ownerToken",
      tests: [status(204)],
    }),
    req("Deleted board is gone", "GET", BOARD, {
      as: "ownerToken",
      tests: [status(404)],
    }),
    req("Delete member account", "DELETE", "/users/{{memberUserId}}", {
      as: "memberToken",
      tests: [status(204)],
    }),
    req("Delete admin account", "DELETE", "/users/{{adminUserId}}", {
      as: "adminToken",
      tests: [status(204)],
    }),
    req("Delete owner account", "DELETE", "/users/{{ownerUserId}}", {
      as: "ownerToken",
      tests: [status(204)],
    }),
  ]),
];

const collection = {
  info: {
    name: "Chore Board API",
    description:
      "Generated by scripts/build-postman-collection.mjs. Start the API with `npm run dev:test`, then run `npm run test:api`.",
    schema: "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
  },
  auth: { type: "noauth" },
  variable: [
    { key: "baseUrl", value: "http://localhost:3000" },
    { key: "runId", value: "" },
  ],
  item: folders,
};

const out = new URL("../postman/chore-board.postman_collection.json", import.meta.url);
writeFileSync(out, JSON.stringify(collection, null, 2) + "\n");

const count = folders.reduce((n, f) => n + f.item.length, 0);
console.log(`Wrote ${count} requests in ${folders.length} folders to postman/chore-board.postman_collection.json`);