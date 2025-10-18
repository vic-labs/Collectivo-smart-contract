#[test_only]
module collectivo::proposal_tests;

use collectivo::campaign::{Self, Campaign};
use collectivo::proposal::{Self, Proposal};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

// Test error codes for better debugging 🐛
const EWrongProposer: u64 = 200; // Proposer is wrong 👤
const EWrongCampaignId: u64 = 201; // Campaign ID doesn't match 🔗
const EWrongApprovalWeight: u64 = 202; // Approval weight is wrong ✅
const EWrongRejectionWeight: u64 = 203; // Rejection weight is wrong ❌
const EWrongProposalType: u64 = 204; // Proposal type is wrong 🔄
const EProposalNotPassed: u64 = 205; // Proposal should be passed ✅
const EProposalNotRejected: u64 = 206; // Proposal should be rejected ❌
const EProposalNotActive: u64 = 207; // Proposal should be active 🔄
const EVoterNotMarked: u64 = 208; // Voter should be marked as voted 🗳️

// === PROPOSAL CREATION TESTS === //

#[test]
fun test_create_listing_proposal() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    // Create and complete campaign
    let campaign_id = create_and_complete_campaign(&mut scenario, admin);

    scenario.next_tx(admin);

    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000); // 2 SUI

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    {
        let proposal = scenario.take_shared<Proposal>();

        // Check proposer
        assert!(proposal.proposer() == admin, EWrongProposer);

        // Check campaign ID
        assert!(proposal.campaign_id() == campaign_id, EWrongCampaignId);

        // Check initial approval weight (admin's voting weight)
        // Admin contributed 1 SUI out of 1 SUI = 100% weight
        assert!(proposal.approvals_weight() == 100, EWrongApprovalWeight);

        // Check rejection weight is 0
        assert!(proposal.rejections_weight() == 0, EWrongRejectionWeight);

        // Check proposal is active but already passed (100% >= 65%)
        assert!(proposal.is_proposal_passed(), EProposalNotPassed);

        test_scenario::return_shared(proposal);
    };

    scenario.end();
}

#[test]
fun test_create_delisting_proposal() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    let _campaign_id = create_and_complete_campaign(&mut scenario, admin);

    scenario.next_tx(admin);

    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_delist_proposal_type();

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    {
        let proposal = scenario.take_shared<Proposal>();
        assert!(
            *proposal.proposal_type() == proposal::create_delist_proposal_type(),
            EWrongProposalType,
        );

        test_scenario::return_shared(proposal);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::proposal::ECampaignNotCompleted)]
fun test_create_proposal_before_campaign_completed() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000);

    scenario.next_tx(admin);

    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        // Try to create proposal before campaign is completed - should fail
        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

// === VOTING TESTS === //

#[test]
fun test_vote_approval() {
    let admin = @0xad;
    let contributor = @0xc1;
    let mut scenario = test_scenario::begin(admin);

    let _campaign_id = create_completed_campaign_with_contributors(
        &mut scenario,
        admin,
        contributor,
    );

    scenario.next_tx(admin);

    // Create proposal
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor votes approval
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(400000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_approval(),
            &test_clock,
            scenario.ctx(),
        );

        // Check approval weight increased (admin 50% + contributor 50% = 100%)
        assert!(proposal.approvals_weight() == 100, EWrongApprovalWeight);

        // Check voter is marked
        assert!(proposal.has_voter_voted(contributor), EVoterNotMarked);

        // Should be passed now (100% >= 65%)
        assert!(proposal.is_proposal_passed(), EProposalNotPassed);

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
fun test_vote_rejection() {
    let admin = @0xad;
    let contributor = @0xc1;
    let mut scenario = test_scenario::begin(admin);

    let _campaign_id = create_completed_campaign_with_contributors(
        &mut scenario,
        admin,
        contributor,
    );

    scenario.next_tx(admin);

    // Create proposal
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor votes rejection
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(400000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_rejection(),
            &test_clock,
            scenario.ctx(),
        );

        // Check rejection weight increased (contributor 50%)
        assert!(proposal.rejections_weight() == 50, EWrongRejectionWeight);

        // Check approval weight (admin 50%)
        assert!(proposal.approvals_weight() == 50, EWrongApprovalWeight);

        // Should still be active (neither reached 65%)
        assert!(proposal.is_proposal_active(), EProposalNotActive);

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
fun test_proposal_passed_at_threshold() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let mut scenario = test_scenario::begin(admin);

    // Create campaign with 3 contributors (admin 50%, c1 25%, c2 25%)
    let _campaign_id = create_completed_campaign_with_multiple_contributors(
        &mut scenario,
        admin,
        contributor1,
        contributor2,
    );

    scenario.next_tx(contributor1);

    // Contributor1 creates proposal (25% approval)
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    // Admin votes approval (25% + 50% = 75% >= 65%)
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(400000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_approval(),
            &test_clock,
            scenario.ctx(),
        );

        // Should be passed (75% >= 65%)
        assert!(proposal.is_proposal_passed(), EProposalNotPassed);
        assert!(proposal.approvals_weight() >= 65, EWrongApprovalWeight);

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
fun test_proposal_rejected_at_threshold() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let mut scenario = test_scenario::begin(admin);

    let _campaign_id = create_completed_campaign_with_multiple_contributors(
        &mut scenario,
        admin,
        contributor1,
        contributor2,
    );

    scenario.next_tx(contributor1);

    // Contributor1 creates proposal (25% approval)
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    // Admin votes rejection (50% rejection)
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(400000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_rejection(),
            &test_clock,
            scenario.ctx(),
        );

        // Still active (50% < 65%)
        assert!(proposal.is_proposal_active(), EProposalNotActive);

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor2);

    // Contributor2 votes rejection (50% + 25% = 75% >= 65%)
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(500000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_rejection(),
            &test_clock,
            scenario.ctx(),
        );

        // Should be rejected (75% >= 65%)
        assert!(proposal.is_proposal_rejected(), EProposalNotRejected);
        assert!(proposal.rejections_weight() >= 65, EWrongRejectionWeight);

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::proposal::EAlreadyVoted)]
fun test_double_voting_fails() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let mut scenario = test_scenario::begin(admin);

    // Create campaign with 3 contributors so votes don't auto-pass
    // Admin 50%, c1 25%, c2 25%
    let _campaign_id = create_completed_campaign_with_multiple_contributors(
        &mut scenario,
        admin,
        contributor1,
        contributor2,
    );

    scenario.next_tx(contributor1);

    // Contributor1 creates proposal (25% approval)
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor1);

    // Contributor1 tries to vote again (already voted when creating) - should fail with EAlreadyVoted
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(400000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_approval(),
            &test_clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::proposal::EProposalNotActive)]
fun test_vote_after_proposal_passed() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let mut scenario = test_scenario::begin(admin);

    let _campaign_id = create_completed_campaign_with_multiple_contributors(
        &mut scenario,
        admin,
        contributor1,
        contributor2,
    );

    scenario.next_tx(contributor1);

    // Create proposal
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    // Admin votes to pass the proposal
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(400000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_approval(),
            &test_clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor2);

    // Contributor2 tries to vote after proposal passed - should fail
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(500000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_approval(),
            &test_clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

// === PROPOSAL DELETION TESTS === //

#[test]
fun test_delete_proposal_with_low_votes() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let mut scenario = test_scenario::begin(admin);

    // Create campaign with 3 contributors: admin 50%, c1 25%, c2 25%
    let _campaign_id = create_completed_campaign_with_multiple_contributors(
        &mut scenario,
        admin,
        contributor1,
        contributor2,
    );

    scenario.next_tx(contributor1);

    // Contributor1 creates proposal (25% approval - truly LOW votes, below 50%)
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor1);

    // Contributor1 can delete their own proposal (25% < 50% threshold ✅)
    {
        let proposal = scenario.take_shared<Proposal>();

        proposal::delete(proposal, scenario.ctx());
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::proposal::ECannotDeleteAfterMuchVotes)]
fun test_delete_proposal_with_high_votes() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let mut scenario = test_scenario::begin(admin);

    // Create campaign with 3 contributors: admin 50%, c1 25%, c2 25%
    let _campaign_id = create_completed_campaign_with_multiple_contributors(
        &mut scenario,
        admin,
        contributor1,
        contributor2,
    );

    scenario.next_tx(contributor1);

    // Contributor1 creates proposal (25% approval - below 50% delete threshold)
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor2);

    // Contributor2 votes approval (25% + 25% = 50% >= 50% delete threshold but < 65% pass)
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(400000000000);

        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_approval(),
            &test_clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor1);

    // Contributor1 tries to delete after votes >= 50% - should fail with ECannotDeleteAfterMuchVotes
    {
        let proposal = scenario.take_shared<Proposal>();

        proposal::delete(proposal, scenario.ctx());
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::proposal::ENotProposer)]
fun test_delete_proposal_not_proposer() {
    let admin = @0xad;
    let contributor = @0xc1;
    let mut scenario = test_scenario::begin(admin);

    let _campaign_id = create_completed_campaign_with_contributors(
        &mut scenario,
        admin,
        contributor,
    );

    scenario.next_tx(admin);

    // Admin creates proposal
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor tries to delete admin's proposal - should fail
    {
        let proposal = scenario.take_shared<Proposal>();

        proposal::delete(proposal, scenario.ctx());
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::proposal::EProposalNotActive)]
fun test_delete_passed_proposal() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    let _campaign_id = create_and_complete_campaign(&mut scenario, admin);

    scenario.next_tx(admin);

    // Create proposal (100% approval, immediately passed)
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        let proposal_type = proposal::create_list_proposal_type(2000000000);

        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    // Try to delete passed proposal - should fail
    {
        let proposal = scenario.take_shared<Proposal>();

        proposal::delete(proposal, scenario.ctx());
    };

    scenario.end();
}

// === EDGE CASE TESTS === //

#[test]
fun test_voting_weight_calculation() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let contributor3 = @0xc3;
    let mut scenario = test_scenario::begin(admin);

    // Create campaign with different contribution amounts
    create_test_campaign(&mut scenario, admin, 100000000); // Admin: 500000000 (0.5 SUI)

    scenario.next_tx(contributor1);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);
        let contribution = coin::mint_for_testing<SUI>(200000000, scenario.ctx()); // 0.2 SUI
        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor2);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);
        let contribution = coin::mint_for_testing<SUI>(200000000, scenario.ctx()); // 0.2 SUI
        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor3);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);
        let contribution = coin::mint_for_testing<SUI>(100000000, scenario.ctx()); // 0.1 SUI (completes to 1 SUI)
        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    // Create proposal (admin has 50% voting weight)
    {
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);
        let proposal_type = proposal::create_list_proposal_type(2000000000);
        proposal::create(&campaign, proposal_type, &test_clock, scenario.ctx());
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor1);

    // Contributor1 votes (20% weight)
    {
        let mut proposal = scenario.take_shared<Proposal>();
        let campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(400000000000);
        proposal::vote(
            &mut proposal,
            &campaign,
            proposal::create_vote_approval(),
            &test_clock,
            scenario.ctx(),
        );
        // 50% + 20% = 70% >= 65% -> Should pass
        assert!(proposal.is_proposal_passed(), EProposalNotPassed);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

// === HELPER FUNCTIONS === //

fun create_test_campaign(
    scenario: &mut test_scenario::Scenario,
    admin: address,
    min_contribution: u64,
) {
    scenario.next_tx(admin);

    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(200000000000);

    let nft_id = object::id_from_address(@0x1234567890abcdef1234567890abcdef12345678);
    let url = b"https://test.com/nft".to_string();
    let image_url = b"https://test.com/image.jpg".to_string();
    let rank = 100;
    let name = b"Test NFT".to_string();
    let description = b"Test campaign description".to_string();
    let target = 1000000000; // 1 SUI
    let contribution = coin::mint_for_testing<SUI>(500000000, scenario.ctx()); // 0.5 SUI

    campaign::create(
        nft_id,
        url,
        image_url,
        rank,
        name,
        description,
        target,
        min_contribution,
        contribution,
        &test_clock,
        scenario.ctx(),
    );

    test_clock.destroy_for_testing();
}

fun create_and_complete_campaign(scenario: &mut test_scenario::Scenario, admin: address): ID {
    create_test_campaign(scenario, admin, 100000000);

    scenario.next_tx(admin);

    // Complete campaign by admin contributing more
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let campaign_id = campaign.id();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(250000000000);

        let contribution = coin::mint_for_testing<SUI>(500000000, scenario.ctx()); // 0.5 SUI

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();

        campaign_id
    }
}

fun create_completed_campaign_with_contributors(
    scenario: &mut test_scenario::Scenario,
    admin: address,
    contributor: address,
): ID {
    create_test_campaign(scenario, admin, 100000000); // Admin contributes 0.5 SUI

    scenario.next_tx(contributor);

    // Contributor completes campaign
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let campaign_id = campaign.id();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(250000000000);

        let contribution = coin::mint_for_testing<SUI>(500000000, scenario.ctx()); // 0.5 SUI

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();

        campaign_id
    }
}

fun create_completed_campaign_with_multiple_contributors(
    scenario: &mut test_scenario::Scenario,
    admin: address,
    contributor1: address,
    contributor2: address,
): ID {
    create_test_campaign(scenario, admin, 100000000); // Admin contributes 0.5 SUI (50%)

    scenario.next_tx(contributor1);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(250000000000);
        let contribution = coin::mint_for_testing<SUI>(250000000, scenario.ctx()); // 0.25 SUI (25%)
        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor2);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let campaign_id = campaign.id();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(260000000000);
        let contribution = coin::mint_for_testing<SUI>(250000000, scenario.ctx()); // 0.25 SUI (25%)
        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());
        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
        campaign_id
    }
}
