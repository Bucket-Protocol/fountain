module bucket_fountain::fountain_core {

    use sui::balance::{Self, Balance};
    use sui::tx_context::TxContext;
    use sui::object::{Self, ID, UID};
    use sui::clock::{Self, Clock};
    use sui::event;
    use bucket_fountain::math;

    const DISTRIBUTION_PRECISION: u128 = 0x10000000000000000;

    const EStillLocked: u64 = 0;
    const EWrongFountainId: u64 = 1;

    struct AdminCap has key, store {
        id: UID,
        fountain_id: ID,
    }

    struct Fountain<phantom S, phantom R> has store, key {
        id: UID,
        source: Balance<R>,
        flow_amount: u64,
        flow_interval: u64,
        pool: Balance<R>,
        staked: Balance<S>,
        total_weight: u64,
        cumulative_unit: u128,
        latest_release_time: u64,
        min_lock_time: u64,
        max_lock_time: u64,
    }

    struct StakeProof<phantom S, phantom R> has store, key {
        id: UID,
        fountain_id: ID,
        stake_amount: u64,
        start_uint: u128,
        stake_weight: u64,
        lock_until: u64,
    }

    struct StakeEvent<phantom S, phantom R> has copy, drop {
        fountain_id: ID,
        stake_amount: u64,
        stake_weight: u64,
        lock_time: u64,
        start_time: u64,
    }

    struct ClaimEvent<phantom S, phantom R> has copy, drop {
        fountain_id: ID,
        reward_amount: u64,
        claim_time: u64,
    }

    struct UnstakeEvent<phantom S, phantom R> has copy, drop {
        fountain_id: ID,
        unstake_amount: u64,
        unstake_weigth: u64,
        end_time: u64,
    }

    public fun new_fountain<S, R>(
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
        start_time: u64,
        ctx: &mut TxContext,
    ): Fountain<S, R> {
        Fountain {
            id: object::new(ctx),
            source: balance::zero(),
            flow_amount,
            flow_interval,
            pool: balance::zero(),
            staked: balance::zero(),
            total_weight: 0,
            cumulative_unit: 0,
            latest_release_time: start_time,
            min_lock_time,
            max_lock_time,
        }
    }

    public fun new_fountain_with_admin_cap<S, R>(
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
        start_time: u64,
        ctx: &mut TxContext,
    ): (Fountain<S, R>, AdminCap) {
        let fountain = new_fountain<S, R>(flow_amount, flow_interval, min_lock_time, max_lock_time, start_time, ctx);
        let fountain_id = object::id(&fountain);
        let admin_cap = AdminCap { id: object::new(ctx), fountain_id };
        (fountain, admin_cap)
    }

    public fun supply<S, R>(clock: &Clock, fountain: &mut Fountain<S, R>, resource: Balance<R>) {
        source_to_pool(fountain, clock);
        balance::join(&mut fountain.source, resource);
    }

    public fun airdrop<S, R>(fountain: &mut Fountain<S, R>, resource: Balance<R>) {
        collect_resource(fountain, resource);
    }

    public fun tune<S, R>(fountain: &mut Fountain<S, R>, resource: Balance<R>) {
        balance::join(&mut fountain.pool, resource);
    }

    public fun stake<S, R>(
        clock: &Clock,
        fountain: &mut Fountain<S, R>,
        input: Balance<S>,
        lock_time: u64,
        ctx: &mut TxContext,
    ): StakeProof<S, R> {
        source_to_pool(fountain, clock);
        let stake_amount = balance::value(&input);
        balance::join(&mut fountain.staked, input);
        let stake_weight = math::compute_weight(
            stake_amount,
            lock_time,
            fountain.min_lock_time,
            fountain.max_lock_time,
        );
        fountain.total_weight = fountain.total_weight + stake_weight;
        let fountain_id = object::id(fountain);
        let current_time = clock::timestamp_ms(clock);
        event::emit(StakeEvent<S, R> {
            fountain_id,
            stake_amount,
            stake_weight,
            lock_time,
            start_time: current_time,
        });
        StakeProof {
            id: object::new(ctx),
            fountain_id,
            stake_amount,
            start_uint: fountain.cumulative_unit,
            stake_weight,
            lock_until: current_time + lock_time,
        }
    }

    public fun claim<S, R>(
        clock: &Clock,
        fountain: &mut Fountain<S, R>,
        proof: &mut StakeProof<S, R>,
    ): Balance<R> {
        source_to_pool(fountain, clock);
        let fountain_id = proof.fountain_id;
        assert!(object::id(fountain) == fountain_id, EWrongFountainId);
        let reward_amount = (math::mul_factor_u128(
            (proof.stake_weight as u128),
            fountain.cumulative_unit - proof.start_uint,
            DISTRIBUTION_PRECISION,
            ) as u64);
        event::emit(ClaimEvent<S, R> {
            fountain_id,
            reward_amount,
            claim_time: clock::timestamp_ms(clock),
        });
        proof.start_uint = fountain.cumulative_unit;
        balance::split(&mut fountain.pool, reward_amount)
    }

    public fun unstake<S, R>(
        clock: &Clock,
        fountain: &mut Fountain<S, R>,
        proof: StakeProof<S, R>,
    ): (Balance<S>, Balance<R>) {
        source_to_pool(fountain, clock);
        let current_time = clock::timestamp_ms(clock);
        let reward = claim(clock, fountain, &mut proof);
        let StakeProof {
            id,
            fountain_id,
            stake_amount,
            start_uint: _,
            stake_weight,
            lock_until
        } = proof;
        assert!(object::id(fountain) == fountain_id, EWrongFountainId);
        assert!(current_time >= lock_until, EStillLocked);
        object::delete(id);
        fountain.total_weight = fountain.total_weight - stake_weight;
        event::emit(UnstakeEvent<S, R> {
            fountain_id,
            unstake_amount: stake_amount,
            unstake_weigth: stake_weight,
            end_time: current_time,
        });
        let returned_stake = balance::split(&mut fountain.staked, stake_amount);
        (returned_stake, reward)
    }

    public entry fun update_flow_rate<S, R>(
        admin_cap: &AdminCap,
        clock: &Clock,
        fountain: &mut Fountain<S, R>,
        flow_amount: u64,
        flow_interval: u64
    ) {
        assert!(admin_cap.fountain_id == object::id(fountain), EWrongFountainId);
        source_to_pool(fountain, clock);
        fountain.flow_amount = flow_amount;
        fountain.flow_interval = flow_interval;
    }

    public fun get_flow_rate<S, R>(fountain: &Fountain<S, R>): (u64, u64) {
        (fountain.flow_amount, fountain.flow_interval)
    }

    public fun get_lock_time_range<S, R>(fountain: &Fountain<S, R>): (u64, u64) {
        (fountain.min_lock_time, fountain.max_lock_time)
    }

    public fun get_source_balance<S, R>(fountain: &Fountain<S, R>): u64 {
        balance::value(&fountain.source)
    }

    public fun get_pool_balance<S, R>(fountain: &Fountain<S, R>): u64 {
        balance::value(&fountain.pool)
    }

    public fun get_staked_balance<S, R>(fountain: &Fountain<S, R>): u64 {
        balance::value(&fountain.staked)
    }

    public fun get_total_weight<S, R>(fountain: &Fountain<S, R>): u64 {
        fountain.total_weight
    }

    public fun get_cumulative_unit<S, R>(fountain: &Fountain<S, R>): u128 {
        fountain.cumulative_unit
    }

    public fun get_proof_stake_amount<S, R>(proof: &StakeProof<S, R>): u64 {
        proof.stake_amount
    }

    public fun get_proof_stake_weight<S, R>(proof: &StakeProof<S, R>): u64 {
        proof.stake_weight
    }

    public fun get_proof_lock_until<S, R>(proof: &StakeProof<S, R>): u64 {
        proof.lock_until
    }

    public fun get_latest_release_time<S, R>(fountain: &Fountain<S, R>): u64 {
        fountain.latest_release_time
    }

    public fun get_reward_amount<S, R>(
        fountain: &Fountain<S, R>,
        proof: &StakeProof<S, R>,
        current_time: u64,
    ): u64 {
        let virtual_released_amount = get_virtual_released_amount(fountain, current_time);
        let virtual_cumulative_unit = fountain.cumulative_unit + math::mul_factor_u128(
            (virtual_released_amount as u128),
            DISTRIBUTION_PRECISION,
            (fountain.total_weight as u128)
        );
        (math::mul_factor_u128((proof.stake_weight as u128), virtual_cumulative_unit - proof.start_uint, DISTRIBUTION_PRECISION) as u64)
    }

    public fun get_virtual_released_amount<S, R>(fountain: &Fountain<S, R>, current_time: u64): u64 {
        if (current_time > fountain.latest_release_time) {
            let interval = current_time - fountain.latest_release_time;
            let released_amount = math::mul_factor(
                fountain.flow_amount,
                interval, 
                fountain.flow_interval,
            );
            let source_balance = get_source_balance(fountain);
            if (released_amount > source_balance) {
                released_amount = source_balance;
            };
            released_amount
        } else {
            0
        }
    }

    fun release_resource<S, R>(fountain: &mut Fountain<S, R>, clock: &Clock): Balance<R> {
        let current_time = clock::timestamp_ms(clock);
        if (current_time > fountain.latest_release_time) {
            let interval = current_time - fountain.latest_release_time;
            let released_amount = math::mul_factor(
                fountain.flow_amount,
                interval, 
                fountain.flow_interval,
            );
            let source_balance = get_source_balance(fountain);
            if (released_amount > source_balance) {
                released_amount = source_balance;
            };
            fountain.latest_release_time = current_time;
            balance::split(&mut fountain.source, released_amount)
        } else {
            balance::zero()
        }
    }

    fun collect_resource<S, R>(fountain: &mut Fountain<S, R>, resource: Balance<R>) {
        let resource_amount = balance::value(&resource);
        if (resource_amount > 0) {
            balance::join(&mut fountain.pool, resource);
            fountain.cumulative_unit = fountain.cumulative_unit + math::mul_factor_u128(
                (resource_amount as u128),
                DISTRIBUTION_PRECISION,
                (fountain.total_weight as u128)
            );
        } else {
            balance::destroy_zero(resource);
        };
    }

    fun source_to_pool<S, R>(fountain: &mut Fountain<S, R>, clock: &Clock) {
        if (get_source_balance(fountain) > 0) {
            let resource = release_resource(fountain, clock);
            collect_resource(fountain, resource);
        } else {
            let current_time = clock::timestamp_ms(clock);
            if (current_time > fountain.latest_release_time) {
                fountain.latest_release_time = current_time;
            };
        }
    }

    #[test_only]
    public fun destroy_fountain_for_testing<S, R>(fountain: Fountain<S, R>) {
        let Fountain {
            id,
            source,
            flow_amount: _,
            flow_interval: _,
            pool,
            staked,
            total_weight: _,
            cumulative_unit: _,
            latest_release_time: _,
            min_lock_time: _,
            max_lock_time: _,
        } = fountain;
        object::delete(id);
        balance::destroy_for_testing(source);
        balance::destroy_for_testing(pool);
        balance::destroy_for_testing(staked);
    }

    #[test_only]
    public fun destroy_proof_for_testing<S, R>(proof: StakeProof<S, R>) {
        let StakeProof {
            id,
            fountain_id: _,
            stake_amount: _,
            start_uint: _,
            stake_weight: _,
            lock_until: _ 
        } = proof;
        object::delete(id);
    }
}
