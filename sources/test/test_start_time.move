#[test_only]
module bucket_fountain::test_start_time {
    use std::vector;
    use sui::sui::SUI;
    use sui::test_scenario as ts;
    use sui::clock::{Self, Clock};
    use sui::balance;
    use sui::coin::{Self, Coin};
    use bucket_fountain::fountain_core::{Self as fc, Fountain, StakeProof, AdminCap};
    use bucket_fountain::math;
    use bucket_fountain::fountain_periphery as fp;
    use bucket_fountain::test_utils as ftu;
    use bucket_fountain::test_lp::TEST_LP;

    #[test]
    fun test_start_time() {
        let flow_amount: u64 = 27_663_000_000_000;
        let flow_interval: u64 = 86400_000 * 7; // 1 week
        let min_lock_time: u64 = flow_interval * 5;
        let max_lock_time: u64 = flow_interval * 20;

        let scenario_val = ts::begin(ftu::dev());
        let scenario = &mut scenario_val;
        {
            let clock = clock::create_for_testing(ts::ctx(scenario));
            let init_supply = balance::create_for_testing<SUI>(flow_amount);
            let init_supply = coin::from_balance(init_supply, ts::ctx(scenario));
            fp::setup_fountain<TEST_LP, SUI>(
                &clock,
                init_supply,
                flow_amount,
                flow_interval,
                min_lock_time,
                max_lock_time,
                ftu::start_time(),
                false,
                ts::ctx(scenario),
            );
            clock::share_for_testing(clock);
        };

        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            assert!(fc::get_latest_release_time(&fountain) == ftu::start_time(), 0);
            clock::set_for_testing(&mut clock, ftu::start_time() / 2);
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        let staker_count: u64 = 88;
        let stakers = ftu::stake_randomly<TEST_LP, SUI>(scenario, staker_count);
        let idx: u64 = 0;
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let clock = ts::take_shared<Clock>(scenario);
                let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
                // std::debug::print(&fountain);
                let proof = ts::take_from_sender<StakeProof<TEST_LP, SUI>>(scenario);
                let current_time = clock::timestamp_ms(&clock);
                let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                assert!(reward_amount == 0, 0);
                fp::claim(&clock, &mut fountain, &mut proof, ts::ctx(scenario));
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, ftu::start_time() / 3);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);   
            assert!(fc::get_source_balance(&fountain) == flow_amount, 0);
            // std::debug::print(&fc::get_pool_balance(&fountain));
            assert!(fc::get_pool_balance(&fountain) == 0, 0);
            assert!(fc::get_latest_release_time(&fountain) == ftu::start_time(), 0);
            let some_staker = *vector::borrow(&stakers, 33);
            let sui_coin_ids = ts::ids_for_address<Coin<SUI>>(some_staker);
            assert!(vector::is_empty(&sui_coin_ids), 0);
            let sec_supply = balance::create_for_testing<SUI>(flow_amount);
            let sec_supply = coin::from_balance(sec_supply, ts::ctx(scenario));
            fp::supply(&clock, &mut fountain, sec_supply);
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        let three_day: u64 = 86400_000 * 3;
        ts::next_tx(scenario, @0xde1);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);   
            assert!(fc::get_source_balance(&fountain) == flow_amount * 2, 0);
            assert!(fc::get_pool_balance(&fountain) == 0, 0);
            assert!(fc::get_latest_release_time(&fountain) == ftu::start_time(), 0);
            clock::set_for_testing(&mut clock, ftu::start_time() + three_day);
            ts::return_shared(clock);
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
                let current_time = clock::timestamp_ms(&clock);
                let expected_released_amount = math::mul_factor(flow_amount, three_day, flow_interval);
                let expected_reward_amount = math::mul_factor(expected_released_amount, stake_weight, total_weight);
                let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                assert!(reward_amount == expected_reward_amount, 0);
                fp::claim(&clock, &mut fountain, &mut proof, ts::ctx(scenario));
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        ts::end(scenario_val);
    }

    #[test]
    fun test_start_time_with_flow_rate_changed() {
        let flow_amount: u64 = 27_663_000_000_000;
        let flow_interval: u64 = 86400_000 * 7; // 1 week
        let min_lock_time: u64 = flow_interval * 5;
        let max_lock_time: u64 = flow_interval * 20;

        let scenario_val = ts::begin(ftu::dev());
        let scenario = &mut scenario_val;
        {
            let clock = clock::create_for_testing(ts::ctx(scenario));
            let init_supply = balance::create_for_testing<SUI>(flow_amount);
            let init_supply = coin::from_balance(init_supply, ts::ctx(scenario));
            fp::setup_fountain<TEST_LP, SUI>(
                &clock,
                init_supply,
                flow_amount,
                flow_interval,
                min_lock_time,
                max_lock_time,
                ftu::start_time(),
                true,
                ts::ctx(scenario),
            );
            clock::share_for_testing(clock);
        };

        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            assert!(fc::get_latest_release_time(&fountain) == ftu::start_time(), 0);
            clock::set_for_testing(&mut clock, ftu::start_time() / 2);
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        let staker_count: u64 = 157;
        let stakers = ftu::stake_randomly<TEST_LP, SUI>(scenario, staker_count);
        let idx: u64 = 0;
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let clock = ts::take_shared<Clock>(scenario);
                let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
                // std::debug::print(&fountain);
                let proof = ts::take_from_sender<StakeProof<TEST_LP, SUI>>(scenario);
                let current_time = clock::timestamp_ms(&clock);
                let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                assert!(reward_amount == 0, 0);
                fp::claim(&clock, &mut fountain, &mut proof, ts::ctx(scenario));
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, ftu::start_time() / 3);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);   
            assert!(fc::get_source_balance(&fountain) == flow_amount, 0);
            // std::debug::print(&fc::get_pool_balance(&fountain));
            assert!(fc::get_pool_balance(&fountain) == 0, 0);
            assert!(fc::get_latest_release_time(&fountain) == ftu::start_time(), 0);
            let some_staker = *vector::borrow(&stakers, 33);
            let sui_coin_ids = ts::ids_for_address<Coin<SUI>>(some_staker);
            assert!(vector::is_empty(&sui_coin_ids), 0);
            let sec_supply = balance::create_for_testing<SUI>(flow_amount);
            let sec_supply = coin::from_balance(sec_supply, ts::ctx(scenario));
            fp::supply(&clock, &mut fountain, sec_supply);
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        let half_day: u64 = 86400_000 / 2;
        ts::next_tx(scenario, @0xde1);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);   
            assert!(fc::get_source_balance(&fountain) == flow_amount * 2, 0);
            assert!(fc::get_pool_balance(&fountain) == 0, 0);
            assert!(fc::get_latest_release_time(&fountain) == ftu::start_time(), 0);
            clock::set_for_testing(&mut clock, ftu::start_time() + half_day);
            ts::return_shared(clock);
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
                let current_time = clock::timestamp_ms(&clock);
                let expected_released_amount = math::mul_factor(flow_amount, half_day, flow_interval);
                let expected_reward_amount = math::mul_factor(expected_released_amount, stake_weight, total_weight);
                let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                assert!(reward_amount == expected_reward_amount, 0);
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        // update flow rate
        ts::next_tx(scenario, ftu::dev());
        {
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);   
            let clock = ts::take_shared<Clock>(scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            fc::update_flow_rate(&admin_cap, &clock, &mut fountain, flow_amount * 3, flow_interval);
            ts::return_shared(fountain);
            ts::return_shared(clock);
            ts::return_to_sender(scenario, admin_cap);
        };

        ts::next_tx(scenario, ftu::dev());
        {
            let clock = ts::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, half_day * 4);
            ts::return_shared(clock);
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
                let current_time = clock::timestamp_ms(&clock);
                let expected_released_amount = math::mul_factor(flow_amount, half_day * 13, flow_interval);
                let expected_reward_amount = math::mul_factor(expected_released_amount, stake_weight, total_weight);
                let reward_amount = fc::get_reward_amount(&fountain, &proof, current_time);
                assert!(math::approx_equal(
                    reward_amount, expected_reward_amount, 1
                ), 0);
                ts::return_shared(clock);
                ts::return_shared(fountain);
                ts::return_to_sender(scenario, proof);
            };
            idx = idx + 1;
        };

        ts::end(scenario_val);
    }
}