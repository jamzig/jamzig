const std = @import("std");
const state_d = @import("../state_delta.zig");
const StateTransition = state_d.StateTransition;
const Params = @import("../jam_params.zig").Params;
const types = @import("../types.zig");
const safrole = @import("../safrole.zig");
const tracing = @import("../tracing.zig");
const trace = tracing.scoped(.stf);

pub fn transition(
    comptime params: Params,
    stx: *StateTransition(params),
    extrinsic_tickets: types.TicketsExtrinsic,
) !safrole.Result {
    const span = trace.span(.transition_safrole);
    defer span.deinit();

    return try safrole.transition(
        params,
        stx,
        extrinsic_tickets,
    );
}
