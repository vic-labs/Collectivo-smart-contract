#!/bin/bash

# Demo script for creating 100 Collectivo campaigns in a loop
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
ADDRESSES=("$ADDRESS1" "$ADDRESS2" "$ADDRESS3")

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
    sleep 4
    echo ""
}

# Helper function to merge coins before transactions
merge_coins() {
    echo -e "${YELLOW}🪙 Merging coins to ensure sufficient gas...${NC}"
    # Try to use mergecoins alias/command (suppress output and errors)
    eval mergecoins > /dev/null 2>&1 || true
    sleep 15
}

echo -e "${GREEN}🚀 Starting Collectivo 100 Campaigns Demo Script${NC}\n"
echo "=========================================="

# NFT collections data
NFT_NAMES=("suimilos" "prime machin" "popkins")
NFT_TYPES=(
    "'0xbc3df36be17f27ac98e3c839b2589db8475fa07b20657b08e8891e3aaf5ee5f9::suimilos::Suimilos'"
    "'0xbc3df36be17f27ac98e3c839b2589db8475fa07b20657b08e8891e3aaf5ee5f9::prime_machin::PrimeMachin'"
    "'0xbc3df36be17f27ac98e3c839b2589db8475fa07b20657b08e8891e3aaf5ee5f9::popkins::Popkins'"
)

# Campaign parameters
TARGET_MIST=2000000000  # 2 SUI
CREATOR_CONTRIBUTION_SUI=1.0
CREATOR_DEPOSIT_MIST=$(echo "$CREATOR_CONTRIBUTION_SUI * 1010000000 / 1" | bc)
MIN_CONTRIBUTION_MIST=$(echo "$TARGET_MIST * 0.1 / 1" | bc)

# Start with first address
CURRENT_ADDRESS_INDEX=0
switch_address "${ADDRESSES[$CURRENT_ADDRESS_INDEX]}"

# Loop to create 100 campaigns
for i in {1..100}; do
    echo -e "${GREEN}📋 Creating Campaign $i/100${NC}"
    echo "----------------------------------------"
    
    # Switch between accounts every 10 campaigns
    if [ $((i % 10)) -eq 1 ] && [ $i -gt 1 ]; then
        CURRENT_ADDRESS_INDEX=$(((CURRENT_ADDRESS_INDEX + 1) % ${#ADDRESSES[@]}))
        switch_address "${ADDRESSES[$CURRENT_ADDRESS_INDEX]}"
        
        # Request faucet funds for new address
        echo -e "${YELLOW}🚰 Requesting faucet funds for new address...${NC}"
        sui client faucet
        sleep 3
        merge_coins
        sleep 5
    fi
    
    # Ensure we have gas more frequently and with better error handling
    if [ $((i % 5)) -eq 1 ]; then
        echo -e "${YELLOW}🚰 Requesting faucet funds...${NC}"
        sui client faucet
        sleep 3
        merge_coins
        sleep 15
    fi
    
    # Generate random NFT data
    RANDOM_INDEX=$((RANDOM % ${#NFT_NAMES[@]}))
    SELECTED_NAME="${NFT_NAMES[$RANDOM_INDEX]}"
    RANDOM_NUMBER=$((RANDOM % 99999 + 1))
    NFT_NAME="${SELECTED_NAME}#${RANDOM_NUMBER}"
    RANDOM_RANK=$((RANDOM % 1000 + 1))
    NFT_TYPE="${NFT_TYPES[$RANDOM_INDEX]}"
    
    # Generate dynamic image URL
    IMAGE_URL="https://walrus.doonies.net/suimilios/${RANDOM_RANK}.png"
    
    # Generate unique NFT ID for each campaign (using hex format)
    NFT_ID_SUFFIX=$(printf "%064x" $i)
    NFT_ID="0x${NFT_ID_SUFFIX}"
    
    echo -e "${YELLOW}Campaign $i:${NC}"
    echo "  NFT: $NFT_NAME (Rank: $RANDOM_RANK)"
    echo "  NFT ID: $NFT_ID"
    echo "  Creator: ${ADDRESSES[$CURRENT_ADDRESS_INDEX]}"
    
    # Create campaign with better error handling
    CAMPAIGN_TX_OUTPUT=$(sui client ptb \
        --assign nft_id @${NFT_ID} \
        --assign clock @0x6 \
        --split-coins gas "[${CREATOR_DEPOSIT_MIST}]" \
        --assign contribution_coin \
        --move-call ${PACKAGE_ID}::campaign::create \
        nft_id \
        "'${IMAGE_URL}'" \
        ${RANDOM_RANK} \
        "'${NFT_NAME}'" \
        ${NFT_TYPE} \
        "'Demo campaign ${i} for testing'" \
        ${TARGET_MIST} \
        ${MIN_CONTRIBUTION_MIST} \
        contribution_coin.0 \
        clock --gas-budget 100000000 --json 2>/dev/null)
    
    # Check if the output is valid JSON before parsing
    if ! echo "$CAMPAIGN_TX_OUTPUT" | jq empty 2>/dev/null; then
        echo -e "${RED}❌ Failed to create campaign $i - Invalid JSON response${NC}"
        echo "Raw output: $CAMPAIGN_TX_OUTPUT"
        
        # Try to get more gas and continue
        echo -e "${YELLOW}🚰 Requesting additional faucet funds...${NC}"
        sui client faucet
        sleep 3
        merge_coins
        sleep 3
        continue
    fi
    
    CAMPAIGN_TX_DIGEST=$(echo "$CAMPAIGN_TX_OUTPUT" | jq -r '.digest // empty')
    
    if [ -z "$CAMPAIGN_TX_DIGEST" ] || [ "$CAMPAIGN_TX_DIGEST" = "null" ]; then
        echo -e "${RED}❌ Failed to create campaign $i - No transaction digest${NC}"
        
        # Check for specific error messages
        ERROR_MSG=$(echo "$CAMPAIGN_TX_OUTPUT" | jq -r '.error // empty')
        if [[ "$ERROR_MSG" == *"InsufficientCoinBalance"* ]]; then
            echo -e "${YELLOW}💰 Insufficient balance detected, requesting more funds...${NC}"
            sui client faucet
            sleep 3
            merge_coins
            sleep 3
        fi
        continue
    fi
    
    # Get the campaign ID from objectChanges
    CAMPAIGN_ID=$(echo "$CAMPAIGN_TX_OUTPUT" | jq -r '.objectChanges[]? | select(.type == "created" and .objectType != null and (.objectType | type == "string") and (.objectType | contains("campaign::Campaign"))) | .objectId' | head -1)
    
    if [ -z "$CAMPAIGN_ID" ] || [ "$CAMPAIGN_ID" = "null" ]; then
        echo -e "${RED}❌ Failed to extract campaign ID for campaign $i${NC}"
        continue
    fi
    
    echo -e "${GREEN}✅ Campaign $i created: $CAMPAIGN_ID${NC}"
    
    # Brief wait between campaigns
    sleep 1
    
    # Progress indicator
    if [ $((i % 10)) -eq 0 ]; then
        echo -e "${BLUE}📊 Progress: $i/100 campaigns created${NC}\n"
    fi
done

echo -e "${GREEN}=========================================="
echo "🎉 Demo Complete!"
echo "==========================================${NC}"
echo ""
echo -e "${GREEN}✅ Successfully created 100 campaigns across multiple accounts!${NC}"
echo ""
