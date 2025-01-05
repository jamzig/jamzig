const std = @import("std");
const Allocator = std.mem.Allocator;

const utils = @import("../utils.zig");
const types = @import("../types.zig");
const state = @import("../state.zig");
const JamState = state.JamState;
const Block = types.Block;
const Header = types.Header;

const state_d = @import("../state_delta.zig");
const StateTransition = state_d.StateTransition;
const Params = @import("../jam_params.zig").Params;

const tracing = @import("../tracing.zig");
const trace = tracing.scoped(.stf);

const time_transition = @import("time.zig");
const recent_history = @import("recent_history.zig");
const consensus = @import("consensus.zig"); 
const disputes = @import("disputes.zig");
const services = @import("services.zig");
const authorization = @import("authorization.zig");

const Error = error{
    BadSlot, // Header contains bad slot
};

pub fn stateTransition(
    comptime params: Params,
    allocator: Allocator,
    current_state: *const JamState(params),
    new_block: *const Block,
) !JamState(params) {
    const span = trace.span(.state_transition);
    defer span.deinit();
    span.debug("Starting state transition", .{});
    span.trace("New block header hash: {any}", .{std.fmt.fmtSliceHexLower(&new_block.header.parent)});

    std.debug.assert(current_state.ensureFullyInitialized() catch false);

    const transition_time = params.Time().init(current_state.tau.?, new_block.header.slot);
    var state_transition = try StateTransition(params).init(allocator, current_state, transition_time);
    errdefer state_transition.deinit();

    span.debug("Starting time transition (τ')", .{});
    try time_transition.transitionTime(
        params,
        &state_transition,
        new_block.header.slot,
    );

    span.debug("Starting recent history transition (β')", .{});
    try recent_history.transitionRecentHistory(
        params,
        &state_transition,
        new_block,
    );

    span.debug("Starting PSI initialization", .{});

    span.debug("Starting Safrole consensus transition", .{});

    // Extract entropy from block header's entropy source
    span.debug("Extracting entropy from block header", .{});
    const entropy = try @import("../crypto/bandersnatch.zig")
        .Bandersnatch.Signature
        .fromBytes(new_block.header.entropy_source)
        .outputHash();
    span.trace("Block entropy={any}", .{std.fmt.fmtSliceHexLower(&entropy)});

    span.debug("Starting epoch transition", .{});
    try consensus.transitionEta(params, &state_transition, entropy);

    span.debug("Starting safrole transition", .{});
    var markers = try consensus.transitionSafrole(
        params,
        &state_transition,
        new_block.extrinsic.tickets,
    );
    defer markers.deinit(allocator);

    span.debug("State transition completed successfully", .{});

    return try state_transition.cloneBaseAndMerge();
}

// Re-export component types and functions
pub const time = time_transition;
pub const history = recent_history;
pub const safrole = consensus;
