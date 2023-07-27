#[test_only]
module bucket_fountain::test_unstake {
    use std::vector;
    use sui::sui::SUI;
    use sui::balance;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::test_scenario as ts;
    use bucket_fountain::test_utils as ftu;
    use bucket_fountain::test_lp::TEST_LP;
    use bucket_fountain::fountain_core::{Self as fc, Fountain, StakeProof};
    use bucket_fountain::fountain_periphery as fp;
    use bucket_fountain::math;

    #[test]
    fun test_unstake() {
        let flow_amount: u64 = 100_000_000_000_000;
        let flow_interval: u64 = 86400_000 * 7; // 1 week
        let min_lock_time: u64 = flow_interval * 5;
        let max_lock_time: u64 = flow_interval * 20;
        let scenario_val = ftu::setup<TEST_LP, SUI>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
        );
        let scenario = &mut scenario_val;

        let staker_count: u64 = 200;
        let stakers = ftu::stake_randomly<TEST_LP, SUI>(scenario, staker_count);
    
        ts::next_tx(scenario, ftu::dev());
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let clock = ts::take_shared<Clock>(scenario);
            let resource_amount = flow_amount;
            let resource = balance::create_for_testing<SUI>(resource_amount);
            let resource = coin::from_balance(resource, ts::ctx(scenario));
            fp::supply(&clock, &mut fountain, resource);
            // std::debug::print(&fountain);
            ts::return_shared(fountain);
            ts::return_shared(clock);
        };

        let fifteen_weeks: u64 = 86400_000 * 7 * 15;
        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, fifteen_weeks);
            ts::return_shared(clock);
        };

        let idx: u64 = 0;
        let unstakers = vector<address>[];
        let stake_amounts = vector<u64>[];
        let reward_amounts = vector<u64>[];
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
                if (clock::timestamp_ms(&clock) >= lock_util) {
                    let total_weight = fc::get_total_weight(&fountain);
                    let stake_weight = fc::get_proof_stake_weight(&proof);
                    let stake_amount = fc::get_proof_stake_amount(&proof);
                    let expected_reward_amount = math::mul_factor(flow_amount, stake_weight, total_weight);
                    vector::push_back(&mut unstakers, staker);
                    vector::push_back(&mut stake_amounts, stake_amount);
                    vector::push_back(&mut reward_amounts, expected_reward_amount);
                    fp::unstake(&clock, &mut fountain, proof, ts::ctx(scenario));
                } else {
                    ts::return_to_sender(scenario, proof);
                };
                ts::return_shared(clock);
                ts::return_shared(fountain);
            };
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
                let expected_stake_amount = *vector::borrow(&stake_amounts, idx);
                assert!(coin::value(&unstaker_lp) == expected_stake_amount, 0);
                ts::return_to_sender(scenario, unstaker_lp);
            };
            idx = idx + 1;
        };

        ts::end(scenario_val);
    }
}