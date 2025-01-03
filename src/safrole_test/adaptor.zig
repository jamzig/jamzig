/// Adapts the TestVector format to our transition function
const std = @import("std");

pub const types = @import("../types.zig");
pub const state = @import("../state.zig");
pub const safrole_types = @import("../safrole/types.zig");
pub const safrole_test_vector = @import("../jamtestvectors/safrole.zig");

const Allocator = std.mem.Allocator;
pub const Params = @import("../jam_params.zig").Params;

pub const safrole = @import("../safrole.zig");

// Constant
pub const TransitionResult = struct {
    output: safrole_test_vector.Output,
    state: ?safrole_test_vector.State,

    pub fn deinit(self: TransitionResult, allocator: std.mem.Allocator) void {
        if (self.state != null) {
            self.state.?.deinit(allocator);
        }
        self.output.deinit(allocator);
    }
};

pub fn transition(
    comptime params: Params,
    allocator: std.mem.Allocator,
    pre_state: safrole_test_vector.State,
    input: safrole_test_vector.Input,
) !TransitionResult {
    var post_psi = state.Psi.init(allocator);
    try post_psi.registerOffenders(pre_state.post_offenders);

    const gamma = try GammaFromTestVectorState(
        params.validators_count,
        params.epoch_length,
        allocator,
        pre_state,
    );
    defer gamma.deinit(allocator);

    const iota = try pre_state.gamma.iota.deepClone(allocator);
    defer iota.deinit(allocator);

    const kappa = try pre_state.gamma.kappa.deepClone(allocator);
    defer kappa.deinit(allocator);

    const lambda = try pre_state.gamma.lambda.deepClone(allocator);
    defer lambda.deinit(allocator);

    const transition_time = params.Time().init(pre_state.gamma.tau, input.slot);

    const stf = @import("../stf.zig");
    const eta_prime = stf.transitionEta(&pre_state.gamma.eta, input.entropy);

    // we need to transition eta here first using the entropy
    var result = stf.transitionSafrole(
        params,
        allocator,
        &transition_time,
        &eta_prime,
        &kappa,
        &gamma,
        &iota,
        &post_psi,
        input.extrinsic,
    ) catch |e| {
        const test_vector_error = switch (e) {
            error.bad_slot => safrole_test_vector.ErrorCode.bad_slot,
            error.unexpected_ticket => safrole_test_vector.ErrorCode.unexpected_ticket,
            error.bad_ticket_order => safrole_test_vector.ErrorCode.bad_ticket_order,
            error.bad_ticket_proof => safrole_test_vector.ErrorCode.bad_ticket_proof,
            error.bad_ticket_attempt => safrole_test_vector.ErrorCode.bad_ticket_attempt,
            error.duplicate_ticket => safrole_test_vector.ErrorCode.duplicate_ticket,
            error.too_many_tickets_in_extrinsic => @panic("Unmapped error"),
            else => @panic("unmapped error"),
        };
        return .{
            .output = .{ .err = test_vector_error },
            .state = null,
        };
    };
    defer result.deinit(allocator);

    const test_vector_post_state = try jamStateToTestVectorState(
        params,
        allocator,
        &transition_time,
        &eta_prime,
        &iota,
        &result.post_state,
        pre_state.post_offenders,
    );
    std.debug.print("{s}\n", .{types.fmt.format(&test_vector_post_state)});

    return TransitionResult{
        .output = .{
            .ok = safrole_test_vector.OutputMarks{
                .epoch_mark = result.epoch_marker,
                .tickets_mark = result.ticket_marker,
            },
        },
        .state = test_vector_post_state,
    };
}

fn GammaFromTestVectorState(
    comptime validators_count: u32,
    comptime epoch_length: u32,
    allocator: Allocator,
    tvstate: safrole_test_vector.State,
) !state.Gamma(validators_count, epoch_length) {
    // Initialize with undefined since we'll set all fields
    var gamma: state.Gamma(validators_count, epoch_length) = undefined;

    // First safely copy gamma_k (BandersnatchPublic keys)
    gamma.k = try tvstate.gamma.gamma_k.deepClone(allocator);
    errdefer gamma.k.deinit(allocator);

    // Copy gamma_a (ticket accumulator)
    gamma.a = try allocator.dupe(types.TicketBody, tvstate.gamma.gamma_a);
    errdefer allocator.free(gamma.a);

    // Handle gamma_s union type
    switch (tvstate.gamma.gamma_s) {
        .tickets => |tickets| {
            gamma.s = .{
                .tickets = try allocator.dupe(types.TicketBody, tickets),
            };
            errdefer if (gamma.s == .tickets) allocator.free(gamma.s.tickets);
        },
        .keys => |keys| {
            gamma.s = .{
                .keys = try allocator.dupe(types.BandersnatchPublic, keys),
            };
            errdefer if (gamma.s == .keys) allocator.free(gamma.s.keys);
        },
    }

    // Copy gamma_z (bandersnatch ring root)
    gamma.z = tvstate.gamma.gamma_z;

    return gamma;
}

fn jamStateToTestVectorState(
    comptime params: Params,
    allocator: std.mem.Allocator,
    transition_time: *const params.Time(),
    eta_prime: *const types.Eta,
    iota: *const types.Iota,
    jam_state: *const state.JamState(params),
    post_offenders: []const types.Ed25519Public,
) !safrole_test_vector.State {
    // Create test vector state with gamma from jam state
    return safrole_test_vector.State{
        .gamma = safrole_types.State{
            .tau = transition_time.current_slot,
            .eta = eta_prime.*,
            .lambda = try jam_state.lambda.?.deepClone(allocator),
            .kappa = try jam_state.kappa.?.deepClone(allocator),
            .gamma_k = try jam_state.gamma.?.k.deepClone(allocator),
            .iota = try iota.deepClone(allocator),
            .gamma_a = try allocator.dupe(types.TicketBody, jam_state.gamma.?.a),
            .gamma_s = try jam_state.gamma.?.s.deepClone(allocator),
            .gamma_z = jam_state.gamma.?.z,
        },
        .post_offenders = try allocator.dupe(types.Ed25519Public, post_offenders),
    };
}
