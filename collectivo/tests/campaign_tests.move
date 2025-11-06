#[test_only]
module collectivo::campaign_tests;

use collectivo::campaign::{Self, Campaign};
use collectivo::collectivo::{AdminCap, issue_admin_cap};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

// Test error codes for better debugging 🐛
const EWrongUserContribution: u64 = 101; // User contribution amount mismatch
const EWrongSuiRaisedAfterWithdrawal: u64 = 103; // sui_raised incorrect after withdrawal
const EWrongCoinValue: u64 = 104; // Returned coin value incorrect
const EWrongInitialBalance: u64 = 105; // Initial campaign balance wrong
const EWrongSuiRaisedAfterContribution: u64 = 107; // sui_raised wrong after contribution
const EUserStillInContributors: u64 = 108; // User should be removed from contributors
const EWrongContributorsCount: u64 = 109; // Contributors count is wrong
const EUserNotInContributors: u64 = 110; // User should still be in contributors
const EWrongUserContributionAfterPartialWithdrawal: u64 = 111; // Wrong contribution after partial withdrawal
const EWrongSuiRaisedAfterPartialWithdrawal: u64 = 112; // Wrong sui_raised after partial withdrawal
const ECampaignNotCompleted: u64 = 113; // Campaign should be completed
const EWrongTargetReached: u64 = 114; // Target amount should be reached exactly
const EWrongRefundAmount: u64 = 115; // Refund amount is incorrect 💰
const EWrongContributorRecordedAmount: u64 = 116; // Contributor's recorded amount is wrong 📝
const EWrongStatus: u64 = 119; // Campaign status is wrong 📊
const EWalletWrong: u64 = 121; // Wallet address is incorrect 🚫
const ENFTNotPurchased: u64 = 122; // NFT should be purchased ✅
const ENFTNotListed: u64 = 123; // NFT should be listed 📋
const ENFTStillListed: u64 = 124; // NFT should not be listed 🚫

// === CAMPAIGN CREATION TESTS === //

#[test]
fun test_create_campaign() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI min contribution

    scenario.next_tx(admin);

    {
        let campaign = scenario.take_shared<Campaign>();

        // Check initial sui_raised balance (admin deposited 505000000, after 1% fee = 500000000)
        let sui_raised = campaign.sui_raised().value();
        assert!(sui_raised == 500000000, EWrongInitialBalance);

        // Check campaign is active
        assert!(!campaign.is_completed(), EWrongStatus);

        // Check admin is a contributor
        assert!(campaign.is_contributor(admin), EUserNotInContributors);
        assert!(campaign.contributors_count() == 1, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::EBelowMinimumContribution)]
fun test_create_campaign_below_minimum() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    // Try to create campaign with contribution below minimum
    scenario.next_tx(admin);

    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(2000000000000);

    let nft_id = object::id_from_address(@0x1234567890abcdef1234567890abcdef12345678);
    let image_url = b"https://test.com/image.jpg".to_string();
    let rank = 100;
    let name = b"Test NFT".to_string();
    let nft_type = b"Test Type".to_string();
    let description = b"Test campaign description".to_string();
    let target = 1000000000; // 1 SUI
    let min_contribution = 100000000; // 0.1 SUI minimum
    let contribution = coin::mint_for_testing<SUI>(50000000, scenario.ctx()); // 0.05 SUI (below minimum)

    campaign::create(
        nft_id,
        image_url,
        rank,
        name,
        nft_type,
        description,
        target,
        min_contribution,
        contribution,
        &test_clock,
        scenario.ctx(),
    );

    test_clock.destroy_for_testing();
    scenario.end();
}

// === CONTRIBUTION TESTS === //

#[test]
fun test_successful_contribution() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    scenario.next_tx(contributor);

    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 303000000 to get 300000000 after fee (303 * 100/101 = 300)
        let contribution = coin::mint_for_testing<SUI>(303000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        // Check contributor's balance
        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(user_contribution.contributor_amount() == 300000000, EWrongUserContribution);

        // Check total sui_raised balance (admin 500000000 + contributor 300000000 = 800000000)
        assert!(campaign.sui_raised().value() == 800000000, EWrongSuiRaisedAfterContribution);

        // Check contributor is in list
        assert!(campaign.is_contributor(contributor), EUserNotInContributors);
        assert!(campaign.contributors_count() == 2, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
fun test_multiple_contributions_same_user() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    scenario.next_tx(contributor);

    // First contribution
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 101000000 to get 100000000 after fee
        let contribution = coin::mint_for_testing<SUI>(101000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Second contribution from same user
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        // Deposit 151500000 to get 150000000 after fee
        let contribution = coin::mint_for_testing<SUI>(151500000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        // Check accumulated contribution (100000000 + 150000000 = 250000000)
        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(user_contribution.contributor_amount() == 250000000, EWrongUserContribution);

        // Total should be admin 500000000 + contributor 250000000 = 750000000
        assert!(campaign.sui_raised().value() == 750000000, EWrongSuiRaisedAfterContribution);

        // Still 2 contributors (admin + contributor)
        assert!(campaign.contributors_count() == 2, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::EBelowMinimumContribution)]
fun test_contribution_below_minimum() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI minimum

    scenario.next_tx(contributor);

    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 50000000 (below minimum after fee)
        let contribution = coin::mint_for_testing<SUI>(50000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
fun test_excess_contribution_with_refund() {
    let admin = @0xad;
    let contributor = @0xc1;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI, target is 1 SUI

    scenario.next_tx(contributor);

    // Contributor tries to contribute but only 500000000 is needed to complete campaign
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 808000000 to get 800000000 after fee, but only 500000000 needed
        let contribution = coin::mint_for_testing<SUI>(808000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        // Check campaign is completed 🎯
        assert!(campaign.is_completed(), ECampaignNotCompleted);

        // Check target is exactly reached (not exceeded) ✅
        assert!(campaign.sui_raised().value() == campaign.target(), EWrongTargetReached);

        // Check exact target amount (1 SUI = 1000000000) 💯
        assert!(campaign.sui_raised().value() == 1000000000, EWrongSuiRaisedAfterContribution);

        // Check contributor's recorded amount is only what was actually deposited (500000000) 📝
        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(
            user_contribution.contributor_amount() == 500000000,
            EWrongContributorRecordedAmount,
        );

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Check that contributor received the excess amount back as refund 💰
    {
        let refund_coin = scenario.take_from_address<coin::Coin<SUI>>(contributor);
        assert!(refund_coin.value() == 300000000, EWrongRefundAmount);

        scenario.return_to_sender(refund_coin);
    };

    scenario.end();
}

#[test]
fun test_campaign_completion_exact_target() {
    let admin = @0xad;
    let contributor = @0xc1;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI, target is 1 SUI

    scenario.next_tx(contributor);

    // Contribute exactly the remaining amount
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 510100000 to get exactly 505000000 after fee (to complete campaign)
        let contribution = coin::mint_for_testing<SUI>(510100000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        // Check campaign is completed
        assert!(campaign.is_completed(), ECampaignNotCompleted);

        // Check target is exactly reached
        assert!(campaign.sui_raised().value() == campaign.target(), EWrongTargetReached);

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::EInactiveCampaign)]
fun test_contribute_after_campaign_completed() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI, target is 1 SUI

    scenario.next_tx(contributor1);

    // First contributor completes the campaign
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 510100000 to complete campaign
        let contribution = coin::mint_for_testing<SUI>(510100000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor2);

    // Second contributor tries to contribute after campaign is completed - should fail
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 202000000 to get 200000000 after fee
        let contribution = coin::mint_for_testing<SUI>(202000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

// === WITHDRAWAL TESTS === //

#[test]
fun test_successful_full_withdrawal() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    scenario.next_tx(contributor);

    // Contributor contributes
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 303000000 to get 300000000 after fee
        let contribution = coin::mint_for_testing<SUI>(303000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor withdraws full amount
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 300000000, scenario.ctx()); // Withdraw 0.3 SUI

        // Check contributor is removed
        assert!(!campaign.is_contributor(contributor), EUserStillInContributors);

        // Check total sui_raised (should be 500000000 from admin only)
        assert!(campaign.sui_raised().value() == 500000000, EWrongSuiRaisedAfterWithdrawal);

        // Check contributors count (should be 1 now, just admin)
        assert!(campaign.contributors_count() == 1, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
    };

    scenario.next_tx(contributor);

    // Check that contributor received their SUI back
    {
        let returned_coin = scenario.take_from_address<coin::Coin<SUI>>(contributor);
        assert!(returned_coin.value() == 300000000, EWrongCoinValue);

        scenario.return_to_sender(returned_coin);
    };

    scenario.end();
}

#[test]
fun test_partial_withdrawal() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    scenario.next_tx(contributor);

    // Contributor contributes
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 404000000 to get 400000000 after fee
        let contribution = coin::mint_for_testing<SUI>(404000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor withdraws partial amount (0.15 SUI out of 0.4 SUI)
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 150000000, scenario.ctx()); // Withdraw 0.15 SUI

        // Check contributor's remaining balance
        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(
            user_contribution.contributor_amount() == 250000000,
            EWrongUserContributionAfterPartialWithdrawal,
        );

        // Check total sui_raised (500000000 + 400000000 - 150000000 = 750000000)
        assert!(campaign.sui_raised().value() == 750000000, EWrongSuiRaisedAfterPartialWithdrawal);

        // Check contributor is still in the list
        assert!(campaign.is_contributor(contributor), EUserNotInContributors);

        // Check contributors count should still be 2
        assert!(campaign.contributors_count() == 2, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
    };

    scenario.next_tx(contributor);

    // Check that contributor received partial SUI back
    {
        let returned_coin = scenario.take_from_address<coin::Coin<SUI>>(contributor);
        assert!(returned_coin.value() == 150000000, EWrongCoinValue);

        scenario.return_to_sender(returned_coin);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::EAmountGreaterThanContribution)]
fun test_withdrawal_exceeds_contribution() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    scenario.next_tx(contributor);

    // Contributor contributes
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 202000000 to get 200000000 after fee
        let contribution = coin::mint_for_testing<SUI>(202000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Try to withdraw more than contributed - should fail
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 500000000, scenario.ctx()); // Try to withdraw 0.5 SUI

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::ENotContributor)]
fun test_non_contributor_withdrawal() {
    let admin = @0xad;
    let non_contributor = @0xba;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    scenario.next_tx(non_contributor);

    // Non-contributor tries to withdraw - should fail
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 100000000, scenario.ctx());

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::EInactiveCampaign)]
fun test_withdraw_after_campaign_completed() {
    let admin = @0xad;
    let contributor = @0xc1;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI, target is 1 SUI

    scenario.next_tx(contributor);

    // Contributor contributes but doesn't complete campaign yet
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 303000000 to get 300000000 after fee
        let contribution = coin::mint_for_testing<SUI>(303000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    // Admin contributes more to complete the campaign
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 510100000 to complete campaign
        let contribution = coin::mint_for_testing<SUI>(510100000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        assert!(campaign.is_completed(), ECampaignNotCompleted);

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor tries to withdraw after campaign is completed - should fail
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 100000000, scenario.ctx());

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::ERemainingAmountLessThanMinimumContribution)]
fun test_partial_withdrawal_below_minimum() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI minimum

    scenario.next_tx(contributor);

    // Contributor contributes exactly the minimum amount
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 101000000 to get exactly 100000000 after fee (minimum)
        let contribution = coin::mint_for_testing<SUI>(101000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Try to withdraw any amount - should fail because remaining would be below minimum
    {
        let mut campaign = scenario.take_shared<Campaign>();

        // Try to withdraw 50000000 (0.05 SUI) - remaining would be 50000000 < 100000000 minimum
        campaign::withdraw(&mut campaign, 50000000, scenario.ctx());

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
fun test_additional_contribution_below_minimum_from_existing() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI minimum

    scenario.next_tx(contributor);

    // First contribution (meets minimum)
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 101000000 to get 100000000 after fee (meets minimum)
        let contribution = coin::mint_for_testing<SUI>(101000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Second contribution below minimum (should succeed since existing contributor)
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        // Deposit 50500000 to get 50000000 after fee (below minimum but existing contributor)
        let contribution = coin::mint_for_testing<SUI>(50500000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        // Check total contribution (100000000 + 50000000 = 150000000)
        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(user_contribution.contributor_amount() == 150000000, EWrongUserContribution);

        // Total sui_raised should be admin 500000000 + contributor 150000000 = 650000000
        assert!(campaign.sui_raised().value() == 650000000, EWrongSuiRaisedAfterContribution);

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
fun test_full_withdrawal_from_existing_contributor() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI minimum

    scenario.next_tx(contributor);

    // Contributor makes initial contribution
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 202000000 to get 200000000 after fee
        let contribution = coin::mint_for_testing<SUI>(202000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Additional small contribution
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        // Deposit 50500000 to get 50000000 after fee
        let contribution = coin::mint_for_testing<SUI>(50500000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        // Total contribution should be 250000000
        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(user_contribution.contributor_amount() == 250000000, EWrongUserContribution);

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Full withdrawal
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 250000000, scenario.ctx()); // Withdraw full amount

        // Contributor should be removed from list
        assert!(!campaign.is_contributor(contributor), EUserStillInContributors);

        // Total sui_raised should be back to admin's 500000000
        assert!(campaign.sui_raised().value() == 500000000, EWrongSuiRaisedAfterWithdrawal);

        // Contributors count should be 1 (just admin)
        assert!(campaign.contributors_count() == 1, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
    };

    scenario.next_tx(contributor);

    // Check full amount was returned
    {
        let returned_coin = scenario.take_from_address<coin::Coin<SUI>>(contributor);
        assert!(returned_coin.value() == 250000000, EWrongCoinValue);
        scenario.return_to_sender(returned_coin);
    };

    scenario.end();
}

#[test]
fun test_multiple_partial_withdrawals_maintaining_minimum() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign_with_target(&mut scenario, admin, 100000000, 2000000000); // 2 SUI target

    scenario.next_tx(contributor);

    // Contributor makes large contribution
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 707000000 to get 700000000 after fee
        let contribution = coin::mint_for_testing<SUI>(707000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    // First partial withdrawal (leave above minimum)
    scenario.next_tx(contributor);
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 300000000, scenario.ctx()); // Withdraw 0.3 SUI, leave 400000000

        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(user_contribution.contributor_amount() == 400000000, EWrongUserContributionAfterPartialWithdrawal);

        assert!(campaign.sui_raised().value() == 900000000, EWrongSuiRaisedAfterPartialWithdrawal);
        assert!(campaign.is_contributor(contributor), EUserNotInContributors);
        assert!(campaign.contributors_count() == 2, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
    };

    // Second partial withdrawal (still above minimum)
    scenario.next_tx(contributor);
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 200000000, scenario.ctx()); // Withdraw 0.2 SUI, leave 200000000

        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(user_contribution.contributor_amount() == 200000000, EWrongUserContributionAfterPartialWithdrawal);

        assert!(campaign.sui_raised().value() == 700000000, EWrongSuiRaisedAfterPartialWithdrawal);
        assert!(campaign.is_contributor(contributor), EUserNotInContributors);
        assert!(campaign.contributors_count() == 2, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
    };

    // Third partial withdrawal (exactly at minimum - should succeed)
    scenario.next_tx(contributor);
    {
        let mut campaign = scenario.take_shared<Campaign>();

        campaign::withdraw(&mut campaign, 100000000, scenario.ctx()); // Withdraw 0.1 SUI, leave 100000000 (minimum)

        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(user_contribution.contributor_amount() == 100000000, EWrongUserContributionAfterPartialWithdrawal);

        assert!(campaign.sui_raised().value() == 600000000, EWrongSuiRaisedAfterPartialWithdrawal);
        assert!(campaign.is_contributor(contributor), EUserNotInContributors);
        assert!(campaign.contributors_count() == 2, EWrongContributorsCount);

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::ERemainingAmountLessThanMinimumContribution)]
fun test_withdrawal_below_minimum_after_multiple_withdrawals() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign_with_target(&mut scenario, admin, 100000000, 2000000000); // 2 SUI target

    scenario.next_tx(contributor);

    // Contributor makes large contribution
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 707000000 to get 700000000 after fee
        let contribution = coin::mint_for_testing<SUI>(707000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    // First three partial withdrawals to reach exactly minimum
    scenario.next_tx(contributor);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        campaign::withdraw(&mut campaign, 300000000, scenario.ctx());
        test_scenario::return_shared(campaign);
    };

    scenario.next_tx(contributor);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        campaign::withdraw(&mut campaign, 200000000, scenario.ctx());
        test_scenario::return_shared(campaign);
    };

    scenario.next_tx(contributor);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        campaign::withdraw(&mut campaign, 100000000, scenario.ctx());
        test_scenario::return_shared(campaign);
    };

    // Now try to withdraw more than remaining minimum - should fail
    scenario.next_tx(contributor);
    {
        let mut campaign = scenario.take_shared<Campaign>();

        // Try to withdraw 15000000 (0.015 SUI) when only 100000000 (0.1 SUI) remains
        // This would leave 85000000 < 100000000 minimum
        campaign::withdraw(&mut campaign, 15000000, scenario.ctx());

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
fun test_partial_withdrawal_leaving_exactly_minimum() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI minimum

    scenario.next_tx(contributor);

    // Contributor contributes
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 404000000 to get 400000000 after fee
        let contribution = coin::mint_for_testing<SUI>(404000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor withdraws partial amount leaving exactly minimum
    {
        let mut campaign = scenario.take_shared<Campaign>();

        // Withdraw 300000000 (0.3 SUI) leaving 100000000 (0.1 SUI) exactly minimum
        campaign::withdraw(&mut campaign, 300000000, scenario.ctx());

        // Check contributor's remaining balance
        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(
            user_contribution.contributor_amount() == 100000000,
            EWrongUserContributionAfterPartialWithdrawal,
        );

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
fun test_additional_contribution_exactly_minimum_from_existing() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI minimum

    scenario.next_tx(contributor);

    // Contributor makes initial contribution
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 202000000 to get 200000000 after fee
        let contribution = coin::mint_for_testing<SUI>(202000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor adds exactly minimum contribution
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(300000000000);

        // Deposit 101000000 to get exactly 100000000 after fee (minimum)
        let contribution = coin::mint_for_testing<SUI>(101000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        // Check accumulated contribution (200000000 + 100000000 = 300000000)
        let user_contribution = campaign.get_user_contribution(contributor);
        assert!(user_contribution.contributor_amount() == 300000000, EWrongUserContribution);

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

#[test]
fun test_withdrawal_of_remaining_after_partial() {
    let admin = @0xad;
    let contributor = @0xc0;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI minimum

    scenario.next_tx(contributor);

    // Contributor contributes
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 404000000 to get 400000000 after fee
        let contribution = coin::mint_for_testing<SUI>(404000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor);

    // Contributor withdraws partial amount
    {
        let mut campaign = scenario.take_shared<Campaign>();

        // Withdraw 200000000 (0.2 SUI) leaving 200000000 (0.2 SUI)
        campaign::withdraw(&mut campaign, 200000000, scenario.ctx());

        test_scenario::return_shared(campaign);
    };

    scenario.next_tx(contributor);

    // Contributor withdraws remaining amount (full withdrawal)
    {
        let mut campaign = scenario.take_shared<Campaign>();

        // Withdraw remaining 200000000
        campaign::withdraw(&mut campaign, 200000000, scenario.ctx());

        // Check contributor is removed
        assert!(!campaign.is_contributor(contributor), EUserStillInContributors);

        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::EBelowMinimumContribution)]
fun test_new_contributor_cannot_contribute_below_minimum() {
    let admin = @0xad;
    let new_contributor = @0xc1;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI minimum

    scenario.next_tx(new_contributor);

    // New contributor tries to contribute below minimum - should fail
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 50000000 to get 49504950 after fee (below minimum)
        let contribution = coin::mint_for_testing<SUI>(50000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.end();
}

// === CAMPAIGN DELETION TESTS === //

#[test]
fun test_delete_campaign_with_refunds() {
    let admin = @0xad;
    let contributor1 = @0xc1;
    let contributor2 = @0xc2;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    // Add contributors
    scenario.next_tx(contributor1);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 202000000 to get 200000000 after fee
        let contribution = coin::mint_for_testing<SUI>(202000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(contributor2);
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 101000000 to get 100000000 after fee
        let contribution = coin::mint_for_testing<SUI>(101000000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    // Delete campaign
    scenario.next_tx(admin);
    {
        let campaign = scenario.take_shared<Campaign>();

        campaign::delete(campaign, scenario.ctx());
    };

    // Check refunds were issued
    scenario.next_tx(contributor2);
    {
        let refund = scenario.take_from_address<coin::Coin<SUI>>(contributor2);
        assert!(refund.value() == 100000000, EWrongRefundAmount);
        scenario.return_to_sender(refund);
    };

    scenario.next_tx(contributor1);
    {
        let refund = scenario.take_from_address<coin::Coin<SUI>>(contributor1);
        assert!(refund.value() == 200000000, EWrongRefundAmount);
        scenario.return_to_sender(refund);
    };

    scenario.next_tx(admin);
    {
        let refund = scenario.take_from_address<coin::Coin<SUI>>(admin);
        assert!(refund.value() == 500000000, EWrongRefundAmount);
        scenario.return_to_sender(refund);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::ECampaignCompleted)]
fun test_delete_completed_campaign() {
    let admin = @0xad;
    let contributor = @0xc1;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    scenario.next_tx(contributor);

    // Complete the campaign
    {
        let mut campaign = scenario.take_shared<Campaign>();
        let mut test_clock = clock::create_for_testing(scenario.ctx());
        test_clock.set_for_testing(200000000000);

        // Deposit 510100000 to complete campaign
        let contribution = coin::mint_for_testing<SUI>(510100000, scenario.ctx());

        campaign::contribute(&mut campaign, contribution, &test_clock, scenario.ctx());

        test_scenario::return_shared(campaign);
        test_clock.destroy_for_testing();
    };

    scenario.next_tx(admin);

    // Try to delete completed campaign - should fail
    {
        let campaign = scenario.take_shared<Campaign>();

        campaign::delete(campaign, scenario.ctx());
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = collectivo::campaign::ENotCreator)]
fun test_delete_campaign_not_creator() {
    let admin = @0xad;
    let not_creator = @0xba;
    let mut scenario = test_scenario::begin(admin);

    create_test_campaign(&mut scenario, admin, 100000000); // 0.1 SUI

    scenario.next_tx(not_creator);

    // Non-creator tries to delete - should fail
    {
        let campaign = scenario.take_shared<Campaign>();

        campaign::delete(campaign, scenario.ctx());
    };

    scenario.end();
}

// === NFT STATUS TESTS === //

#[test]
fun test_nft_purchased_status() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    issue_admin_cap(scenario.ctx());
    create_test_campaign(&mut scenario, admin, 100000000);

    scenario.next_tx(admin);

    {
        let mut campaign = scenario.take_shared<Campaign>();
        let admin_cap = scenario.take_from_address<AdminCap>(admin);

        let new_nft_id = object::id_from_address(@0xabcdef1234567890abcdef1234567890abcdef12);
        let new_image_url = b"https://test.com/purchased-image.jpg".to_string();
        let new_rank = 150;
        let new_name = b"Purchased NFT".to_string();
        let new_nft_type = b"Purchased Type".to_string();

        campaign::set_nft_status(
            &mut campaign,
            campaign::get_nft_status_purchased(),
            &admin_cap,
            new_nft_id,
            new_image_url,
            new_rank,
            new_name,
            new_nft_type,
        );

        assert!(campaign.nft_is_purchased(), ENFTNotPurchased);

        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
fun test_nft_listed_status() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    issue_admin_cap(scenario.ctx());
    create_test_campaign(&mut scenario, admin, 100000000);

    scenario.next_tx(admin);

    {
        let mut campaign = scenario.take_shared<Campaign>();
        let admin_cap = scenario.take_from_address<AdminCap>(admin);

        let nft_id = object::id_from_address(@0xabcdef1234567890abcdef1234567890abcdef12);
        let image_url = b"https://test.com/listed-image.jpg".to_string();
        let rank = 200;
        let name = b"Listed NFT".to_string();
        let nft_type = b"Listed Type".to_string();

        campaign::set_nft_status(
            &mut campaign,
            campaign::get_nft_status_listed(),
            &admin_cap,
            nft_id,
            image_url,
            rank,
            name,
            nft_type,
        );

        assert!(campaign.nft_is_listed(), ENFTNotListed);

        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

#[test]
fun test_nft_delisted_status() {
    let admin = @0xad;
    let mut scenario = test_scenario::begin(admin);

    issue_admin_cap(scenario.ctx());
    create_test_campaign(&mut scenario, admin, 100000000);

    scenario.next_tx(admin);

    {
        let mut campaign = scenario.take_shared<Campaign>();
        let admin_cap = scenario.take_from_address<AdminCap>(admin);

        // First list it
        let nft_id = object::id_from_address(@0xabcdef1234567890abcdef1234567890abcdef12);
        let image_url = b"https://test.com/image.jpg".to_string();
        let rank = 200;
        let name = b"Test NFT".to_string();
        let nft_type = b"Test Type".to_string();

        campaign::set_nft_status(
            &mut campaign,
            campaign::get_nft_status_listed(),
            &admin_cap,
            nft_id,
            image_url,
            rank,
            name,
            nft_type,
        );

        assert!(campaign.nft_is_listed(), ENFTNotListed);

        // Then delist it
        campaign::set_nft_status(
            &mut campaign,
            campaign::get_nft_status_delisted(),
            &admin_cap,
            nft_id,
            image_url,
            rank,
            name,
            nft_type,
        );

        assert!(!campaign.nft_is_listed(), ENFTStillListed);

        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

// === WALLET TESTS === //

#[test]
fun test_create_and_get_wallet() {
    let admin = @0xad;
    let wallet_address = @0xa11e7;
    let mut scenario = test_scenario::begin(admin);

    issue_admin_cap(scenario.ctx());
    create_test_campaign(&mut scenario, admin, 100000000);

    scenario.next_tx(admin);

    {
        let mut campaign = scenario.take_shared<Campaign>();
        let admin_cap = scenario.take_from_address<AdminCap>(admin);

        campaign::create_wallet(&mut campaign, wallet_address, &admin_cap);

        let retrieved_wallet = campaign::get_wallet(&mut campaign);
        assert!(retrieved_wallet == wallet_address, EWalletWrong);

        scenario.return_to_sender(admin_cap);
        test_scenario::return_shared(campaign);
    };

    scenario.end();
}

// === HELPER FUNCTIONS === //

fun create_test_campaign(
    scenario: &mut test_scenario::Scenario,
    admin: address,
    min_contribution: u64,
) {
    create_test_campaign_with_target(scenario, admin, min_contribution, 1000000000);
}

fun create_test_campaign_with_target(
    scenario: &mut test_scenario::Scenario,
    admin: address,
    min_contribution: u64,
    target: u64,
) {
    scenario.next_tx(admin);

    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(200000000000);

    let nft_id = object::id_from_address(@0x1234567890abcdef1234567890abcdef12345678);
    let image_url = b"https://test.com/image.jpg".to_string();
    let rank = 100;
    let name = b"Test NFT".to_string();
    let nft_type = b"Test Type".to_string();
    let description = b"Test campaign description".to_string();
    // Deposit 505000000 to get 500000000 after fee
    let contribution = coin::mint_for_testing<SUI>(505000000, scenario.ctx());

    campaign::create(
        nft_id,
        image_url,
        rank,
        name,
        nft_type,
        description,
        target,
        min_contribution,
        contribution,
        &test_clock,
        scenario.ctx(),
    );

    test_clock.destroy_for_testing();
}
