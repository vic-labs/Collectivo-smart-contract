#!/bin/bash

# Source config (keep in sync with packages/shared-types/index.ts)
source "$(dirname "$0")/config.sh"

PACKAGE_ID="${DEVNET_PACKAGE_ID}"

create_campaign() {
    CONTRIBUTION_SUI=$1
    
    if [ -z "$CONTRIBUTION_SUI" ]; then
        echo "❌ Please provide contribution amount in SUI: bun run create-campaign <amount_in_sui>"
        exit 1
    fi
    
    # Convert SUI to MIST (1 SUI = 1,000,000,000 MIST)
    CONTRIBUTION_MIST=$(echo "$CONTRIBUTION_SUI * 1000000000 / 1" | bc)
    # Calculate deposit amount with 1% fee: deposit = contribution * 101 / 100
    DEPOSIT_MIST=$(echo "$CONTRIBUTION_MIST * 101 / 100" | bc)
    TARGET_MIST=2000000000  # 2 SUI
    MIN_CONTRIBUTION_MIST=$(echo "$TARGET_MIST * 0.1 / 1" | bc)  # 10% of target
    
    # Generate dynamic NFT name and rank
    NFT_NAMES=("suimilos" "prime machin" "popkins")
    RANDOM_INDEX=$((RANDOM % ${#NFT_NAMES[@]}))
    SELECTED_NAME="${NFT_NAMES[$RANDOM_INDEX]}"
    RANDOM_NUMBER=$((RANDOM % 99999 + 1))
    NFT_NAME="${SELECTED_NAME} #${RANDOM_NUMBER}"
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
    
    echo "🚀 Creating campaign..."
    echo "💰 Intended Contribution: ${CONTRIBUTION_SUI} SUI (${CONTRIBUTION_MIST} MIST)"
    echo "💵 Deposit Amount (with 1% fee): $(echo "scale=9; $DEPOSIT_MIST / 1000000000" | bc) SUI (${DEPOSIT_MIST} MIST)"
    echo "🎯 Target: 2 SUI (${TARGET_MIST} MIST)"
    echo "📊 Min Contribution: 0.2 SUI (${MIN_CONTRIBUTION_MIST} MIST) - 10% of target"
    echo "🎨 NFT Name: ${NFT_NAME}"
    echo "⭐ NFT Rank: ${RANDOM_RANK}"
    
    if sui client ptb \
        --assign nft_id @0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
        --assign clock @0x6 \
        --split-coins gas "[${DEPOSIT_MIST}]" \
        --assign contribution_coin \
        --move-call ${PACKAGE_ID}::campaign::create \
        nft_id \
        "'https://www.tradeport.xyz/sui/4'" \
        "'${IMAGE_URL}'" \
        ${RANDOM_RANK} \
        "'${NFT_NAME}'" \
        ${NFT_TYPE} \
        "'The most important NFT in the world'" \
        ${TARGET_MIST} \
        ${MIN_CONTRIBUTION_MIST} \
        contribution_coin.0 \
        clock --json; then
        echo "✅ Campaign created!"
    else
        echo "❌ Failed to create campaign"
        exit 1
    fi
}

contribute() {
    CAMPAIGN_ID=$1
    CONTRIBUTION_SUI=$2
    
    if [ -z "$CAMPAIGN_ID" ]; then
        echo "❌ Please provide campaign ID: ./scripts.sh contribute <campaign_id> <amount_in_sui>"
        exit 1
    fi
    
    if [ -z "$CONTRIBUTION_SUI" ]; then
        echo "❌ Please provide contribution amount in SUI: ./scripts.sh contribute <campaign_id> <amount_in_sui>"
        exit 1
    fi
    
    # Convert SUI to MIST (1 SUI = 1,000,000,000 MIST)
    CONTRIBUTION_MIST=$(echo "$CONTRIBUTION_SUI * 1000000000 / 1" | bc)
    # Calculate deposit amount with 1% fee: deposit = contribution * 101 / 100
    DEPOSIT_MIST=$(echo "$CONTRIBUTION_MIST * 101 / 100" | bc)
    
    echo "💰 Intended Contribution: ${CONTRIBUTION_SUI} SUI (${CONTRIBUTION_MIST} MIST)"
    echo "💵 Deposit Amount (with 1% fee): $(echo "scale=9; $DEPOSIT_MIST / 1000000000" | bc) SUI (${DEPOSIT_MIST} MIST)"
    echo "📝 Contributing to campaign ${CAMPAIGN_ID}..."
    
    if sui client ptb \
        --assign campaign @${CAMPAIGN_ID} \
        --assign clock @0x6 \
        --split-coins gas "[${DEPOSIT_MIST}]" \
        --assign contribution_coin \
        --move-call ${PACKAGE_ID}::campaign::contribute \
        campaign \
        contribution_coin.0 \
        clock; then
        echo "✅ Contribution successful!"
    else
        echo "❌ Failed to contribute"
        exit 1
    fi
}

withdraw() {
    CAMPAIGN_ID=$1
    AMOUNT_SUI=$2
    
    if [ -z "$CAMPAIGN_ID" ]; then
        echo "❌ Please provide campaign ID: ./scripts.sh withdraw <campaign_id> <amount_in_sui>"
        exit 1
    fi
    
    if [ -z "$AMOUNT_SUI" ]; then
        echo "❌ Please provide withdrawal amount in SUI: ./scripts.sh withdraw <campaign_id> <amount_in_sui>"
        exit 1
    fi
    
    # Convert SUI to MIST (1 SUI = 1,000,000,000 MIST)
    AMOUNT_MIST=$(echo "$AMOUNT_SUI * 1000000000 / 1" | bc)
    
    echo "💸 Withdrawing ${AMOUNT_SUI} SUI (${AMOUNT_MIST} MIST) from campaign ${CAMPAIGN_ID}..."
    
    if sui client ptb \
        --assign campaign @${CAMPAIGN_ID} \
        --move-call ${PACKAGE_ID}::campaign::withdraw \
        campaign \
        ${AMOUNT_MIST}; then
        echo "✅ Withdrawal successful!"
    else
        echo "❌ Failed to withdraw"
        exit 1
    fi
}

create_proposal() {
    CAMPAIGN_ID=$1
    
    if [ -z "$CAMPAIGN_ID" ]; then
        echo "❌ Please provide campaign ID: ./scripts.sh create-proposal <campaign_id>"
        exit 1
    fi
    
    # Randomly choose between list and delist (0 = list, 1 = delist)
    PROPOSAL_TYPE=$((RANDOM % 2))
    
    if [ $PROPOSAL_TYPE -eq 0 ]; then
        # Generate random proposal price (between 1-100 SUI) for list proposal
        RANDOM_PRICE_SUI=$((RANDOM % 100 + 1))
        PRICE_MIST=$(echo "$RANDOM_PRICE_SUI * 1000000000 / 1" | bc)
        
        echo "📋 Creating LIST proposal for campaign ${CAMPAIGN_ID}..."
        echo "💰 Proposal Price: ${RANDOM_PRICE_SUI} SUI (${PRICE_MIST} MIST)"
        
        if sui client ptb \
            --assign campaign @${CAMPAIGN_ID} \
            --assign clock @0x6 \
            --move-call ${PACKAGE_ID}::proposal::new_list_proposal_type ${PRICE_MIST} \
            --assign proposal_type \
            --move-call ${PACKAGE_ID}::proposal::create \
            campaign \
            proposal_type \
            clock; then
            echo "✅ List proposal created!"
        else
            echo "❌ Failed to create proposal"
            exit 1
        fi
    else
        echo "📋 Creating DELIST proposal for campaign ${CAMPAIGN_ID}..."
        
        if sui client ptb \
            --assign campaign @${CAMPAIGN_ID} \
            --assign clock @0x6 \
            --move-call ${PACKAGE_ID}::proposal::new_delist_proposal_type \
            --assign proposal_type \
            --move-call ${PACKAGE_ID}::proposal::create \
            campaign \
            proposal_type \
            clock; then
            echo "✅ Delist proposal created!"
        else
            echo "❌ Failed to create proposal"
            exit 1
        fi
    fi
}

case "$1" in
    create-campaign)
        create_campaign "$2"
        ;;
    contribute)
        contribute "$2" "$3"
        ;;
    withdraw)
        withdraw "$2" "$3"
        ;;
    create-proposal)
        create_proposal "$2"
        ;;
    *)
        echo "Usage:"
        echo "  ./scripts.sh create-campaign <contribution_amount_in_sui>"
        echo "  ./scripts.sh contribute <campaign_id> <amount_in_sui>"
        echo "  ./scripts.sh withdraw <campaign_id> <amount_in_sui>"
        echo "  ./scripts.sh create-proposal <campaign_id>"
        exit 1
        ;;
esac

