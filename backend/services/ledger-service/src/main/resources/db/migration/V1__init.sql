CREATE TABLE IF NOT EXISTS ledger_accounts (
  id UUID PRIMARY KEY,
  code VARCHAR(20) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS ledger_entries (
  id UUID PRIMARY KEY,
  tx_id UUID NOT NULL,
  debit_account UUID NOT NULL,
  credit_account UUID NOT NULL,
  amount NUMERIC(18,2) NOT NULL CHECK (amount > 0),
  created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledger_tx ON ledger_entries(tx_id);
