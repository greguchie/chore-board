-- Up Migration
CREATE TABLE tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_id uuid NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'in_progress', 'done')),
  assignee_id uuid REFERENCES members(id) ON DELETE SET NULL,
  due_date date,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tasks_board_id_idx ON tasks (board_id);
CREATE INDEX tasks_assignee_id_idx ON tasks (assignee_id);

-- Down Migration
DROP TABLE tasks;
