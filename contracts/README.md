# zkremit — Soroban ComplianceVerifier Contract

The `ComplianceVerifier` contract is the on-chain enforcement point for zkremit's private cross-border payment system. It verifies Noir UltraHonk compliance proofs using Stellar Protocol 25/26 BN254 host functions, records nullifiers to prevent replay, and emits compliance events.

---

## Functions

### `initialize`

Initializes the contract with the verification key, admin address, and initial Merkle roots.

| Parameter | Type | Description |
|---|---|---|
| `vk` | `Bytes` | Noir UltraHonk verification key (base64) |
| `admin` | `Address` | Admin address (can update roots) |
| `allowed_jurisdictions_root` | `BytesN<32>` | Merkle root of permitted jurisdiction codes |
| `approved_corridors_root` | `BytesN<32>` | Merkle root of currently approved corridors |
| `revocation_root` | `BytesN<32>` | Merkle root of revoked credentials |

**Authorization:** None (can only be called once).  
**Panics:** If already initialized.  
**Storage:** Writes to instance storage: `init`, `vk`, `admin`, `juris_root`, `corr_root`, `revoc_root`.

---

### `verify_and_record`

Verifies a Noir UltraHonk proof and records the nullifier to prevent double-use.

| Parameter | Type | Description |
|---|---|---|
| `proof` | `Bytes` | Serialized UltraHonk proof |
| `public_inputs` | `Bytes` | 264 bytes of encoded public inputs (see below) |

**Returns:** `bool` — `true` if proof is valid and nullifier is fresh.

**Public input byte layout (264 bytes):**

| Offset | Size | Field |
|---|---|---|
| 0 | 32 | `nullifier` — Poseidon2(credential_secret, corridor_id) |
| 32 | 32 | `issuer_pubkey_hash` — Poseidon2 of issuer secp256k1 pubkey |
| 64 | 32 | `payment_asset` — Asset identifier hash |
| 96 | 8 | `aml_threshold` — u64 big-endian |
| 104 | 32 | `corridor_id` — Hash of corridor string |
| 136 | 32 | `amount_commitment` — Pedersen commitment to amount |
| 168 | 32 | `revocation_root` — Current revocation Merkle root |
| 200 | 32 | `approved_corridors_root` — Current approved corridors root |
| 232 | 32 | `allowed_jurisdictions_root` — Current jurisdictions root |

**Validation:**
1. Roots in `public_inputs` must match stored roots (prevents stale proof attacks)
2. Nullifier must not be previously recorded
3. Proof must verify via `verify_groth16_bn254` host function

**Authorization:** None (publicly callable).  
**Events:** `(compliant, (nullifier, corridor_id, amount_commitment))`  
**Storage:** Records nullifier → `true` in persistent storage. Stores `ComplianceRecord` keyed by `0x01 || nullifier`.

---

### `is_nullifier_used`

Checks if a nullifier has been previously recorded.

| Parameter | Type | Description |
|---|---|---|
| `nullifier` | `BytesN<32>` | Nullifier to check |

**Returns:** `bool`

---

### `get_compliance_record`

Retrieves the full compliance record for a given nullifier.

| Parameter | Type | Description |
|---|---|---|
| `nullifier` | `BytesN<32>` | Nullifier to look up |

**Returns:** `Option<ComplianceRecord>`

**`ComplianceRecord` fields:**

| Field | Type | Description |
|---|---|---|
| `nullifier` | `BytesN<32>` | The nullifier |
| `issuer_pubkey_hash` | `BytesN<32>` | Issuer public key hash |
| `payment_asset` | `BytesN<32>` | Asset identifier |
| `corridor_id` | `BytesN<32>` | Payment corridor |
| `aml_threshold` | `u64` | AML threshold at time of verification |
| `amount_commitment` | `BytesN<32>` | Pedersen commitment to amount |
| `revocation_root` | `BytesN<32>` | Revocation root at time of verification |
| `approved_corridors_root` | `BytesN<32>` | Approved corridors root |
| `allowed_jurisdictions_root` | `BytesN<32>` | Allowed jurisdictions root |
| `verified_at` | `u64` | Ledger timestamp of verification |

---

### `get_verifier_key`

Returns the stored verification key.

**Returns:** `Bytes`

---

### `update_roots`

Updates the three Merkle roots (admin-only).

| Parameter | Type | Description |
|---|---|---|
| `caller` | `Address` | Must match stored admin |
| `new_revocation_root` | `BytesN<32>` | New revocation root |
| `new_approved_corridors_root` | `BytesN<32>` | New approved corridors root |
| `new_allowed_jurisdictions_root` | `BytesN<32>` | New allowed jurisdictions root |

**Authorization:** `caller.require_auth()`. Must match stored admin.  
**Events:** `(roots_upd, ())`

---

## Storage Layout

### Instance Storage

| Key | Type | Description |
|---|---|---|
| `init` | `bool` | Initialization flag |
| `vk` | `Bytes` | UltraHonk verification key |
| `admin` | `Address` | Admin address |
| `juris_root` | `BytesN<32>` | Allowed jurisdictions Merkle root |
| `corr_root` | `BytesN<32>` | Approved corridors Merkle root |
| `revoc_root` | `BytesN<32>` | Revoked credentials Merkle root |

### Persistent Storage

| Key | Value | Description |
|---|---|---|
| `nullifier` (`BytesN<32>`) | `bool` | Nullifier usage flag |
| `0x01 || nullifier` (`BytesN<33>`) | `ComplianceRecord` | Full compliance record |

---

## Events

| Topic | Data | When |
|---|---|---|
| `compliant` | `(nullifier, corridor_id, amount_commitment)` | After successful proof verification |
| `roots_upd` | `()` | After admin updates Merkle roots |

---

## Deployment

```bash
# Requires: stellar-cli, wasm32 target, ~100 XLM in deployer account

# Build and deploy to testnet
./contracts/scripts/deploy.sh testnet

# Build and deploy to mainnet (requires --confirm)
./contracts/scripts/deploy.sh mainnet

# Dry run — validates build and config without submitting transactions
./contracts/scripts/deploy.sh testnet --dry-run
```

## Deployed Contracts

### Testnet

| Contract | ID | Explorer |
|---|---|---|
| ComplianceVerifier | `$(grep VERIFIER_CONTRACT_ID .env 2>/dev/null \| cut -d= -f2)` | [stellar.expert](https://stellar.expert/explorer/testnet/contract/$(grep VERIFIER_CONTRACT_ID .env 2>/dev/null \| cut -d= -f2)) |

> **Note:** The contract ID above is dynamically read from your `.env` file after deployment. Run `./contracts/scripts/deploy.sh testnet` to deploy and populate it.

### Mainnet

Deploy to mainnet using the deployment pipeline (GitHub Actions) or manually with `./contracts/scripts/deploy.sh mainnet`. Mainnet deployment requires the `--confirm` interactive prompt and a separate `MAINNET_DEPLOYER_SECRET_KEY`.

---

## Testing

```bash
cd contracts/verifier
cargo test --features testutils
```

---

## Upgrade Path

To update the circuit's verification key, deploy a new contract instance with the new VK and reconfigure.

To update Merkle roots (jurisdictions, corridors, revocation), call `update_roots` with the admin key:

```bash
./contracts/scripts/invoke.sh update_roots \
    --revocation-root 0x... \
    --corridors-root 0x... \
    --jurisdictions-root 0x...
```

---

## Security Notes

- The contract uses `verify_groth16_bn254` host function (Protocol 25/26). Requires Stellar Protocol 25+.
- The admin key controls root updates. Store the admin key securely (e.g., hardware wallet, multisig).
- Nullifier storage is permanent and immutable. A recorded nullifier can never be removed.
- Root validation in `verify_and_record` prevents replay of proofs generated against stale roots.
