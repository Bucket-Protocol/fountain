#[test_only]
module bucket_fountain::test_force_unstake {
    use std::vector;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::test_scenario as ts;
    use bucket_fountain::test_utils as ftu;
    use bucket_fountain::test_lp::TEST_LP;
    use bucket_fountain::fountain_core::{Self as fc, Fountain, StakeProof, AdminCap};
    use bucket_fountain::fountain_periphery as fp;
    use bucket_fountain::math;

    #[test]
    fun test_force_unstake() {
        let flow_amount: u64 = 1_000_000_000_000;
        let flow_interval: u64 = 86400_000; // 1 day
        let min_lock_time: u64 = flow_interval * 1;
        let max_lock_time: u64 = flow_interval * 56;
        let max_penalty_rate: u64 = 100_000; // 10%
        let scenario_val = ftu::setup<TEST_LP, SUI>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
            true,
        );
        let scenario = &mut scenario_val;

        let staker_count: u64 = 200;
        let stakers = ftu::stake_randomly<TEST_LP, SUI>(scenario, staker_count);
    
        ts::next_tx(scenario, ftu::dev());
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let clock = ts::take_shared<Clock>(scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let resource_amount = flow_amount * 56;
            let resource = coin::mint_for_testing<SUI>(resource_amount, ts::ctx(scenario));
            fp::supply(&clock, &mut fountain, resource);
            let tuned_sui = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(scenario));
            fp::tune(&mut fountain, tuned_sui);
            fc::new_penalty_vault(&admin_cap, &mut fountain, max_penalty_rate);
            // std::debug::print(&fountain);
            ts::return_shared(fountain);
            ts::return_shared(clock);
            ts::return_to_sender(scenario, admin_cap);
        };

        let fourteen_days: u64 = flow_interval * 28;
        ts::next_tx(scenario, ftu::dev());
        let total_weight = {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            clock::increment_for_testing(&mut clock, fourteen_days);
            let total_weight = fc::get_total_weight(&fountain);
            ts::return_shared(clock);
            ts::return_shared(fountain);
            total_weight
        };

        let idx: u64 = 0;
        let unstakers = vector<address>[];
        let unstake_amounts = vector<u64>[];
        let reward_amounts = vector<u64>[];
        let after_total_weight = total_weight;
        let total_penalty_amount: u64 = 0;
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let clock = ts::take_shared<Clock>(scenario);
                let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
                // std::debug::print(&fountain);
                let proof = ts::take_from_sender<StakeProof<TEST_LP, SUI>>(scenario);
                let lock_util = fc::get_proof_lock_until(&proof);
                // std::debug::print(&lock_util);
                let current_time = clock::timestamp_ms(&clock);
                let stake_amount = fc::get_proof_stake_amount(&proof);
                let stake_weight = fc::get_proof_stake_weight(&proof);
                let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                let expected_reward_amount = math::mul_factor(flow_amount * 28, stake_weight, total_weight);
                assert!(reward_amount == expected_reward_amount, 0);
                vector::push_back(&mut unstakers, staker);
                vector::push_back(&mut reward_amounts, reward_amount);
                after_total_weight = after_total_weight - stake_weight;
                if (current_time >= lock_util) {
                    // std::debug::print(&reward_amount);
                    // std::debug::print(&expected_reward_amount);
                    vector::push_back(&mut unstake_amounts, stake_amount);
                    fp::unstake(&clock, &mut fountain, proof, ts::ctx(scenario));
                } else {
                    let penalty_amount = fc::get_penalty_amount(&fountain, &proof, current_time);
                    let out_penalty_rate = (penalty_amount * 1_000_000 / stake_amount);
                    assert!(out_penalty_rate <= max_penalty_rate, 0);
                    // std::debug::print(&out_penalty_rate);
                    fp::force_unstake(&clock, &mut fountain, proof, ts::ctx(scenario));
                    vector::push_back(&mut unstake_amounts, stake_amount - penalty_amount);
                    total_penalty_amount = total_penalty_amount + penalty_amount;
                };
                ts::return_shared(clock);
                ts::return_shared(fountain);
            };
            // std::debug::print(&idx);
            idx = idx + 1;
        };

        let idx: u64 = 0;
        let unstaker_count = vector::length(&unstakers);
        // std::debug::print(&unstaker_count);
        while (idx < unstaker_count) {
            let unstaker = *vector::borrow(&unstakers, idx);
            ts::next_tx(scenario, unstaker);
            {
                let unstaker_reward = ts::take_from_sender<Coin<SUI>>(scenario);
                let expected_reward_amount = *vector::borrow(&reward_amounts, idx);
                // std::debug::print(&coin::value(&unstaker_reward));
                // std::debug::print(&expected_reward_amount);
                assert!(coin::value(&unstaker_reward) == expected_reward_amount, 0);
                ts::return_to_sender(scenario, unstaker_reward);
                let unstaker_lp = ts::take_from_sender<Coin<TEST_LP>>(scenario);
                let expected_stake_amount = *vector::borrow(&unstake_amounts, idx);
                assert!(coin::value(&unstaker_lp) == expected_stake_amount, 0);
                ts::return_to_sender(scenario, unstaker_lp);
            };
            idx = idx + 1;
        };

        ts::next_tx(scenario, ftu::dev());
        let recipient = @0xcafe;
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            assert!(fc::get_total_weight(&fountain) == 0, 0);
            assert!(fc::get_staked_balance(&fountain) == 0, 0);
            assert!(fc::get_penalty_vault_balance(&fountain) == total_penalty_amount, 0);
            fp::claim_penalty(&admin_cap, &mut fountain, recipient, ts::ctx(scenario));
            ts::return_shared(fountain);
            ts::return_to_sender(scenario, admin_cap);
        };

        ts::next_tx(scenario, recipient);
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let penalty_lp = ts::take_from_sender<Coin<TEST_LP>>(scenario);
            assert!(fc::get_penalty_vault_balance(&fountain) == 0, 0);
            assert!(coin::value(&penalty_lp) == total_penalty_amount, 0);
            ts::return_shared(fountain);
            ts::return_to_sender(scenario, penalty_lp);
        };

        ts::end(scenario_val);
    }
}