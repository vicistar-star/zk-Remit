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

echo "E2E Tests for zkremit"
echo "Backend URL: $BASE_URL"
echo

# Step 1: Backend health check
if curl -sf "$BASE_URL/health" > /dev/null 2>&1; then
  pass "Backend health check returned 200"
else
  fail "Backend health check failed — is the server running?"
fi

# Step 2: Credential issuance
CRED_RESPONSE=$(curl -sf -X POST "$BASE_URL/credential/issue" \
  -H "Content-Type: application/json" \
  -d '{"walletAddress":"GAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQ","kycProvider":"mock-issuer","corridorId":"NG-PH"}' 2>/dev/null || echo "")

if echo "$CRED_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'credentialHash' in d" 2>/dev/null; then
  pass "Credential issuance returned credentialHash"
  CREDENTIAL_HASH=$(echo "$CRED_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['credentialHash'])")
else
  fail "Credential issuance failed — response: $CRED_RESPONSE"
  CREDENTIAL_HASH=""
fi

# Step 3: Proof relay
if [ -n "$CREDENTIAL_HASH" ]; then
  PROOF_RESPONSE=$(curl -sf -X POST "$BASE_URL/proof/relay" \
    -H "Content-Type: application/json" \
    -d "{\"proof\":\"0xabcd\",\"publicInputs\":{\"nullifier\":\"0x$CREDENTIAL_HASH\",\"issuerPubkeyHash\":\"0x00\",\"paymentAsset\":\"USDC\",\"amlThreshold\":10000,\"corridorId\":\"0x00\",\"allowedJurisdictionsRoot\":\"0x00\"}}" 2>/dev/null || echo "")

  if echo "$PROOF_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('verified') == True" 2>/dev/null; then
    pass "Proof relay returned verified: true"
    NULLIFIER=$(echo "$PROOF_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['nullifier'])")
  else
    fail "Proof relay failed — response: $PROOF_RESPONSE"
    NULLIFIER=""
  fi
else
  fail "Skipped proof relay — no credential hash"
  NULLIFIER=""
fi

# Step 4: Nullifier check
if [ -n "$NULLIFIER" ]; then
  NULLIFIER_RESPONSE=$(curl -sf "$BASE_URL/nullifier/$NULLIFIER" 2>/dev/null || echo "")
  if echo "$NULLIFIER_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('used') == True" 2>/dev/null; then
    pass "Nullifier check returned used: true"
  else
    fail "Nullifier check failed — response: $NULLIFIER_RESPONSE"
  fi
else
  fail "Skipped nullifier check — no nullifier"
fi

# Step 5: Payment
PAYMENT_RESPONSE=$(curl -sf -X POST "$BASE_URL/payment/send" \
  -H "Content-Type: application/json" \
  -d "{\"fromAddress\":\"GAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQ\",\"toAddress\":\"GBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\",\"amount\":\"500\",\"asset\":\"XLM\",\"nullifier\":\"$NULLIFIER\"}" 2>/dev/null || echo "")

if echo "$PAYMENT_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('success') == True" 2>/dev/null; then
  pass "Payment returned success: true"
else
  fail "Payment failed — response: $PAYMENT_RESPONSE"
fi

echo
echo "Results: $((TOTAL - FAILED))/$TOTAL tests passed"
exit $FAILED
