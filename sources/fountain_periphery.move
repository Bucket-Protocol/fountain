module bucket_fountain::fountain_periphery {
   
    use sui::tx_context::{Self, TxContext};
    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use bucket_fountain::fountain_core::{Self as core, Fountain, StakeProof};

    public entry fun create_fountain<S, R>(
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
        ctx: &mut TxContext,
    ) {
        let fountain = core::new_fountain<S, R>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
            ctx,
        );
        transfer::public_share_object(fountain);
    }

    public entry fun create_fountain_with_admin_cap<S, R>(
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
        ctx: &mut TxContext,
    ) {
        let (fountain, admin_cap)= core::new_fountain_with_admin_cap<S, R>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
            ctx,
        );
        transfer::public_share_object(fountain);
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
    }

    public entry fun supply<S, R>(clock: &Clock, fountain: &mut Fountain<S, R>, resource: Coin<R>) {
        let resource = coin::into_balance(resource);
        core::supply(clock, fountain, resource);
    }

    public entry fun airdrop<S, R>(fountain: &mut Fountain<S, R>, resource: Coin<R>) {
        let resource = coin::into_balance(resource);
        core::airdrop(fountain, resource);
    }

    public entry fun tune<S, R>(fountain: &mut Fountain<S, R>, resource: Coin<R>) {
        let resource = coin::into_balance(resource);
        core::tune(fountain, resource);
    }

    public entry fun stake<S, R>(
        clock: &Clock,
        fountain: &mut Fountain<S, R>,
        input: Coin<S>,
        lock_time: u64,
        ctx: &mut TxContext,
    ) {
        let input = coin::into_balance(input);
        let proof = core::stake(clock, fountain, input, lock_time, ctx);
        transfer::public_transfer(proof, tx_context::sender(ctx));
    }

    public entry fun claim<S, R>(
        clock: &Clock,
        fountain: &mut Fountain<S, R>,
        proof: &mut StakeProof<S, R>,
        ctx: &mut TxContext,
    ) {
        let reward = core::claim(clock, fountain, proof);
        let reward = coin::from_balance(reward, ctx);
        transfer::public_transfer(reward, tx_context::sender(ctx));
    }

    public entry fun unstake<S, R>(
        clock: &Clock,
        fountain: &mut Fountain<S, R>,
        proof: StakeProof<S, R>,
        ctx: &mut TxContext,
    ) {
        let (unstake_output, reward) = core::unstake(clock, fountain, proof);
        let unstake_output = coin::from_balance(unstake_output, ctx);
        let reward = coin::from_balance(reward, ctx);
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(unstake_output, sender);
        transfer::public_transfer(reward, sender);
    }
}