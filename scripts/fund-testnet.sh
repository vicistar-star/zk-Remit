#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$ROOT_DIR/.env" ]; then
  error ".env file not found at $ROOT_DIR/.env. Run scripts/setup.sh first."
fi

source "$ROOT_DIR/.env"

if [ -z "${DEPLOYER_PUBLIC_KEY:-}" ]; then
  error "DEPLOYER_PUBLIC_KEY is not set in .env"
fi

info "Funding account: $DEPLOYER_PUBLIC_KEY"

FRIENDBOT_URL="https://friendbot.stellar.org?addr=$DEPLOYER_PUBLIC_KEY"
FRIENDBOT_RESPONSE=$(curl -sf "$FRIENDBOT_URL" 2>&1 || true)

if echo "$FRIENDBOT_RESPONSE" | grep -q "already exists"; then
  info "Account already funded — checking balance..."
elif echo "$FRIENDBOT_RESPONSE" | grep -q '"hash"'; then
  info "Account funded successfully!"
else
  warn "Friendbot response: $FRIENDBOT_RESPONSE"
fi

# Fetch and display balance
BALANCE=$(curl -sf "https://horizon-testnet.stellar.org/accounts/$DEPLOYER_PUBLIC_KEY" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); balances=[b for b in d['balances'] if b['asset_type']=='native']; print(balances[0]['balance'] if balances else '0')" 2>/dev/null || echo "unavailable")

info "XLM balance: $BALANCE"
