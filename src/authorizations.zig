const std = @import("std");
const trace = @import("tracing.zig").scoped(.authorizations);
const types = @import("types.zig");

const Params = @import("jam_params.zig").Params;

const state = @import("state.zig");
const state_delta = @import("state_delta.zig");

const auth_pool = @import("authorizer_pool.zig");
const auth_queue = @import("authorizer_queue.zig");

pub const CoreAuthorizer = struct {
    core: types.CoreIndex,
    auth_hash: types.OpaqueHash,
};

// Process authorizations for a block
// Since α′ is dependent on φ′, practically speaking, this step must be
// computed after accumulation, the stage in which φ′ is defined.
pub fn processAuthorizations(
    comptime params: Params,
    stx: *state_delta.StateTransition(params),
    authorizers: []const CoreAuthorizer,
) !void {
    const span = trace.span(.process_authorizations);
    defer span.deinit();

    span.debug("Processing authorizations for slot {d}", .{stx.time.current_slot});
    span.debug("Number of core authorizers: {d}", .{authorizers.len});

    const alpha_prime: *state.Alpha(params.core_count, params.max_authorizations_pool_items) =
        try stx.ensure(.alpha_prime);

    const phi_prime: *state.Phi(params.core_count, params.max_authorizations_queue_items) =
        try stx.ensure(.phi_prime);

    const process_span = span.child(.process_authorizers);
    defer process_span.deinit();
    process_span.debug("Processing {d} input authorizers", .{authorizers.len});

    for (authorizers, 0..) |authorizer, i| {
        const auth_span = process_span.child(.authorizer);
        defer auth_span.deinit();

        const core = authorizer.core;
        const auth_hash = authorizer.auth_hash;

        auth_span.debug("Processing authorizer {d}/{d} for core {d}", .{ i + 1, authorizers.len, core });
        auth_span.trace("Auth hash: {}", .{std.fmt.fmtSliceHexLower(&auth_hash)});

        // Skip if core is invalid
        if (core >= params.core_count) {
            auth_span.warn("Invalid core: {d} (max: {d})", .{ core, params.core_count - 1 });
            return error.InvalidCore;
        }

        // First, check if the auth is already in the pool
        const is_authorized = alpha_prime.isAuthorized(core, auth_hash);
        auth_span.trace("Auth in pool check result: {}", .{is_authorized});

        if (is_authorized) {
            auth_span.debug("Auth already in pool for core {d}, removing", .{core});

            const remove_span = auth_span.child(.remove_authorizer);
            defer remove_span.deinit();
            alpha_prime.removeAuthorizer(core, auth_hash);
            remove_span.debug("Successfully removed authorizer from pool", .{});
        } else {
            auth_span.debug("Auth not in pool for core {d}, nothing to remove", .{core});
        }
    }

    const rotation_span = span.child(.rotation);
    defer rotation_span.deinit();
    rotation_span.debug("Processing authorization rotation across {d} cores", .{params.core_count});

    for (0..params.core_count) |core_index| {
        const core_span = rotation_span.child(.core);
        defer core_span.deinit();
        core_span.debug("Processing core {d}", .{core_index});

        const queue_items = phi_prime.queue[core_index].items;
        core_span.trace("Queue items for core {d}: {d} available", .{ core_index, queue_items.len });

        if (queue_items.len == 0) {
            core_span.debug("Core {d} has empty queue, skipping", .{core_index});
            continue;
        }

        const auth_index = @mod(stx.time.current_slot, queue_items.len);
        core_span.trace("Selected auth index {d} for slot {d}", .{ auth_index, stx.time.current_slot });

        const pool_size = alpha_prime.pools[core_index].len;
        const max_pool_size = params.max_authorizations_pool_items;
        core_span.trace("Pool size for core {d}: {d}/{d}", .{ core_index, pool_size, max_pool_size });

        // We always select an item from the queue and place it at position 0 of the pool,
        // shifting all other items up by one position.
        const auth_item = queue_items[auth_index];
        core_span.debug("Adding auth from queue to pool: {}", .{std.fmt.fmtSliceHexLower(&auth_item)});

        const add_span = core_span.child(.add_authorizer);
        defer add_span.deinit();

        // Now we need to shift all items up by one position
        var pool = &alpha_prime.pools[core_index];

        // Check if the pool is already at maximum capacity
        if (pool.len >= params.max_authorizations_pool_items) {
            // Pool is full, shift everything down by one position (removing the oldest)
            const pool_slice = pool.slice();
            for (0..pool_slice.len - 1) |i| {
                pool_slice[i] = pool_slice[i + 1];
            }

            // Set the new auth at the last position
            pool_slice[pool_slice.len - 1] = auth_item;
        } else {
            // Pool has space, simply append the new auth
            try pool.append(auth_item);
        }

        add_span.debug("Successfully added authorizer to pool at position 0", .{});
    }

    span.debug("Authorization processing complete for slot {d}", .{stx.time.current_slot});
}

pub fn verifyAuthorizationsExtrinsicPre(
    comptime params: anytype,
    slot: types.TimeSlot,
    authorizers: []const CoreAuthorizer,
) !void {
    const span = trace.span(.verify_pre);
    defer span.deinit();

    span.debug("Pre-verification of authorizations for slot {d}", .{slot});
    span.trace("Number of authorizers: {d}", .{authorizers.len});
    span.trace("Parameters: core_count={d}", .{params.core_count});

    // No pre-verification requirements for authorizations
    span.debug("No pre-verification requirements, check passed", .{});
    return;
}

pub fn verifyAuthorizationsExtrinsicPost(
    comptime params: anytype,
    alpha_prime: anytype,
    phi_prime: anytype,
    authorizers: []const CoreAuthorizer,
) !void {
    const span = trace.span(.verify_post);
    defer span.deinit();

    span.debug("Post-verification of authorizations", .{});
    span.trace("Number of authorizers: {d}", .{authorizers.len});
    span.trace("Parameters: core_count={d}", .{params.core_count});

    // Report alpha_prime and phi_prime state (debugging purposes)
    span.trace("Alpha prime pool size by core:", .{});
    for (0..params.core_count) |core_index| {
        const pool_size = if (core_index < alpha_prime.pools.len) alpha_prime.pools[core_index].len else 0;
        span.trace("  Core {d}: {d} authorizers", .{ core_index, pool_size });
    }

    span.trace("Phi prime queue size by core:", .{});
    for (0..params.core_count) |core_index| {
        const queue_size = phi_prime.getQueueLength(core_index);
        span.trace("  Core {d}: {d} authorizers", .{ core_index, queue_size });
    }

    // No post-verification requirements for authorizations
    span.debug("No post-verification requirements, check passed", .{});
    return;
}
