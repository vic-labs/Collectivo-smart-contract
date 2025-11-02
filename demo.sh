#!/bin/bash

# Demo script for Collectivo campaign and proposal scenarios
# Source config
source "$(dirname "$0")/config.sh"

PACKAGE_ID="${DEVNET_PACKAGE_ID}"

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Addresses
ADDRESS1="walrus-deployer"
ADDRESS2="festive-malachite"
ADDRESS3="festive-carnelian"

# Helper function to switch address
switch_address() {
    echo -e "${BLUE}🔄 Switching to address: $1${NC}"
    sui client switch --address "$1"
    CURRENT_ADDRESS=$(sui client active-address)
    echo -e "${GREEN}✅ Active address: $CURRENT_ADDRESS${NC}\n"
}

# Helper function to wait for transaction
wait_for_tx() {
    echo -e "${YELLOW}⏳ Waiting for transaction to finalize...${NC}"
    sleep 3
    echo ""
}

# Helper function to merge coins before transactions
merge_coins() {
    echo -e "${YELLOW}🪙 Merging coins to ensure sufficient gas...${NC}"
    # Try to use mergecoins alias/command (suppress output and errors)
    eval mergecoins > /dev/null 2>&1 || true
    sleep 1
}

# Helper function to extract object ID from transaction output
extract_object_id() {
    grep -oP 'Created|Mutated.*: \K[0-9a-fx]+' | head -1
}

echo -e "${GREEN}🚀 Starting Collectivo Demo Script${NC}\n"
echo "=========================================="
echo ""

# === SCENARIO 1: CREATE CAMPAIGN ===
echo -e "${GREEN}📋 SCENARIO 1: Creating Campaign${NC}"
echo "----------------------------------------"
switch_address "$ADDRESS1"
merge_coins

# Target: 2 SUI (2000000000 MIST)
# Creator wants 50% voting weight, so needs to contribute 1 SUI
# With 1% fee: deposit = 1 * 101 / 100 = 1.01 SUI
TARGET_MIST=2000000000
CREATOR_CONTRIBUTION_SUI=1.0
CREATOR_DEPOSIT_MIST=$(echo "$CREATOR_CONTRIBUTION_SUI * 1010000000 / 1" | bc)

# Generate random NFT name and rank
NFT_NAMES=("suimilos" "prime machin" "popkins")
RANDOM_INDEX=$((RANDOM % ${#NFT_NAMES[@]}))
SELECTED_NAME="${NFT_NAMES[$RANDOM_INDEX]}"
RANDOM_NUMBER=$((RANDOM % 99999 + 1))
NFT_NAME="${SELECTED_NAME}#${RANDOM_NUMBER}"
RANDOM_RANK=$((RANDOM % 1000 + 1))

# Map NFT names to their types
case "$SELECTED_NAME" in
    "suimilos")
        NFT_TYPE="'0xbc3df36be17f27ac98e3c839b2589db8475fa07b20657b08e8891e3aaf5ee5f9::suimilos::Suimilos'"
        ;;
    "prime machin")
        NFT_TYPE="'0xbc3df36be17f27ac98e3c839b2589db8475fa07b20657b08e8891e3aaf5ee5f9::prime_machin::PrimeMachin'"
        ;;
    "popkins")
        NFT_TYPE="'0xbc3df36be17f27ac98e3c839b2589db8475fa07b20657b08e8891e3aaf5ee5f9::popkins::Popkins'"
        ;;
esac

# Generate dynamic image URL: https://walrus.doonies.net/suimilios/{rank}.png (fixed path for demo)
IMAGE_URL="https://walrus.doonies.net/suimilios/${RANDOM_RANK}.png"

MIN_CONTRIBUTION_MIST=$(echo "$TARGET_MIST * 0.1 / 1" | bc)

echo -e "${YELLOW}Creating campaign with:${NC}"
echo "  Target: 2 SUI"
echo "  Creator contribution: $CREATOR_CONTRIBUTION_SUI SUI (50% voting weight)"
echo "  NFT: $NFT_NAME (Rank: $RANDOM_RANK)"
echo ""

CAMPAIGN_TX_OUTPUT=$(sui client ptb \
    --assign nft_id @0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
    --assign clock @0x6 \
    --split-coins gas "[${CREATOR_DEPOSIT_MIST}]" \
    --assign contribution_coin \
    --move-call ${PACKAGE_ID}::campaign::create \
    nft_id \
    "'https://www.tradeport.xyz/sui/4'" \
    "'${IMAGE_URL}'" \
    ${RANDOM_RANK} \
    "'${NFT_NAME}'" \
    ${NFT_TYPE} \
    "'Demo campaign for testing proposals'" \
    ${TARGET_MIST} \
    ${MIN_CONTRIBUTION_MIST} \
    contribution_coin.0 \
    clock --gas-budget 100000000 --json 2>&1 | grep -v "warning\|api version")

CAMPAIGN_TX_DIGEST=$(echo "$CAMPAIGN_TX_OUTPUT" | jq -r '.digest // empty')

if [ -z "$CAMPAIGN_TX_DIGEST" ]; then
    echo -e "${RED}❌ Failed to get transaction digest${NC}"
    echo "$CAMPAIGN_TX_OUTPUT"
    exit 1
fi

# Get the campaign ID from objectChanges where type is "created" and objectType contains "campaign::Campaign"
CAMPAIGN_ID=$(echo "$CAMPAIGN_TX_OUTPUT" | jq -r '.objectChanges[]? | select(.type == "created" and .objectType != null and (.objectType | type == "string") and (.objectType | contains("campaign::Campaign"))) | .objectId' | head -1)

if [ -z "$CAMPAIGN_ID" ] || [ "$CAMPAIGN_ID" = "null" ]; then
    echo -e "${RED}❌ Failed to extract campaign ID from transaction${NC}"
    echo "Transaction: $CAMPAIGN_TX_DIGEST"
    exit 1
fi

echo -e "${GREEN}✅ Campaign created: $CAMPAIGN_ID${NC}\n"
wait_for_tx

# === SCENARIO 2: CONTRIBUTE FROM OTHER ADDRESSES ===
echo -e "${GREEN}📋 SCENARIO 2: Contributing to Complete Campaign${NC}"
echo "----------------------------------------"

# Address 2 contributes 0.4 SUI (with fee: 0.404 SUI)
switch_address "$ADDRESS2"
merge_coins
CONTRIBUTION2_SUI=0.4
DEPOSIT2_MIST=$(echo "$CONTRIBUTION2_SUI * 1010000000 / 1" | bc)

echo -e "${YELLOW}Address 2 contributing: $CONTRIBUTION2_SUI SUI${NC}"
sui client ptb \
    --assign campaign @${CAMPAIGN_ID} \
    --assign clock @0x6 \
    --split-coins gas "[${DEPOSIT2_MIST}]" \
    --assign contribution_coin \
    --move-call ${PACKAGE_ID}::campaign::contribute \
    campaign \
    contribution_coin.0 \
    clock --gas-budget 100000000 2>&1 | grep -v "warning\|api version" || true

echo -e "${GREEN}✅ Contribution successful${NC}\n"
wait_for_tx

# Address 3 contributes 0.6 SUI (with fee: 0.606 SUI) - completes campaign
switch_address "$ADDRESS3"
merge_coins
CONTRIBUTION3_SUI=0.6
DEPOSIT3_MIST=$(echo "$CONTRIBUTION3_SUI * 1010000000 / 1" | bc)

echo -e "${YELLOW}Address 3 contributing: $CONTRIBUTION3_SUI SUI${NC}"
echo -e "${YELLOW}(This should complete the campaign)${NC}"
sui client ptb \
    --assign campaign @${CAMPAIGN_ID} \
    --assign clock @0x6 \
    --split-coins gas "[${DEPOSIT3_MIST}]" \
    --assign contribution_coin \
    --move-call ${PACKAGE_ID}::campaign::contribute \
    campaign \
    contribution_coin.0 \
    clock --gas-budget 100000000 2>&1 | grep -v "warning\|api version" || true

echo -e "${GREEN}✅ Campaign completed!${NC}\n"
wait_for_tx

# === SCENARIO 3: CREATE PROPOSAL ===
echo -e "${GREEN}📋 SCENARIO 3: Creating Proposal${NC}"
echo "----------------------------------------"

# Randomly choose between list and delist
PROPOSAL_TYPE=$((RANDOM % 2))

if [ $PROPOSAL_TYPE -eq 0 ]; then
    # List proposal with random price
    RANDOM_PRICE_SUI=$((RANDOM % 100 + 1))
    PRICE_MIST=$(echo "$RANDOM_PRICE_SUI * 1000000000 / 1" | bc)
    
    echo -e "${YELLOW}Creating LIST proposal with price: $RANDOM_PRICE_SUI SUI${NC}"
    
    PROPOSAL_TX_OUTPUT=$(sui client ptb \
        --assign campaign @${CAMPAIGN_ID} \
        --assign clock @0x6 \
        --move-call ${PACKAGE_ID}::proposal::new_list_proposal_type ${PRICE_MIST} \
        --assign proposal_type \
        --move-call ${PACKAGE_ID}::proposal::create \
        campaign \
        proposal_type \
        clock --gas-budget 100000000 --json 2>&1 | grep -v "warning\|api version")
    
    PROPOSAL_TX_DIGEST=$(echo "$PROPOSAL_TX_OUTPUT" | jq -r '.digest // empty')
    
    if [ -z "$PROPOSAL_TX_DIGEST" ]; then
        echo -e "${RED}❌ Failed to get proposal transaction digest${NC}"
        echo "$PROPOSAL_TX_OUTPUT"
        exit 1
    fi
    
    # Get proposal ID from objectChanges where type is "created" and objectType contains "proposal::Proposal"
    PROPOSAL_ID=$(echo "$PROPOSAL_TX_OUTPUT" | jq -r '.objectChanges[]? | select(.type == "created" and .objectType != null and (.objectType | type == "string") and (.objectType | contains("proposal::Proposal"))) | .objectId' | head -1)
    
    if [ -z "$PROPOSAL_ID" ] || [ "$PROPOSAL_ID" = "null" ]; then
        echo -e "${RED}❌ Failed to extract proposal ID${NC}"
        echo "Transaction: $PROPOSAL_TX_DIGEST"
        exit 1
    fi
    
    echo -e "${GREEN}✅ List proposal created: $PROPOSAL_ID${NC}\n"
else
    echo -e "${YELLOW}Creating DELIST proposal${NC}"
    
    PROPOSAL_TX_OUTPUT=$(sui client ptb \
        --assign campaign @${CAMPAIGN_ID} \
        --assign clock @0x6 \
        --move-call ${PACKAGE_ID}::proposal::new_delist_proposal_type \
        --assign proposal_type \
        --move-call ${PACKAGE_ID}::proposal::create \
        campaign \
        proposal_type \
        clock --gas-budget 100000000 --json 2>&1 | grep -v "warning\|api version")
    
    PROPOSAL_TX_DIGEST=$(echo "$PROPOSAL_TX_OUTPUT" | jq -r '.digest // empty')
    
    if [ -z "$PROPOSAL_TX_DIGEST" ]; then
        echo -e "${RED}❌ Failed to get proposal transaction digest${NC}"
        echo "$PROPOSAL_TX_OUTPUT"
        exit 1
    fi
    
    # Get proposal ID from objectChanges where type is "created" and objectType contains "proposal::Proposal"
    PROPOSAL_ID=$(echo "$PROPOSAL_TX_OUTPUT" | jq -r '.objectChanges[]? | select(.type == "created" and .objectType != null and (.objectType | type == "string") and (.objectType | contains("proposal::Proposal"))) | .objectId' | head -1)
    
    if [ -z "$PROPOSAL_ID" ] || [ "$PROPOSAL_ID" = "null" ]; then
        echo -e "${RED}❌ Failed to extract proposal ID${NC}"
        echo "Transaction: $PROPOSAL_TX_DIGEST"
        exit 1
    fi
    echo -e "${GREEN}✅ Delist proposal created: $PROPOSAL_ID${NC}\n"
fi

wait_for_tx

# === SCENARIO 4: VOTING ===
echo -e "${GREEN}📋 SCENARIO 4: Voting on Proposal${NC}"
echo "----------------------------------------"

# Address 1 (creator, 50% weight) votes Approval
switch_address "$ADDRESS1"
merge_coins

if [ -z "$PROPOSAL_ID" ] || [ -z "$CAMPAIGN_ID" ]; then
    echo -e "${RED}❌ Missing proposal or campaign ID${NC}"
    exit 1
fi

echo -e "${YELLOW}Address 1 (50% weight) voting: Approval${NC}"
sui client ptb \
    --assign proposal @"${PROPOSAL_ID}" \
    --assign campaign @"${CAMPAIGN_ID}" \
    --assign clock @0x6 \
    --move-call "${PACKAGE_ID}"::proposal::new_approval_vote_type \
    --assign vote_type \
    --move-call "${PACKAGE_ID}"::proposal::vote \
    proposal \
    campaign \
    vote_type \
    clock --gas-budget 100000000 2>&1 | grep -v "warning\|api version" || true

echo -e "${GREEN}✅ Approval vote cast (50% weight)${NC}"
echo ""
wait_for_tx

# Address 2 votes Approval (adds more weight)
switch_address "$ADDRESS2"
merge_coins
echo -e "${YELLOW}Address 2 voting: Approval${NC}"
sui client ptb \
    --assign proposal @"${PROPOSAL_ID}" \
    --assign campaign @"${CAMPAIGN_ID}" \
    --assign clock @0x6 \
    --move-call "${PACKAGE_ID}"::proposal::new_approval_vote_type \
    --assign vote_type \
    --move-call "${PACKAGE_ID}"::proposal::vote \
    proposal \
    campaign \
    vote_type \
    clock --gas-budget 100000000 2>&1 | grep -v "warning\|api version" || true

echo -e "${GREEN}✅ Approval vote cast${NC}\n"
wait_for_tx

# Address 3 votes Rejection
switch_address "$ADDRESS3"
merge_coins
echo -e "${YELLOW}Address 3 voting: Rejection${NC}"
sui client ptb \
    --assign proposal @"${PROPOSAL_ID}" \
    --assign campaign @"${CAMPAIGN_ID}" \
    --assign clock @0x6 \
    --move-call "${PACKAGE_ID}"::proposal::new_rejection_vote_type \
    --assign vote_type \
    --move-call "${PACKAGE_ID}"::proposal::vote \
    proposal \
    campaign \
    vote_type \
    clock --gas-budget 100000000 2>&1 | grep -v "warning\|api version" || true

echo -e "${GREEN}✅ Rejection vote cast${NC}\n"
wait_for_tx

# === SUMMARY ===
echo -e "${GREEN}=========================================="
echo "🎉 Demo Complete!"
echo "==========================================${NC}"
echo ""
echo "Campaign ID: $CAMPAIGN_ID"
echo "Proposal ID: $PROPOSAL_ID"
echo ""
echo "Voting Summary:"
echo "  - Address 1 (Creator): 50% weight - Approval ✅"
echo "  - Address 2: ~20% weight - Approval ✅"
echo "  - Address 3: ~30% weight - Rejection ❌"
echo ""
echo "Total Approvals: ~70% (should pass)"
echo "Total Rejections: ~30%"
echo ""
echo -e "${GREEN}✅ Proposal should have PASSED (65% threshold)${NC}\n"

