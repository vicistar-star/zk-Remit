CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(255) PRIMARY KEY,
  applied_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS credentials (
  id SERIAL PRIMARY KEY,
  wallet_address VARCHAR(56) NOT NULL,
  kyc_provider VARCHAR(64) NOT NULL,
  credential_hash VARCHAR(66) NOT NULL,
  credential_secret VARCHAR(66) NOT NULL,
  issuer_signature VARCHAR(130) NOT NULL,
  issuer_pubkey VARCHAR(66) NOT NULL,
  user_pubkey_hash VARCHAR(66) NOT NULL,
  jurisdiction_code INTEGER NOT NULL,
  corridor_id VARCHAR(66) NOT NULL,
  expiry BIGINT NOT NULL,
  is_revoked BOOLEAN DEFAULT false,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(wallet_address, corridor_id)
);

CREATE TABLE IF NOT EXISTS nullifiers (
  id SERIAL PRIMARY KEY,
  nullifier VARCHAR(66) UNIQUE NOT NULL,
  wallet_address VARCHAR(56),
  corridor_id VARCHAR(66),
  stellar_tx_hash VARCHAR(64),
  verified_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payments (
  id SERIAL PRIMARY KEY,
  nullifier VARCHAR(66) NOT NULL REFERENCES nullifiers(nullifier),
  from_address VARCHAR(56) NOT NULL,
  to_address VARCHAR(56) NOT NULL,
  amount VARCHAR(32) NOT NULL,
  asset_code VARCHAR(12) NOT NULL,
  asset_issuer VARCHAR(56),
  corridor_id VARCHAR(66) NOT NULL,
  stellar_tx_hash VARCHAR(64),
  ledger INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
