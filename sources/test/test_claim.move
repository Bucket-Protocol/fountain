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
    use bucket_fountain::fountain_core::{Self as fc, Fountain, StakeProof};
    use bucket_fountain::fountain_periphery as fp;
    use bucket_fountain::math;

    #[test]
    fun test_claim() {
        let flow_amount: u64 = 27_663_000_000_000;
        let flow_interval: u64 = 86400_000 * 7; // 1 week
        let min_lock_time: u64 = flow_interval * 5;
        let max_lock_time: u64 = flow_interval * 20;
        let scenario_val = ftu::setup<TEST_LP, SUI>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
            false,
        );
        let scenario = &mut scenario_val;

        let staker_count: u64 = 100;
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

        let one_day: u64 = 86400_000;
        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, one_day);
            ts::return_shared(clock);
        };

        let idx: u64 = 0;
        let staker_reward_amounts = vector<u64>[];
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let clock = ts::take_shared<Clock>(scenario);
                let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
                // std::debug::print(&fountain);
                let proof = ts::take_from_sender<StakeProof<TEST_LP, SUI>>(scenario);
                let total_weight = fc::get_total_weight(&fountain);
                let stake_weight = fc::get_proof_stake_weight(&proof);
                let expected_released_amount = math::mul_factor(flow_amount, one_day, flow_interval);
                let expected_reward_amount = math::mul_factor(expected_released_amount, stake_weight, total_weight);
                let current_time = clock::timestamp_ms(&clock);
                let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                assert!(reward_amount == expected_reward_amount, 0);
                vector::push_back(&mut staker_reward_amounts, reward_amount);
                fp::claim(&clock, &mut fountain, &mut proof, ts::ctx(scenario));
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        let idx: u64 = 0;
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let staker_reward = ts::take_from_sender<Coin<SUI>>(scenario);
                let expected_reward_amount = *vector::borrow(&staker_reward_amounts, idx);
                assert!(coin::value(&staker_reward) == expected_reward_amount, 0);
                let staker_reward = coin::into_balance(staker_reward);
                balance::destroy_for_testing(staker_reward);
            };
            idx = idx + 1;
        };

        ts::next_tx(scenario, ftu::dev());
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);   
            assert!(math::approx_equal(
                fc::get_source_balance(&fountain),
                flow_amount * 6 / 7,
                1,
            ), 0);
            std::debug::print(&fc::get_pool_balance(&fountain));
            assert!(math::approx_equal(
                fc::get_pool_balance(&fountain),
                0,
                10,
            ), 0);
            let expected_released_amount = (math::mul_factor(flow_amount, one_day, flow_interval) as u128);
            let total_weight = (fc::get_total_weight(&fountain) as u128);
            // std::debug::print(&fc::get_cumulative_unit(&fountain));
            // std::debug::print(&(expected_released_amount * 0x10000000000000000 / total_weight));
            assert!(fc::get_cumulative_unit(&fountain) == math::mul_factor_u128(expected_released_amount, 0x10000000000000000, total_weight), 0); 
            ts::return_shared(fountain);
        };

        let second_staker_count: u64 = 69;
        let second_stakers = ftu::stake_randomly<TEST_LP, SUI>(scenario, second_staker_count);

        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, one_day * 2);
            ts::return_shared(clock);
        };

        vector::append(&mut stakers, second_stakers);
        staker_count = staker_count + second_staker_count;

        let idx: u64 = 0;
        let staker_reward_amounts = vector<u64>[];
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let clock = ts::take_shared<Clock>(scenario);
                let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
                // std::debug::print(&fountain);
                let proof = ts::take_from_sender<StakeProof<TEST_LP, SUI>>(scenario);
                let total_weight = fc::get_total_weight(&fountain);
                let stake_weight = fc::get_proof_stake_weight(&proof);
                let current_time = clock::timestamp_ms(&clock);
                let expected_released_amount = math::mul_factor(flow_amount, one_day * 2, flow_interval);
                let expected_reward_amount = math::mul_factor(expected_released_amount, stake_weight, total_weight);
                let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                assert!(reward_amount == expected_reward_amount, 0);
                vector::push_back(&mut staker_reward_amounts, reward_amount);
                fp::claim(&clock, &mut fountain, &mut proof, ts::ctx(scenario));
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        let idx: u64 = 0;
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let staker_reward = ts::take_from_sender<Coin<SUI>>(scenario);
                let expected_reward_amount = *vector::borrow(&staker_reward_amounts, idx);
                assert!(coin::value(&staker_reward) == expected_reward_amount, 0);
                let staker_reward = coin::into_balance(staker_reward);
                balance::destroy_for_testing(staker_reward);
            };
            idx = idx + 1;
        };

        ts::next_tx(scenario, ftu::dev());
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            assert!(math::approx_equal(
                fc::get_source_balance(&fountain),
                flow_amount * 4 / 7,
                1,
            ), 0);
            std::debug::print(&fc::get_pool_balance(&fountain));
            assert!(math::approx_equal(
                fc::get_pool_balance(&fountain),
                0,
                10,
            ), 0);
            ts::return_shared(fountain);
        };

        let airdrop_amount: u64 = flow_amount / 3;
        ts::next_tx(scenario, ftu::dev());
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let airdrop_input = balance::create_for_testing<SUI>(airdrop_amount);
            let airdrop_input = coin::from_balance(airdrop_input, ts::ctx(scenario));
            fp::airdrop(&mut fountain, airdrop_input);
            ts::return_shared(fountain);
        };

        let idx: u64 = 0;
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let clock = ts::take_shared<Clock>(scenario);
                let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
                // std::debug::print(&fountain);
                let proof = ts::take_from_sender<StakeProof<TEST_LP, SUI>>(scenario);
                let total_weight = fc::get_total_weight(&fountain);
                let stake_weight = fc::get_proof_stake_weight(&proof);
                let expected_reward_amount = math::mul_factor(airdrop_amount, stake_weight, total_weight);
                let reward = fc::claim(&clock, &mut fountain, &mut proof);
                assert!(balance::value(&reward) == expected_reward_amount, 0);
                balance::destroy_for_testing(reward);
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        ts::next_tx(scenario, ftu::dev());
        let pool_balance = {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let pool_balance = fc::get_pool_balance(&fountain);
            ts::return_shared(fountain);
            pool_balance
        };

        let tune_amount: u64 = 10;
        ts::next_tx(scenario, ftu::dev());
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let tune_input = balance::create_for_testing<SUI>(tune_amount);
            let tune_input = coin::from_balance(tune_input, ts::ctx(scenario));
            fp::tune(&mut fountain, tune_input);
            ts::return_shared(fountain);
        };

        let idx: u64 = 0;
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let clock = ts::take_shared<Clock>(scenario);
                let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
                // std::debug::print(&fountain);
                assert!(fc::get_pool_balance(&fountain) == pool_balance + tune_amount, 0);
                let proof = ts::take_from_sender<StakeProof<TEST_LP, SUI>>(scenario);
                let reward = fc::claim(&clock, &mut fountain, &mut proof);
                assert!(balance::value(&reward) == 0, 0);
                balance::destroy_for_testing(reward);
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = fc::EInvalidProof)]
    fun test_wrong_fountain_id() {
        let flow_amount: u64 = 100_000_000_000_000;
        let flow_interval: u64 = 86400_000 * 7; // 1 week
        let min_lock_time: u64 = flow_interval * 5;
        let max_lock_time: u64 = flow_interval * 20;
        let scenario_val = ftu::setup<TEST_LP, SUI>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
            true,
        );
        let scenario = &mut scenario_val;
        let stakers = ftu::stake_randomly<TEST_LP, SUI>(scenario, 5);

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

        let ten_weeks: u64 = 86400_000 * 7 * 10;
        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, ten_weeks);
            ts::return_shared(clock);
        };

        let staker = *vector::borrow(&stakers, 4);
        ts::next_tx(scenario, staker);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let current_time = clock::timestamp_ms(&clock);
            let fountain = fc::new_fountain<TEST_LP, SUI>(
                flow_amount,
                flow_interval,
                min_lock_time,
                max_lock_time,
                current_time,
                ts::ctx(scenario),
            );
            let proof = ts::take_from_sender<StakeProof<TEST_LP, SUI>>(scenario);
            fp::claim(&clock, &mut fountain, &mut proof, ts::ctx(scenario));
            ts::return_shared(clock);
            ts::return_to_sender(scenario, proof);
            fc::destroy_fountain_for_testing(fountain);
        };

        ts::end(scenario_val);
    }
}