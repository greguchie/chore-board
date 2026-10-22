-- Up Migration
CREATE TABLE members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_id uuid NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (board_id, user_id)
);
CREATE INDEX members_user_id_idx ON members (user_id);

-- Down Migration
DROP TABLE members;
