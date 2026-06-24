#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  zkremit Verifier Contract Deployment${NC}"
echo -e "${YELLOW}========================================${NC}"

NETWORK="testnet"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        testnet|mainnet) NETWORK="$arg" ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: $0 [testnet|mainnet] [--dry-run]"
            echo ""
            echo "Options:"
            echo "  testnet       Deploy to Stellar testnet (default)"
            echo "  mainnet       Deploy to Stellar mainnet"
            echo "  --dry-run     Build and validate everything without submitting transactions"
            echo "  --help, -h    Show this help message"
            exit 0
            ;;
    esac
done

if [ "$NETWORK" != "testnet" ] && [ "$NETWORK" != "mainnet" ]; then
    echo -e "${RED}Error: Network must be 'testnet' or 'mainnet'${NC}"
    echo "Usage: $0 [testnet|mainnet] [--dry-run]"
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}⚠  DRY RUN MODE — No transactions will be submitted${NC}"
    echo
fi

if [ "$NETWORK" = "mainnet" ] && [ "$DRY_RUN" = false ]; then
    echo -e "${RED}⚠  DEPLOYING TO MAINNET${NC}"
    echo -e "${RED}   Type 'deploy mainnet' to confirm:${NC}"
    read -r CONFIRM
    if [ "$CONFIRM" != "deploy mainnet" ]; then
        echo -e "${RED}Deployment cancelled.${NC}"
        exit 0
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_DIR"

source .env 2>/dev/null || {
    echo -e "${RED}Error: .env not found at $PROJECT_DIR/.env${NC}"
    exit 1
}

echo -e "${GREEN}[1/8]${NC} Validating environment variables..."

if [ "$NETWORK" = "testnet" ]; then
    SECRET_KEY="${DEPLOYER_SECRET_KEY:-}"
    PUBLIC_KEY="${DEPLOYER_PUBLIC_KEY:-}"
    RPC_URL="${STELLAR_RPC_URL:-https://soroban-testnet.stellar.org}"
    PASSPHRASE="${STELLAR_PASSPHRASE:-Test SDF Network ; September 2015}"
    EXPLORER="https://stellar.expert/explorer/testnet"
else
    SECRET_KEY="${MAINNET_DEPLOYER_SECRET_KEY:-${DEPLOYER_SECRET_KEY:-}}"
    PUBLIC_KEY="${DEPLOYER_PUBLIC_KEY:-}"
    RPC_URL="${STELLAR_MAINNET_RPC_URL:-https://soroban.stellar.org}"
    PASSPHRASE="${STELLAR_MAINNET_PASSPHRASE:-Public Global Stellar Network ; September 2015}"
    EXPLORER="https://stellar.expert/explorer/public"
fi

if [ -z "$SECRET_KEY" ]; then
    echo -e "${RED}Error: DEPLOYER_SECRET_KEY not set in .env${NC}"
    exit 1
fi
if [ -z "$PUBLIC_KEY" ]; then
    echo -e "${RED}Error: DEPLOYER_PUBLIC_KEY not set in .env${NC}"
    exit 1
fi

echo -e "${GREEN}[2/8]${NC} Checking deployer XLM balance..."
BALANCE=$(curl -sf "https://horizon-$NETWORK.stellar.org/accounts/$PUBLIC_KEY" | python3 -c "import json,sys; data=json.load(sys.stdin); print([b['balance'] for b in data['balances'] if b['asset_type']=='native'][0])" 2>/dev/null || echo "0")

echo "   Deployer: $PUBLIC_KEY"
echo "   Balance: $BALANCE XLM"

if [ "$(echo "$BALANCE < 100" | bc -l 2>/dev/null || echo 1)" = "1" ]; then
    echo -e "${RED}Error: Deployer account has less than 100 XLM. Current balance: $BALANCE XLM${NC}"
    echo "   Fund it using: ./scripts/fund-testnet.sh"
    exit 1
fi

echo -e "${GREEN}[3/8]${NC} Building optimized WASM..."
cd "$PROJECT_DIR/contracts/verifier"
cargo build --target wasm32-unknown-unknown --release 2>&1 | tail -5

WASM_PATH="target/wasm32-unknown-unknown/release/verifier.wasm"
if [ ! -f "$WASM_PATH" ]; then
    echo -e "${RED}Error: WASM not found at $WASM_PATH${NC}"
    exit 1
fi

stellar contract optimize --wasm "$WASM_PATH" 2>&1 | tail -3
OPTIMIZED_WASM_PATH="target/wasm32-unknown-unknown/release/verifier.optimized.wasm"

echo -e "${GREEN}[4/8]${NC} Deploying contract to $NETWORK..."
if [ "$DRY_RUN" = true ]; then
    VERIFIER_CONTRACT_ID="CAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADRYRUN"
    echo -e "${YELLOW}   [DRY RUN] Would deploy contract.${NC}"
    echo "   Contract ID: $VERIFIER_CONTRACT_ID (dry-run placeholder)"
else
    VERIFIER_CONTRACT_ID=$(stellar contract deploy \
        --wasm "$OPTIMIZED_WASM_PATH" \
        --source "$SECRET_KEY" \
        --network "$NETWORK" 2>&1 | tail -1)

    if [ -z "$VERIFIER_CONTRACT_ID" ]; then
        echo -e "${RED}Error: Deployment failed${NC}"
        exit 1
    fi
    echo "   Contract ID: $VERIFIER_CONTRACT_ID"
fi

echo -e "${GREEN}[5/8]${NC} Reading and encoding verification key..."
VK_PATH="$PROJECT_DIR/circuits/target/vk"
if [ ! -f "$VK_PATH" ]; then
    echo -e "${YELLOW}Warning: VK not found at $VK_PATH. Using placeholder.${NC}"
    VK_B64="AAAAAA=="
else
    VK_B64=$(base64 -w 0 < "$VK_PATH")
fi

echo -e "${GREEN}[6/8]${NC} Fetching initial Merkle roots..."

JURIS_ROOT=$(curl -sf http://localhost:3000/merkle/jurisdiction-root 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
CORR_ROOT=$(curl -sf http://localhost:3000/merkle/corridor-root 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
REVOC_ROOT=$(curl -sf http://localhost:3000/merkle/revocation-root 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")

echo "   Jurisdictions root: $JURIS_ROOT"
echo "   Corridors root: $CORR_ROOT"
echo "   Revocation root: $REVOC_ROOT"

echo -e "${GREEN}[7/8]${NC} Initializing contract..."
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}   [DRY RUN] Would call initialize with:${NC}"
    echo "     --admin: $PUBLIC_KEY"
    echo "     --allowed_jurisdictions_root: $JURIS_ROOT"
    echo "     --approved_corridors_root: $CORR_ROOT"
    echo "     --revocation_root: $REVOC_ROOT"
else
    stellar contract invoke \
        --id "$VERIFIER_CONTRACT_ID" \
        --source "$SECRET_KEY" \
        --network "$NETWORK" \
        -- \
        initialize \
        --vk "$VK_B64" \
        --admin "$PUBLIC_KEY" \
        --allowed_jurisdictions_root "$JURIS_ROOT" \
        --approved_corridors_root "$CORR_ROOT" \
        --revocation_root "$REVOC_ROOT"
fi

echo -e "${GREEN}[8/8]${NC} Writing contract ID to .env..."
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}   [DRY RUN] Would write VERIFIER_CONTRACT_ID=$VERIFIER_CONTRACT_ID to .env${NC}"
else
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^VERIFIER_CONTRACT_ID=.*/VERIFIER_CONTRACT_ID=$VERIFIER_CONTRACT_ID/" "$PROJECT_DIR/.env"
    else
        sed -i "s/^VERIFIER_CONTRACT_ID=.*/VERIFIER_CONTRACT_ID=$VERIFIER_CONTRACT_ID/" "$PROJECT_DIR/.env"
    fi
fi

echo ""
echo -e "${GREEN}┌─────────────────────────────────────────────┐${NC}"
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}│  zkremit Verifier Deployment (DRY RUN)        │${NC}"
    echo -e "${YELLOW}│  Contract:  (not deployed — dry run)          │${NC}"
    echo -e "${YELLOW}│  Network:   $NETWORK${NC}"
    echo -e "${YELLOW}│  All build and validation steps passed        │${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────┘${NC}"
else
    echo -e "${GREEN}│  zkremit Verifier Deployed                  │${NC}"
    echo -e "${GREEN}│  Contract:  $VERIFIER_CONTRACT_ID${NC}"
    echo -e "${GREEN}│  Network:   $NETWORK${NC}"
    echo -e "${GREEN}│  Explorer:  $EXPLORER/contract/$VERIFIER_CONTRACT_ID${NC}"
    echo -e "${GREEN}└─────────────────────────────────────────────┘${NC}"
fi
