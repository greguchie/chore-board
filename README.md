# chore-board

A chore-tracking app built with Node.js and TypeScript.

## Getting started

```bash
npm install
npm run dev
```

## Scripts

- `npm run dev` runs the app with auto-reload
- `npm run build` compiles TypeScript to `dist/`
- `npm start` runs the compiled build

## Branching

- `main` is always working and only changes through pull requests
- Branch names: `feature/<name>`, `fix/<name>`, `chore/<name>`
- Small commits, one purpose per branch

## Database setup

Requires PostgreSQL. Create the database and apply migrations:

```bash
createdb chore_board
cp .env.example .env
npm run migrate up
```
