#[test_only]
module bucket_fountain::test_stake {

    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::balance;
    use sui::coin;
    use sui::test_scenario as ts;
    use bucket_fountain::test_lp::TEST_LP;
    use bucket_fountain::math;
    use bucket_fountain::test_utils as ftu;
    use bucket_fountain::fountain_core::{Self as fc, Fountain};
    use bucket_fountain::fountain_periphery as fp;

    #[test]
    #[expected_failure(abort_code = math::EStakeAmountTooSmall)]
    fun test_stake_zero() {
        let flow_amount: u64 = 27_663_000_000_000;
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

        ts::next_tx(scenario, @0xcafe);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let (min_lock_time, max_lock_time) = fc::get_lock_time_range(&fountain);
            let stake_input = coin::zero<TEST_LP>(ts::ctx(scenario));
            let lock_time = (min_lock_time + max_lock_time) / 2;
            fp::stake(&clock, &mut fountain, stake_input, lock_time, ts::ctx(scenario));
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = math::EInvalidLockTime)]
    fun test_lower_than_min_lock_time() {
        let flow_amount: u64 = 27_663_000_000_000;
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

        ts::next_tx(scenario, @0xcafe);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let (min_lock_time, _max_lock_time) = fc::get_lock_time_range(&fountain);
            let stake_amount: u64 = 1_234_567_890;
            let lp_token = balance::create_for_testing<TEST_LP>(stake_amount);
            let lp_token = coin::from_balance(lp_token, ts::ctx(scenario));
            let lock_time = min_lock_time - 1;
            fp::stake(&clock, &mut fountain, lp_token, lock_time, ts::ctx(scenario));
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = math::EInvalidLockTime)]
    fun test_exceed_max_lock_time() {
        let flow_amount: u64 = 27_663_000_000_000;
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

        ts::next_tx(scenario, @0xcafe);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_LP, SUI>>(scenario);
            let (_min_lock_time, max_lock_time) = fc::get_lock_time_range(&fountain);
            let stake_amount: u64 = 9_876_543_210;
            let lp_token = balance::create_for_testing<TEST_LP>(stake_amount);
            let lp_token = coin::from_balance(lp_token, ts::ctx(scenario));
            let lock_time = max_lock_time + 1;
            fp::stake(&clock, &mut fountain, lp_token, lock_time, ts::ctx(scenario));
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        ts::end(scenario_val);
    }
}