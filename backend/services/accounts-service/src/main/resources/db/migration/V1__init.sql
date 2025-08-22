CREATE TABLE IF NOT EXISTS accounts (
  id UUID PRIMARY KEY,
  customer_id UUID NOT NULL,
  number VARCHAR(30) UNIQUE NOT NULL,
  branch VARCHAR(10) NOT NULL,
  balance NUMERIC(18,2) NOT NULL DEFAULT 0,
  currency VARCHAR(3) NOT NULL DEFAULT 'BRL',
  created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_accounts_customer ON accounts(customer_id);
