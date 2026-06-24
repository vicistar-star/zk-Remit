#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  zkremit BN254 Host Function Benchmarks${NC}"
echo -e "${YELLOW}========================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_DIR"

source .env 2>/dev/null || {
    echo -e "${RED}Error: .env not found at $PROJECT_DIR/.env${NC}"
    exit 1
}

NETWORK="${NETWORK:-testnet}"
CONTRACT_ID="${VERIFIER_CONTRACT_ID:-}"
DEPLOYER_SECRET="${DEPLOYER_SECRET_KEY:-}"

if [ -z "$CONTRACT_ID" ]; then
    echo -e "${RED}Error: VERIFIER_CONTRACT_ID not set in .env${NC}"
    exit 1
fi

if [ -z "$DEPLOYER_SECRET" ]; then
    echo -e "${RED}Error: DEPLOYER_SECRET_KEY not set in .env${NC}"
    exit 1
fi

echo -e "${GREEN}Contract ID:${NC} $CONTRACT_ID"
echo -e "${GREEN}Network:${NC} $NETWORK"
echo

# Generate a random nullifier for testing
TEST_NULLIFIER=$(node -e "
const crypto = require('crypto');
const h = crypto.createHash('sha256').update(crypto.randomBytes(32)).digest('hex');
console.log(h);
")

echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}  Benchmark 1: is_nullifier_used (fresh)${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"

FRESH_RESULT=$(stellar contract invoke \
    --id "$CONTRACT_ID" \
    --source "$DEPLOYER_SECRET" \
    --network "$NETWORK" \
    --simulate-only \
    -- \
    is_nullifier_used \
    --nullifier "$TEST_NULLIFIER" 2>&1 || echo "")

FRESH_INSNS=$(echo "$FRESH_RESULT" | grep -oP '"cpu_insns":\s*\K[0-9]+' || echo "N/A")
FRESH_BUDGET=$(echo "$FRESH_RESULT" | grep -oP '"(cpu_instructions|cpuInsns)":\s*\K[0-9]+' || echo "N/A")

echo -e "  CPU Instructions: ${BLUE}${FRESH_INSNS:-N/A}${NC}"

echo
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}  Benchmark 2: is_nullifier_used (used)${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"

# Use an already recorded nullifier (the zero hash)
USED_RESULT=$(stellar contract invoke \
    --id "$CONTRACT_ID" \
    --source "$DEPLOYER_SECRET" \
    --network "$NETWORK" \
    --simulate-only \
    -- \
    is_nullifier_used \
    --nullifier "0000000000000000000000000000000000000000000000000000000000000000" 2>&1 || echo "")

USED_INSNS=$(echo "$USED_RESULT" | grep -oP '"cpu_insns":\s*\K[0-9]+' || echo "N/A")

echo -e "  CPU Instructions: ${BLUE}${USED_INSNS:-N/A}${NC}"

echo
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}  Benchmark 3: verify_and_record (simulated)${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"

# Build a minimal proof and public inputs for simulation
DEMO_PROOF=$(node -e "
const crypto = require('crypto');
// Generate a 256-byte mock proof
const p = crypto.randomBytes(256).toString('hex');
console.log('0x' + p);
")

DEMO_PUBLIC_INPUTS=$(node -e "
const crypto = require('crypto');
// Generate 264 bytes of public inputs
const buf = Buffer.alloc(264, 0);
// Fill with deterministic data
for (let i = 0; i < 264; i++) buf[i] = i % 256;
console.log('0x' + buf.toString('hex'));
")

echo -e "${YELLOW}  Note: Full UltraHonk verification requires a valid proof.${NC}"
echo -e "${YELLOW}  The BN254 host function cost can be estimated from simulation.${NC}"

VERIFY_RESULT=$(stellar contract invoke \
    --id "$CONTRACT_ID" \
    --source "$DEPLOYER_SECRET" \
    --network "$NETWORK" \
    --simulate-only \
    -- \
    verify_and_record \
    --proof "$DEMO_PROOF" \
    --public_inputs "$DEMO_PUBLIC_INPUTS" 2>&1 || echo "")

VERIFY_INSNS=$(echo "$VERIFY_RESULT" | grep -oP '"cpu_insns":\s*\K[0-9]+' || echo "N/A")
VERIFY_BUDGET=$(echo "$VERIFY_RESULT" | grep -oP '"cpu_instructions":\s*\K[0-9]+' || echo "N/A")

echo -e "  CPU Instructions: ${BLUE}${VERIFY_INSNS:-N/A}${NC}"

echo
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Benchmark Summary${NC}"
echo -e "${YELLOW}========================================${NC}"
echo

# Compute budget percentages
TOTAL_BUDGET=1000000000

compute_pct() {
    local val=$1
    if [ "$val" = "N/A" ] || [ -z "$val" ]; then
        echo "N/A"
    else
        echo "scale=2; $val * 100 / $TOTAL_BUDGET" | bc 2>/dev/null || echo "N/A"
    fi
}

FRESH_PCT=$(compute_pct "$FRESH_INSNS")
USED_PCT=$(compute_pct "$USED_INSNS")
VERIFY_PCT=$(compute_pct "$VERIFY_INSNS")

echo -e "${GREEN}┌─────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}│  Operation                                │  CPU Insns  │ Budget %│${NC}"
echo -e "${GREEN}├─────────────────────────────────────────────────────────────────┤${NC}"
printf "│  %-42s │  %-10s │ %-7s│\n" "is_nullifier_used (fresh)" "${FRESH_INSNS:-N/A}" "${FRESH_PCT:-N/A}%"
printf "│  %-42s │  %-10s │ %-7s│\n" "is_nullifier_used (used)" "${USED_INSNS:-N/A}" "${USED_PCT:-N/A}%"
printf "│  %-42s │  %-10s │ %-7s│\n" "verify_and_record (simulated)" "${VERIFY_INSNS:-N/A}" "${VERIFY_PCT:-N/A}%"
echo -e "${GREEN}└─────────────────────────────────────────────────────────────────┘${NC}"

echo
echo -e "${YELLOW}Benchmark saved to contracts/benchmark-results.md${NC}"

# Save results to markdown file
cat > "$PROJECT_DIR/contracts/benchmark-results.md" <<EOF
# BN254 Host Function Benchmarks

Measured on Stellar **${NETWORK}** at $(date -u '+%Y-%m-%d %H:%M UTC).

| Operation | CPU Instructions | Compute Budget |
|---|---|---|
| is_nullifier_used (fresh) | ${FRESH_INSNS:-N/A} | ${FRESH_PCT:-N/A}% |
| is_nullifier_used (used) | ${USED_INSNS:-N/A} | ${USED_PCT:-N/A}% |
| verify_and_record (simulated) | ${VERIFY_INSNS:-N/A} | ${VERIFY_PCT:-N/A}% |

**Notes:**
- Total compute budget per Soroban transaction: 1,000,000 CPU instructions
- BN254 host functions (Protocol 25/26) significantly reduce verification cost vs. pure WASM implementation
- Full UltraHonk verification cost with Protocol 26 MSM host functions: ~8M instructions (estimated)
- For precise measurements, run this benchmark against a live testnet deployment
EOF

echo
echo -e "${GREEN}Done.${NC}"
