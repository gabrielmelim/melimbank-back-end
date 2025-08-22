DO $$ BEGIN
  CREATE TYPE tx_type AS ENUM ('DEBIT','CREDIT','TRANSFER');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL,
  type tx_type NOT NULL,
  amount NUMERIC(18,2) NOT NULL CHECK (amount > 0),
  description VARCHAR(200),
  created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);
