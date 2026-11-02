-- Up Migration
CREATE TABLE invites (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_id    uuid NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
  token_hash  text NOT NULL UNIQUE,
  role        text NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  created_by  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at  timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX invites_board_id_idx ON invites (board_id);

-- Down Migration
DROP TABLE invites;