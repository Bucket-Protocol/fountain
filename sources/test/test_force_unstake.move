#[test_only]
module bucket_fountain::test_claim {
    use std::vector;
    use sui::sui::SUI;
    use sui::balance;
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
        let min_penalty_rate: u64 = 20_000; // 2%
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
            let resource_amount = flow_amount;
            let resource = balance::create_for_testing<SUI>(resource_amount);
            let resource = coin::from_balance(resource, ts::ctx(scenario));
            fp::supply(&clock, &mut fountain, resource);
            fc::new_penalty_vault(&admin_cap, &mut fountain, min_penalty_rate, max_penalty_rate);
            // std::debug::print(&fountain);
            ts::return_shared(fountain);
            ts::return_shared(clock);
            ts::return_to_sender(scenario, admin_cap);
        };

        let fifteen_days: u64 = flow_interval * 15;
        ts::next_tx(scenario, ftu::dev());
        let total_weight = {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            clock::increment_for_testing(&mut clock, fifteen_days);
            let total_weight = fc::get_total_weight(&fountain);
            ts::return_shared(clock);
            ts::return_shared(fountain);
            total_weight
        };

        let idx: u64 = 0;
        let unstakers = vector<address>[];
        let stake_amounts = vector<u64>[];
        let reward_amounts = vector<u64>[];
        let after_stakers = vector<address>[];
        let after_stake_weights = vector<u64>[];
        let after_total_weight = total_weight;
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
                let stake_weight = fc::get_proof_stake_weight(&proof);
                if (current_time >= lock_util) {
                    let stake_amount = fc::get_proof_stake_amount(&proof);
                    let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                    let expected_reward_amount = math::mul_factor(flow_amount * 3 / 4, stake_weight, total_weight);
                    // std::debug::print(&reward_amount);
                    // std::debug::print(&expected_reward_amount);
                    assert!(reward_amount == expected_reward_amount, 0);
                    vector::push_back(&mut unstakers, staker);
                    vector::push_back(&mut stake_amounts, stake_amount);
                    vector::push_back(&mut reward_amounts, reward_amount);
                    fp::unstake(&clock, &mut fountain, proof, ts::ctx(scenario));
                    after_total_weight = after_total_weight - stake_weight;
                } else {
                    vector::push_back(&mut after_stakers, staker);
                    vector::push_back(&mut after_stake_weights, stake_weight);
                    ts::return_to_sender(scenario, proof);
                };
                ts::return_shared(clock);
                ts::return_shared(fountain);
            };
            idx = idx + 1;
        };
    }
}