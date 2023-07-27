#[test_only]
module bucket_fountain::test_lp {
    use std::option;
    use sui::coin;
    use sui::tx_context::TxContext;
    use sui::transfer;

    struct TEST_LP has drop {}

    fun init(otw: TEST_LP, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            otw,
            9,
            b"TLP",
            b"Test LP Coin",
            b"",
            option::none(),
            ctx,
        );
        transfer::freeze_object(treasury_cap);
        transfer::freeze_object(metadata);
    }
}

#[test_only]
module bucket_fountain::test_utils {
    use std::vector;
    use sui::sui::SUI;
    use sui::address;
    use sui::test_random;
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::balance;
    use sui::coin;
    use bucket_fountain::fountain_core::{Self as fc, Fountain};
    use bucket_fountain::test_lp::TEST_LP;
    use bucket_fountain::math;
    use bucket_fountain::fountain_periphery as fp;

    const DEV: address = @0x0c87f96e5b09faebc286a2180e977003313c4467a9e95bbc3b6c5c6d711f67ae;
    const START_TIME: u64 = 1690466779049;

    public fun setup<S, R>(
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
    ): Scenario {
        let scenario_val = ts::begin(DEV);
        let scenario = &mut scenario_val;
        {
            let clock = clock::create_for_testing(ts::ctx(scenario));
            clock::set_for_testing(&mut clock, START_TIME);
            clock::share_for_testing(clock);
            fp::create_fountain<S, R>(
                flow_amount,
                flow_interval,
                min_lock_time,
                max_lock_time,
                ts::ctx(scenario),
            );
        };

        ts::next_tx(scenario, DEV);
        {
            let fountain = ts::take_shared<Fountain<S, R>>(scenario);
            let (fountain_flow_amount, fountain_flow_interval) = fc::get_flow_rate(&fountain);
            assert!(fountain_flow_amount == flow_amount, 0);
            assert!(fountain_flow_interval == flow_interval, 0);
            ts::return_shared(fountain);
        };

        scenario_val
    }

    public fun stake_randomly<S, R>(
        scenario: &mut Scenario,
        staker_count: u64,
    ): (vector<address>, vector<u64>) {
        let seed = b"fountain stakers";
        vector::push_back(&mut seed, ((staker_count % 256) as u8));
        let rang = test_random::new(seed);
        let rangr = &mut rang;

        let stakers = vector<address>[];
        let idx: u64 = 1;
        while (idx <= staker_count) {
            vector::push_back(&mut stakers, address::from_u256(test_random::next_u256(rangr)));
            idx = idx + 1;
        };

        let idx: u64 = 0;
        let expected_total_stake_amount: u64 = 0;
        let expected_total_stake_weight: u64 = 0;
        let min_stake_amount: u64 = 1_000_000_000;
        let staker_weights = vector<u64>[];
        while (idx < staker_count) {
            let staker = *vector::borrow(&stakers, idx);
            ts::next_tx(scenario, staker);
            {
                let clock = ts::take_shared<Clock>(scenario);
                let fountain = ts::take_shared<Fountain<S, R>>(scenario);
                let (min_lock_time, max_lock_time) = fc::get_lock_time_range(&fountain);
                let stake_amount = min_stake_amount + test_random::next_u64(rangr) % (min_stake_amount * 10_000);
                let lp_token = balance::create_for_testing<S>(stake_amount);
                let lp_token = coin::from_balance(lp_token, ts::ctx(scenario));
                let lock_time = min_lock_time + test_random::next_u64(rangr) % (max_lock_time - min_lock_time);
                fp::stake(&clock, &mut fountain, lp_token, lock_time, ts::ctx(scenario));
                let expected_stake_weight = math::compute_weight(stake_amount, lock_time, min_lock_time, max_lock_time);
                expected_total_stake_amount = expected_total_stake_amount + stake_amount;
                expected_total_stake_weight = expected_total_stake_weight + expected_stake_weight;
                vector::push_back(&mut staker_weights, expected_stake_weight);
                ts::return_shared(clock);
                ts::return_shared(fountain);
            };
            idx = idx + 1;
        };

        let idx: u64 = 0;
        ts::next_tx(scenario, DEV);
        {
            let fountain = ts::take_shared<Fountain<S, R>>(scenario);
            assert!(fc::get_source_balance(&fountain) == 0, 0);
            assert!(fc::get_pool_balance(&fountain) == 0, 0);
            assert!(fc::get_staked_balance(&fountain) == expected_total_stake_amount, 0);
            assert!(fc::get_total_weight(&fountain) == expected_total_stake_weight, 0);
            assert!(fc::get_cumulative_unit(&fountain) == 0, 0);
            ts::return_shared(fountain);
        };

        (stakers, staker_weights)
    }

    public fun dev(): address { DEV }

    public fun start_time(): u64 { START_TIME }
}