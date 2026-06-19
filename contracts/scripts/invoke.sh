#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

source .env 2>/dev/null || {
    echo -e "${RED}Error: .env not found${NC}"
    exit 1
}

NETWORK="${STELLAR_NETWORK:-testnet}"
CONTRACT_ID="${VERIFIER_CONTRACT_ID:-}"
SOURCE="${DEPLOYER_SECRET_KEY:-}"

if [ -z "$CONTRACT_ID" ]; then
    echo -e "${RED}Error: VERIFIER_CONTRACT_ID not set in .env${NC}"
    echo "   Run ./contracts/scripts/deploy.sh first"
    exit 1
fi

if [ -z "$SOURCE" ]; then
    echo -e "${RED}Error: DEPLOYER_SECRET_KEY not set in .env${NC}"
    exit 1
fi

COMMAND="${1:-help}"

case "$COMMAND" in
    is_nullifier_used)
        NULLIFIER="${2:-}"
        if [ -z "$NULLIFIER" ]; then
            echo -e "${RED}Usage: $0 is_nullifier_used --nullifier <hex>${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Checking nullifier: $NULLIFIER${NC}"
        stellar contract invoke \
            --id "$CONTRACT_ID" \
            --source "$SOURCE" \
            --network "$NETWORK" \
            -- \
            is_nullifier_used \
            --nullifier "$NULLIFIER"
        ;;

    get_verifier_key)
        echo -e "${YELLOW}Fetching verifier key...${NC}"
        stellar contract invoke \
            --id "$CONTRACT_ID" \
            --source "$SOURCE" \
            --network "$NETWORK" \
            -- \
            get_verifier_key
        ;;

    get_compliance_record)
        NULLIFIER="${2:-}"
        if [ -z "$NULLIFIER" ]; then
            echo -e "${RED}Usage: $0 get_compliance_record --nullifier <hex>${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Fetching compliance record for nullifier: $NULLIFIER${NC}"
        stellar contract invoke \
            --id "$CONTRACT_ID" \
            --source "$SOURCE" \
            --network "$NETWORK" \
            -- \
            get_compliance_record \
            --nullifier "$NULLIFIER"
        ;;

    update_roots)
        REVOC_ROOT="${2:-}"
        CORR_ROOT="${3:-}"
        JURIS_ROOT="${4:-}"
        if [ -z "$REVOC_ROOT" ] || [ -z "$CORR_ROOT" ] || [ -z "$JURIS_ROOT" ]; then
            echo -e "${RED}Usage: $0 update_roots --revocation-root <hex> --corridors-root <hex> --jurisdictions-root <hex>${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Updating Merkle roots...${NC}"
        echo "   Revocation root: $REVOC_ROOT"
        echo "   Corridors root: $CORR_ROOT"
        echo "   Jurisdictions root: $JURIS_ROOT"
        stellar contract invoke \
            --id "$CONTRACT_ID" \
            --source "$SOURCE" \
            --network "$NETWORK" \
            -- \
            update_roots \
            --caller "$(stellar address --source "$SOURCE" --network "$NETWORK")" \
            --new_revocation_root "$REVOC_ROOT" \
            --new_approved_corridors_root "$CORR_ROOT" \
            --new_allowed_jurisdictions_root "$JURIS_ROOT"
        ;;

    help|*)
        echo "zkremit Soroban Verifier — Invocation Script"
        echo ""
        echo "Usage:"
        echo "  $0 is_nullifier_used --nullifier <hex>"
        echo "      Check if a nullifier has been used"
        echo ""
        echo "  $0 get_verifier_key"
        echo "      Fetch the stored verification key"
        echo ""
        echo "  $0 get_compliance_record --nullifier <hex>"
        echo "      Fetch the ComplianceRecord for a nullifier"
        echo ""
        echo "  $0 update_roots --revocation-root <hex> --corridors-root <hex> --jurisdictions-root <hex>"
        echo "      Update Merkle roots (admin only)"
        echo ""
        echo "Environment:"
        echo "  NETWORK (from .env): $NETWORK"
        echo "  CONTRACT_ID (from .env): $CONTRACT_ID"
        ;;
esac
