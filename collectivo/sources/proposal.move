module collectivo::proposal;

use collectivo::campaign::Campaign;
use sui::clock::Clock;
use sui::event;
use sui::vec_set::{Self, VecSet};

const EProposalNotActive: u64 = 1;
const EAlreadyVoted: u64 = 2;
const ENotProposer: u64 = 3;
const ECannotDeleteAfterMuchVotes: u64 = 4;
const ECampaignNotCompleted: u64 = 5;
const NFTNotPurchasedYet: u64 = 6;

const PASS_THRESHOLD: u64 = 65;
const CAN_DELETE_THRESHOLD: u64 = 50;

public enum ProposalType has copy, drop, store {
    List { price: u64 },
    Delist,
}

public enum ProposalStatus has copy, drop, store {
    Active,
    Passed,
    Rejected,
}

public enum VoteType has copy, drop, store {
    Approval,
    Rejection,
}

public struct VotersInfo has drop, store {
    weight: u64,
    voters: VecSet<address>,
}

public struct Proposal has key, store {
    id: UID,
    campaign_id: ID,
    proposer: address,
    proposal_type: ProposalType,
    approvals: VotersInfo,
    rejections: VotersInfo,
    status: ProposalStatus,
    created_at: u64,
    ended_at: u64,
}

public struct ProposalCreatedEvent has copy, drop {
    proposal_id: ID,
}

public struct ProposalDeletedEvent has copy, drop {
    proposal_id: ID,
}

public struct ProposalVotedEvent has copy, drop {
    proposal_id: ID,
    voter: address,
    vote_type: VoteType,
}

public struct ProposalPassedEvent has copy, drop {
    proposal_id: ID,
}

public struct ProposalRejectedEvent has copy, drop {
    proposal_id: ID,
}

public fun create(
    campaign: &Campaign,
    proposal_type: ProposalType,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(campaign.is_completed(), ECampaignNotCompleted);
    assert!(campaign.nft_is_purchased(), NFTNotPurchasedYet);

    let proposer = ctx.sender();
    let mut voters = vec_set::empty<address>();
    voters.insert(proposer);
    let proposer_weight = campaign.get_voting_weight(proposer);
    // let is_listing_proposal = is_listing_proposal(&proposal_type);

    let mut proposal = Proposal {
        id: object::new(ctx),
        campaign_id: campaign.id(),
        proposer,
        proposal_type,
        approvals: VotersInfo { weight: proposer_weight, voters },
        rejections: VotersInfo { weight: 0, voters: vec_set::empty<address>() },
        status: ProposalStatus::Active,
        created_at: clock.timestamp_ms(),
        ended_at: 0,
    };
    let proposal_id = proposal.id.to_inner();

    // After creating proposal, check if it immediately passes based on proposer's weight
    if (proposer_weight >= PASS_THRESHOLD) {
        proposal.status = ProposalStatus::Passed;
        proposal.ended_at = clock.timestamp_ms();
        event::emit(ProposalPassedEvent { proposal_id });
    };

    transfer::public_share_object(proposal);
    event::emit(ProposalCreatedEvent { proposal_id });

    event::emit(ProposalVotedEvent {
        proposal_id,
        voter: proposer,
        vote_type: VoteType::Approval,
    })
}

public fun delete(proposal: Proposal, ctx: &mut TxContext) {
    assert!(proposal.status == ProposalStatus::Active, EProposalNotActive);
    assert!(proposal.proposer == ctx.sender(), ENotProposer);
    let approvals_weight = proposal.approvals.weight;
    let rejections_weight = proposal.rejections.weight;
    assert!(
        approvals_weight < CAN_DELETE_THRESHOLD && rejections_weight < CAN_DELETE_THRESHOLD,
        ECannotDeleteAfterMuchVotes,
    );

    let Proposal { id, .. } = proposal;
    let proposal_id = id.to_inner();
    object::delete(id);
    event::emit(ProposalDeletedEvent { proposal_id });
}

public fun vote(
    proposal: &mut Proposal,
    campaign: &Campaign,
    vote_type: VoteType,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(proposal.status == ProposalStatus::Active, EProposalNotActive);
    assert!(!has_voted(proposal, ctx.sender()), EAlreadyVoted);
    let voter = ctx.sender();
    let voter_weight = campaign.get_voting_weight(voter);

    if (vote_type == VoteType::Approval) {
        proposal.approvals.weight = proposal.approvals.weight + voter_weight;
        proposal.approvals.voters.insert(voter);
    } else {
        proposal.rejections.weight = proposal.rejections.weight + voter_weight;
        proposal.rejections.voters.insert(voter);
    };

    event::emit(ProposalVotedEvent {
        proposal_id: proposal.id.to_inner(),
        voter,
        vote_type,
    });

    if (proposal.approvals.weight >= PASS_THRESHOLD) {
        proposal.status = ProposalStatus::Passed;
        proposal.ended_at = clock.timestamp_ms();
        event::emit(ProposalPassedEvent { proposal_id: proposal.id.to_inner() });
    } else if (proposal.rejections.weight >= PASS_THRESHOLD) {
        proposal.status = ProposalStatus::Rejected;
        proposal.ended_at = clock.timestamp_ms();
        event::emit(ProposalRejectedEvent { proposal_id: proposal.id.to_inner() });
    };
}

fun has_voted(proposal: &Proposal, voter: address): bool {
    proposal.approvals.voters.contains(&voter) || proposal.rejections.voters.contains(&voter)
}

public fun is_proposal_passed(self: &Proposal): bool {
    self.status == ProposalStatus::Passed
}

public fun is_proposal_active(self: &Proposal): bool {
    self.status == ProposalStatus::Active
}

public fun is_proposal_rejected(self: &Proposal): bool {
    self.status == ProposalStatus::Rejected
}

public fun proposer(self: &Proposal): address {
    self.proposer
}

public fun campaign_id(self: &Proposal): ID {
    self.campaign_id
}

public fun approvals_weight(self: &Proposal): u64 {
    self.approvals.weight
}

public fun rejections_weight(self: &Proposal): u64 {
    self.rejections.weight
}

public fun has_voter_voted(self: &Proposal, voter: address): bool {
    has_voted(self, voter)
}

public fun status(self: &Proposal): &ProposalStatus {
    &self.status
}

public fun proposal_type(self: &Proposal): &ProposalType {
    &self.proposal_type
}

public fun new_list_proposal_type(price: u64): ProposalType {
    ProposalType::List { price }
}

public fun new_delist_proposal_type(): ProposalType {
    ProposalType::Delist
}

public fun new_approval_vote_type(): VoteType {
    VoteType::Approval
}

public fun new_rejection_vote_type(): VoteType {
    VoteType::Rejection
}
