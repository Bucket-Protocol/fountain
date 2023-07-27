module bucket_fountain::math {

    const EDividedByZero: u64 = 0;
    const EInvalidLockTime: u64 = 1;
    const EStakeAmountTooSmall: u64 = 2;

    public fun mul_factor(number: u64, numerator: u64, denominator: u64): u64 {
        assert!(denominator > 0, EDividedByZero);
        ((
            ((number as u128) * (numerator as u128) + (denominator as u128) / 2)
            / (denominator as u128)
        ) as u64)
    }

    public fun mul_factor_u128(number: u128, numerator: u128, denominator: u128): u128 {
        assert!(denominator > 0, EDividedByZero);
        (number * numerator + denominator / 2) / denominator
    }

    public fun compute_weight(
        stake_amount: u64,
        lock_time: u64,
        min_lock_time: u64,
        max_lock_time: u64,
    ): u64 {
        assert!(lock_time >= min_lock_time && lock_time <= max_lock_time, EInvalidLockTime);
        let weight = mul_factor(stake_amount, lock_time, max_lock_time);
        assert!(weight > 0, EStakeAmountTooSmall);
        weight
    }

    #[test_only]
    public fun approx_equal(x: u64, y: u64, tolarence: u64): bool {
        sui::math::diff(x, y) <= tolarence
    }

    #[test]
    #[expected_failure]
    fun test_native_mul() {
        let amount = 10000000000; // 100 SUI
        let price = 4000000000; // 1 SUI = 4000 USD
        let denominator = 1000000;
        let value = amount * price / denominator; // overflow
        std::debug::print(&value);
    }

    #[test]
    fun test_mul_factor() {
        let amount = 10000000000; // 100 SUI
        let price = 4000000000; // 1 SUI = 4000 USD
        let decimals = 1000000;
        let value = mul_factor(amount, price, decimals);
        // std::debug::print(&value);
        assert!(value == 40000000000000, 0);
    }

    #[test]
    #[expected_failure(abort_code = EDividedByZero)]
    fun test_mul_factor_divided_by_zero() {
        mul_factor(3, 1, 0);
    }

    #[test]
    #[expected_failure(abort_code = EDividedByZero)]
    fun test_mul_factor_u128_divided_by_zero() {
        mul_factor_u128(3, 1, 0);
    }
}
