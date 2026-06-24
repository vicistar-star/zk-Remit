#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC} — $1"; }
fail() { echo -e "${RED}FAIL${NC} — $1"; FAILED=$((FAILED + 1)); }

FAILED=0
TOTAL=5
BASE_URL="${API_URL:-http://localhost:3000}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  zkremit End-to-End Tests${NC}"
echo -e "${YELLOW}========================================${NC}"
echo "Backend URL: $BASE_URL"
echo "Project dir: $PROJECT_DIR"
echo

# Prerequisites check
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo -e "${RED}Error: .env not found at $PROJECT_DIR/.env${NC}"
    echo "Run ./scripts/setup.sh first"
    exit 1
fi
source "$PROJECT_DIR/.env"

if [ -z "${VERIFIER_CONTRACT_ID:-}" ]; then
    echo -e "${RED}Error: VERIFIER_CONTRACT_ID not set in .env${NC}"
    echo "Deploy the contract first: ./contracts/scripts/deploy.sh"
    exit 1
fi

echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}  Step 1/5 — Backend Health Check${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"

if curl -sf "$BASE_URL/health" > /dev/null 2>&1; then
    pass "Backend health check returned 200"
else
    fail "Backend health check failed — is the server running on $BASE_URL?"
    echo -e "${YELLOW}  Start with: cd backend && npm run start:dev${NC}"
fi

echo
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}  Step 2/5 — Credential Issuance (Alice, NG-PH)${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"

TEST_WALLET="GAXK2SOZ2RI4ZJ6ZYVJXL6QY7YV5Z7G7Y6Y7Y6Y7Y6Y7Y6Y7Y6Y7Y6Y7Y"

CRED_RESPONSE=$(curl -sf -X POST "$BASE_URL/credential/issue" \
    -H "Content-Type: application/json" \
    -d "{\"walletAddress\":\"$TEST_WALLET\",\"kycProvider\":\"mock-issuer\",\"corridorId\":\"NG-PH\"}" 2>/dev/null || echo "")

if echo "$CRED_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    assert 'credentialHash' in d
    assert 'issuerSignature' in d
    assert 'issuerPubkey' in d
    assert 'expiry' in d
    assert 'jurisdictionCode' in d
    assert 'credentialSecret' in d
    assert d['jurisdictionCode'] == 566
    print(d['credentialHash'])
except Exception as e:
    sys.exit(1)
" 2>/dev/null; then
    CREDENTIAL_HASH=$(echo "$CRED_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['credentialHash'])")
    CREDENTIAL_SECRET=$(echo "$CRED_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['credentialSecret'])")
    ISSUER_SIGNATURE=$(echo "$CRED_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['issuerSignature'])")
    ISSUER_PUBKEY=$(echo "$CRED_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['issuerPubkey'])")
    EXPIRY=$(echo "$CRED_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['expiry'])")
    pass "Credential issued successfully — corridor NG-PH, jurisdiction 566 (Nigeria)"
else
    fail "Credential issuance failed — response: $CRED_RESPONSE"
    CREDENTIAL_HASH=""
    CREDENTIAL_SECRET=""
    ISSUER_SIGNATURE=""
    ISSUER_PUBKEY=""
    EXPIRY=""
fi

echo
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}  Step 3/5 — Proof Generation (nargo prove)${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"

if [ -n "$CREDENTIAL_HASH" ]; then
    # Build Prover.toml from the issued credential
    PROVER_TOML="$PROJECT_DIR/circuits/Prover.toml"
    TIMESTAMP=$(date +%s)
    AML_THRESHOLD=10000
    AMOUNT=500
    JURISDICTION_CODE=566
    CORRIDOR_ID="NG-PH"
    PAYMENT_ASSET="USDC"

    # Compute Poseidon2 hashes using node script
    PROVER_INPUTS=$(node -e "
    const { poseidon2 } = require('poseidon-lite');
    const crypto = require('crypto');

    const credentialHash = '$CREDENTIAL_HASH';
    const credentialSecret = '$CREDENTIAL_SECRET';
    const issuerSignature = '$ISSUER_SIGNATURE';
    const issuerPubkey = '$ISSUER_PUBKEY';
    const expiry = $EXPIRY;
    const timestamp = $TIMESTAMP;

    // Parse hex values to Field elements
    const ch = BigInt('0x' + credentialHash);
    const cs = BigInt('0x' + credentialSecret);
    const userPubkeyHash = poseidon2([BigInt(0)]);
    const corridorId = poseidon2([BigInt('NG-PH'.split('').map(c=>c.charCodeAt(0)).reduce((a,b)=>a*256n+BigInt(b),0n))]);

    const nullifier = poseidon2([cs, corridorId]);

    const signatureBytes = issuerSignature.match(/.{1,2}/g).map(b => parseInt(b, 16));
    const pubkeyBytes = issuerPubkey.match(/.{1,2}/g).map(b => parseInt(b, 16));

    const result = {
        credential_secret: cs.toString(),
        credential_hash: ch.toString(),
        issuer_signature: signatureBytes,
        issuer_pubkey: pubkeyBytes,
        user_pubkey_hash: userPubkeyHash.toString(),
        amount: $AMOUNT,
        jurisdiction_code: $JURISDICTION_CODE,
        credential_expiry: expiry,
        current_timestamp: timestamp,
        allowed_jurisdictions_path: Array(10).fill('0'),
        allowed_jurisdictions_indices: Array(10).fill(0),
        amount_blinding: '12345',
        revocation_path: Array(10).fill('0'),
        revocation_indices: Array(10).fill(0),
        approved_corridors_path: Array(8).fill('0'),
        approved_corridors_indices: Array(8).fill(0),
        nullifier: nullifier.toString(),
        issuer_pubkey_hash: '0',
        payment_asset: poseidon2([BigInt('USDC'.split('').map(c=>c.charCodeAt(0)).reduce((a,b)=>a*256n+BigInt(b),0n))]).toString(),
        aml_threshold: $AML_THRESHOLD,
        corridor_id: corridorId.toString(),
        allowed_jurisdictions_root: '0',
        amount_commitment: poseidon2([BigInt($AMOUNT), BigInt(12345)]).toString(),
        revocation_root: '0',
        approved_corridors_root: '0'
    };

    console.log(JSON.stringify(result));
    " 2>/dev/null || echo "")

    if [ -z "$PROVER_INPUTS" ]; then
        fail "Proof generation — could not compute Prover.toml inputs"
    else
        # Write Prover.toml
        echo "$PROVER_INPUTS" | python3 -c "
import sys, json
inputs = json.load(sys.stdin)
out = []
for k, v in inputs.items():
    if isinstance(v, list):
        out.append(f'{k} = [{chr(10)}{chr(10).join([str(x) for x in v])}{chr(10)}]')
    else:
        out.append(f'{k} = \"{v}\"')
print('\n'.join(out))
" > "$PROVER_TOML"

        # Run nargo prove
        cd "$PROJECT_DIR/circuits"
        if nargo prove 2>&1; then
            PROOF_FILE="$PROJECT_DIR/circuits/proofs/zk_compliance.proof"
            if [ -f "$PROOF_FILE" ]; then
                PROOF_SIZE=$(wc -c < "$PROOF_FILE")
                pass "Proof generated — $PROOF_SIZE bytes"
            else
                fail "Proof file not found at $PROOF_FILE"
            fi
        else
            fail "nargo prove failed"
        fi
        cd "$PROJECT_DIR"
    fi
else
    fail "Skipped proof generation — no credential"
fi

echo
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}  Step 4/5 — Proof Relay to Soroban${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"

# For proof relay, we use the generated proof if available, otherwise send test data
PROOF_FILE="$PROJECT_DIR/circuits/proofs/zk_compliance.proof"
if [ -f "$PROOF_FILE" ]; then
    PROOF_HEX=$(xxd -p "$PROOF_FILE" | tr -d '\n')
    PROOF_HEX="0x$PROOF_HEX"
else
    PROOF_HEX="0xabcd"
fi

# Construct public inputs from the credential
NULLIFIER=$(node -e "
const { poseidon2 } = require('poseidon-lite');
const cs = BigInt('0x$CREDENTIAL_SECRET');
const corridorId = poseidon2([BigInt('NG-PH'.split('').map(c=>c.charCodeAt(0)).reduce((a,b)=>a*256n+BigInt(b),0n))]);
const nullifier = poseidon2([cs, corridorId]);
console.log('0x' + nullifier.toString(16).padStart(64, '0'));
" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")

PAYLOAD=$(cat <<EOF
{
  "proof": "$PROOF_HEX",
  "publicInputs": {
    "nullifier": "$NULLIFIER",
    "issuer_pubkey_hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "payment_asset": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "aml_threshold": 10000,
    "corridor_id": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "amount_commitment": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "revocation_root": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "approved_corridors_root": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "allowed_jurisdictions_root": "0x0000000000000000000000000000000000000000000000000000000000000000"
  }
}
EOF
)

if [ -n "$NULLIFIER" ]; then
    PROOF_RESPONSE=$(curl -sf -X POST "$BASE_URL/proof/relay" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>/dev/null || echo "")

    if echo "$PROOF_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    assert d.get('verified') == True
    print(d.get('txHash', 'no-tx-hash'))
except Exception as e:
    sys.exit(1)
" 2>/dev/null; then
        TX_HASH=$(echo "$PROOF_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('txHash',''))")
        pass "Proof relay returned verified: true — txHash: $TX_HASH"
    else
        fail "Proof relay failed — response: $PROOF_RESPONSE"
    fi
else
    fail "Skipped proof relay — no nullifier"
fi

echo
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}  Step 5/5 — Nullifier Check + Payment${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"

# Step 5a: Nullifier check
NULLIFIER_RESPONSE=$(curl -sf "$BASE_URL/nullifier/$NULLIFIER" 2>/dev/null || echo "")
if echo "$NULLIFIER_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    assert d.get('used') == True
except:
    sys.exit(1)
" 2>/dev/null; then
    pass "Nullifier check returned used: true"
else
    fail "Nullifier check failed — response: $NULLIFIER_RESPONSE"
fi

# Step 5b: Payment send
PAYMENT_RESPONSE=$(curl -sf -X POST "$BASE_URL/payment/send" \
    -H "Content-Type: application/json" \
    -d "{
      \"nullifier\":\"$NULLIFIER\",
      \"signedXdr\":\"AAAAAgAAAQAAAAAAAAAA\"
    }" 2>/dev/null || echo "")

if echo "$PAYMENT_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    assert d.get('success') == True
except:
    sys.exit(1)
" 2>/dev/null; then
    pass "Payment submitted successfully"
else
    fail "Payment failed — response: $PAYMENT_RESPONSE"
fi

echo
echo -e "${YELLOW}========================================${NC}"
PASSED=$((TOTAL - FAILED))
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}  Results: $PASSED/$TOTAL tests passed${NC}"
    echo -e "${GREEN}  All checks passed — zkremit is working!${NC}"
else
    echo -e "${RED}  Results: $PASSED/$TOTAL tests passed${NC}"
    echo -e "${RED}  $FAILED test(s) failed${NC}"
fi
echo -e "${YELLOW}========================================${NC}"
echo

exit $FAILED
