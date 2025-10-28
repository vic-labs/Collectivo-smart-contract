module collectivo::campaign;

use collectivo::collectivo::AdminCap;
use std::string::String;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::Coin;
use sui::dynamic_field as df;
use sui::event;
use sui::sui::SUI;
use sui::table::{Self, Table};

const EBelowMinimumContribution: u64 = 0;
const EInactiveCampaign: u64 = 1;
const ECampaignCompleted: u64 = 2;
const ENotCreator: u64 = 3;
const ENotContributor: u64 = 4;
const EAmountGreaterThanContribution: u64 = 5;

public enum CampaignStatus has copy, drop, store {
    Active,
    Completed,
}

public enum NFTStatus has copy, drop, store {
    Purchased,
    Listed,
    Delisted,
}

public enum NFTActionError has copy, drop, store {
    Listing,
    Purchasing,
    Delisting,
}

public struct ContributorInfo has drop, store {
    contributed_at: u64,
    amount: u64,
}

public struct NFT has drop, store {
    nft_id: ID,
    url: String,
    image_url: String,
    rank: u64,
    is_purchased: bool,
    is_listed: bool,
    nft_type: String,
    name: String,
}

public struct Campaign has key, store {
    id: UID,
    nft: NFT,
    description: String,
    target: u64,
    sui_raised: Balance<SUI>,
    min_contribution: u64,
    user_contributions: Table<address, ContributorInfo>,
    contributors: vector<address>,
    status: CampaignStatus,
    creator: address,
    created_at: u64,
}

// === EVENTS === //

public struct NewCampaignEvent has copy, drop {
    campaign_id: ID,
}

public struct CampaignDeletedEvent has copy, drop {
    campaign_id: ID,
}

public struct NewContributionEvent has copy, drop {
    campaign_id: ID,
    amount: u64,
    contributor: address,
    is_new: bool,
}

public struct CampaignCompletedEvent has copy, drop {
    campaign_id: ID,
}

public struct WithdrawEvent has copy, drop {
    campaign_id: ID,
    amount: u64,
    is_full_withdrawal: bool,
    contributor: address,
}

public struct NFTPurchasedEvent has copy, drop {
    campaign_id: ID,
}

public struct NFTListedEvent has copy, drop {
    campaign_id: ID,
}

public struct NFTDelistedEvent has copy, drop {
    campaign_id: ID,
}

public struct NFTActionErrorEvent has copy, drop {
    campaign_id: ID,
    error_type: NFTActionError,
}

public struct WalletAddressSetEvent has copy, drop {
    campaign_id: ID,
    wallet_address: address,
}

public fun create(
    nft_id: ID,
    url: String,
    image_url: String,
    rank: u64,
    name: String,
    nft_type: String,
    description: String,
    target: u64,
    min_contribution: u64,
    contribution: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let creator = ctx.sender();

    let mut campaign = Campaign {
        id: object::new(ctx),
        nft: NFT {
            nft_id,
            url,
            image_url,
            rank,
            name,
            is_purchased: false,
            is_listed: false,
            nft_type,
        },
        description,
        target,
        min_contribution,
        sui_raised: balance::zero<SUI>(),
        created_at: clock.timestamp_ms(),
        status: CampaignStatus::Active,
        user_contributions: table::new<address, ContributorInfo>(ctx),
        contributors: vector[],
        creator,
    };

    let campaign_id = campaign.id.to_inner();

    contribute(&mut campaign, contribution, clock, ctx);
    transfer::public_share_object(campaign);

    event::emit(NewCampaignEvent { campaign_id });
}

public fun delete(campaign: Campaign, ctx: &mut TxContext) {
    assert!(!(campaign.status == CampaignStatus::Completed), ECampaignCompleted);
    assert!(campaign.creator == ctx.sender(), ENotCreator);
    let campaign_id = campaign.id.to_inner();

    let Campaign { id, user_contributions, mut sui_raised, mut contributors, .. } = campaign;
    // refund all contributors
    while (sui_raised.value() > 0) {
        let contributor = contributors.pop_back();
        let contributor_info = user_contributions.borrow(contributor);
        let amount = contributor_info.amount;
        let sui_coin = sui_raised.split(amount).into_coin(ctx);
        transfer::public_transfer(sui_coin, contributor);
    };

    table::drop(user_contributions);
    balance::destroy_zero(sui_raised);
    object::delete(id);
    event::emit(CampaignDeletedEvent { campaign_id });
}

#[allow(lint(self_transfer))]
public fun contribute(
    campaign: &mut Campaign,
    coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(campaign.status == CampaignStatus::Active, EInactiveCampaign);

    let contribution_amount = coin.value();
    let is_new_contributor = !campaign.contributors.contains(&ctx.sender());
    let total_contributed = campaign.sui_raised.value();
    let user = ctx.sender();
    let campaign_id = campaign.id.to_inner();

    let mut contributor_info = ContributorInfo {
        contributed_at: clock.timestamp_ms(),
        amount: contribution_amount,
    };

    assert!(contribution_amount >= campaign.min_contribution, EBelowMinimumContribution);

    // If the user's deposit for some reason is more than the remaining amount to hit target, then we deposit only the needed amount and return the rest to the user
    if (contribution_amount > campaign.target - total_contributed) {
        let mut deposit_coin = coin;
        let needed_deposit_coin = deposit_coin.split(campaign.target - total_contributed, ctx);
        let deposit_balance = needed_deposit_coin.into_balance();
        contributor_info.amount = deposit_balance.value();

        // update campaign funds
        campaign.sui_raised.join(deposit_balance);
        // return the rest to the user
        transfer::public_transfer(deposit_coin, user);
    } else {
        campaign.sui_raised.join(coin.into_balance());
    };

    if (is_new_contributor) {
        campaign.user_contributions.add(user, contributor_info);
        campaign.contributors.push_back(user);

        event::emit(NewContributionEvent {
            campaign_id,
            amount: contribution_amount,
            contributor: user,
            is_new: true,
        });
    } else {
        let curr_contribution_info = campaign.user_contributions.borrow_mut(user);
        curr_contribution_info.amount = contributor_info.amount + curr_contribution_info.amount;
        curr_contribution_info.contributed_at = contributor_info.contributed_at;

        event::emit(NewContributionEvent {
            campaign_id,
            amount: contributor_info.amount,
            contributor: user,
            is_new: false,
        });
    };

    if (campaign.sui_raised.value() == campaign.target) {
        campaign.status = CampaignStatus::Completed;
        event::emit(CampaignCompletedEvent { campaign_id });
    }
}

#[allow(lint(self_transfer))]
public fun withdraw(campaign: &mut Campaign, amount: u64, ctx: &mut TxContext) {
    assert!(campaign.status == CampaignStatus::Active, EInactiveCampaign);
    let user = ctx.sender();
    assert!(campaign.contributors.contains(&user), ENotContributor);
    let user_contribution = get_user_contribution(campaign, user);
    assert!(user_contribution.amount > 0, ENotContributor);
    assert!(amount <= user_contribution.amount, EAmountGreaterThanContribution);
    let campaign_id = campaign.id.to_inner();
    let is_full_withdrawal = amount == user_contribution.amount;

    let coin_balance_to_withdraw = campaign.sui_raised.split(amount);
    transfer::public_transfer(coin_balance_to_withdraw.into_coin(ctx), user);

    if (is_full_withdrawal) {
        campaign.user_contributions.remove(user);
        let (_, index) = campaign.contributors.index_of(&user);
        campaign.contributors.remove(index);
    } else {
        let user_contribution_info = campaign.user_contributions.borrow_mut(user);
        user_contribution_info.amount = user_contribution_info.amount - amount;
    };
    event::emit(WithdrawEvent {
        campaign_id,
        amount,
        is_full_withdrawal,
        contributor: user,
    });
}

public fun set_nft_status(
    campaign: &mut Campaign,
    status: NFTStatus,
    _cap: &AdminCap,
    nft_id: ID,
    image_url: String,
    url: String,
    rank: u64,
    name: String,
) {
    let campaign_id = campaign.id.to_inner();
    let is_purchased = status == NFTStatus::Purchased;
    let is_listed = status == NFTStatus::Listed;
    let is_delisted = status == NFTStatus::Delisted;
    if (is_purchased && !campaign.nft.is_purchased) {
        campaign.nft.is_purchased = is_purchased;
    };
    campaign.nft.is_listed = is_listed;
    campaign.nft.nft_id = nft_id;
    campaign.nft.image_url = image_url;
    campaign.nft.url = url;
    campaign.nft.rank = rank;
    campaign.nft.name = name;

    if (is_purchased) {
        event::emit(NFTPurchasedEvent { campaign_id });
    } else if (is_listed) {
        event::emit(NFTListedEvent { campaign_id });
    } else if (is_delisted) {
        event::emit(NFTDelistedEvent { campaign_id });
    }
}

public fun set_nft_status_error(
    campaign: &mut Campaign,
    error_type: NFTActionError,
    _cap: &AdminCap,
) {
    let campaign_id = campaign.id.to_inner();
    event::emit(NFTActionErrorEvent { campaign_id, error_type });
}

public fun create_wallet(campaign: &mut Campaign, address: address, _cap: &AdminCap) {
    df::add(&mut campaign.id, b"wallet", address);
    event::emit(WalletAddressSetEvent {
        campaign_id: campaign.id.to_inner(),
        wallet_address: address,
    });
}

public fun get_wallet(campaign: &mut Campaign): &address {
    df::borrow(&campaign.id, b"wallet")
}

public fun get_user_contribution(self: &Campaign, user: address): &ContributorInfo {
    self.user_contributions.borrow(user)
}

public fun contributor_amount(info: &ContributorInfo): u64 {
    info.amount
}

public fun sui_raised(self: &Campaign): &Balance<SUI> {
    &self.sui_raised
}

public fun target(self: &Campaign): u64 {
    self.target
}

public fun contributors_count(self: &Campaign): u64 {
    self.contributors.length()
}

public fun is_contributor(self: &Campaign, user: address): bool {
    self.contributors.contains(&user)
}

public fun is_completed(self: &Campaign): bool {
    self.status == CampaignStatus::Completed
}

public fun nft_is_purchased(self: &Campaign): bool {
    self.nft.is_purchased
}

public fun nft_is_listed(self: &Campaign): bool {
    self.nft.is_listed
}

public fun nft_is_delisted(self: &Campaign): bool {
    self.nft.is_purchased && !self.nft.is_listed
}

public fun id(self: &Campaign): ID {
    self.id.to_inner()
}

public(package) fun get_voting_weight(self: &Campaign, user: address): u64 {
    // Get user's contribution weight over 100
    let user_contribution = self.user_contributions.borrow(user).amount;

    // Calculate weight: (contribution * 100) / target
    // Multiply first to maintain precision
    (user_contribution * 100) / self.target
}

#[test_only]
public fun create_nft_status_purchased(): NFTStatus {
    NFTStatus::Purchased
}

#[test_only]
public fun create_nft_status_listed(): NFTStatus {
    NFTStatus::Listed
}

#[test_only]
public fun create_nft_status_delisted(): NFTStatus {
    NFTStatus::Delisted
}
