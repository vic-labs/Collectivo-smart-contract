module collectivo::collectivo;

public struct COLLECTIVO has drop {}

public struct AdminCap has key { id: UID }

fun init(_otw: COLLECTIVO, ctx: &mut TxContext) {
    let admin_cap = AdminCap { id: object::new(ctx) };
    transfer::transfer(admin_cap, ctx.sender());
}

#[test_only]
public fun issue_admin_cap(ctx: &mut TxContext) {
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender())
}

#[test_only]
public fun issue_otw(_ctx: &mut TxContext): COLLECTIVO {
    COLLECTIVO {}
}
