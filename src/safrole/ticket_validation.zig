const std = @import("std");
const ArrayList = std.ArrayList;

const ring_vrf = @import("../ring_vrf.zig");

pub const entropy = @import("../entropy.zig");
pub const types = @import("../types.zig");

const Params = @import("../jam_params.zig").Params;
const StateTransition = @import("../state_delta.zig").StateTransition;

const trace = @import("../tracing.zig").scoped(.safrole);

const Error = @import("../safrole.zig").Error;

// Extracted ticket processing logic
pub fn processTicketExtrinsic(
    comptime params: Params,
    stx: *StateTransition(params),
    ticket_extrinsic: types.TicketsExtrinsic,
) Error![]types.TicketBody {
    const span = trace.span(.process_ticket_extrinsic);
    defer span.deinit();
    span.debug("Processing ticket extrinsic", .{});

    // in case we have no tickets leave early
    if (ticket_extrinsic.data.len == 0) {
        span.debug("No tickets in ticket extrinsic, leaving", .{});
        return &[_]types.TicketBody{};
    }

    // Process tickets if not in epoch's tail
    if (stx.time.current_slot_in_epoch >= params.ticket_submission_end_epoch_slot) {
        span.err("Received ticket extrinsic in epoch's tail", .{});
        return Error.UnexpectedTicket;
    }

    // Chapter 6.7 Ticketing and extrensics
    // Check the number of ticket attempts in the input when more than N we have a bad ticket attempt
    for (ticket_extrinsic.data) |extrinsic| {
        if (extrinsic.attempt >= params.max_ticket_entries_per_validator) {
            std.debug.print("attempt {d}\n", .{extrinsic.attempt});
            return Error.BadTicketAttempt;
        }
    }

    // We should not have more than K tickets in the input
    if (ticket_extrinsic.data.len > params.epoch_length) {
        return Error.TooManyTicketsInExtrinsic;
    }

    // Verify ticket envelope
    const gamma = try stx.ensure(.gamma);
    const eta_prime = try stx.ensure(.eta_prime);
    const verified_extrinsic = verifyTicketEnvelope(
        stx.allocator,
        params.validators_count,
        &gamma.z,
        eta_prime[2],
        ticket_extrinsic.data,
    ) catch |e| {
        if (e == error.SignatureVerificationFailed) {
            return Error.BadTicketProof;
        } else return e;
    };
    errdefer stx.allocator.free(verified_extrinsic);

    // Chapter 6.7: The tickets should be in order of their implied identifier
    var index: usize = 0;
    while (index < verified_extrinsic.len) : (index += 1) {
        const current_ticket = verified_extrinsic[index];

        // Check order and duplicates with previous ticket
        if (index > 0) {
            const order = std.mem.order(u8, &current_ticket.id, &verified_extrinsic[index - 1].id);
            switch (order) {
                .lt => return Error.BadTicketOrder,
                .eq => return Error.DuplicateTicket,

                .gt => {},
            }
        }

        // Check for duplicates in gamma_a using binary search
        std.debug.assert(blk: {
            if (gamma.a.len <= 1) break :blk true;
            var i: usize = 1;
            while (i < gamma.a.len) : (i += 1) {
                if (!std.mem.lessThan(u8, &gamma.a[i - 1].id, &gamma.a[i].id)) break :blk false;
            }
            break :blk true;
        });

        const position = std.sort.binarySearch(types.TicketBody, gamma.a, current_ticket, struct {
            fn order(context: types.TicketBody, item: types.TicketBody) std.math.Order {
                return std.mem.order(u8, &context.id, &item.id);
            }
        }.order);

        if (position != null) {
            span.warn("Found duplicate ticket ID: {s}", .{std.fmt.fmtSliceHexLower(&current_ticket.id)});
            span.trace("Current gamma_a contents:", .{});
            for (gamma.a, 0..) |ticket, idx| {
                span.trace("  [{d}] ID: {s}", .{ idx, std.fmt.fmtSliceHexLower(&ticket.id) });
            }
            return Error.DuplicateTicket;
        }
    }

    return verified_extrinsic;
}

fn verifyTicketEnvelope(
    allocator: std.mem.Allocator,
    ring_size: usize,
    gamma_z: *const types.BandersnatchVrfRoot,
    n2: types.Entropy,
    extrinsic: []const types.TicketEnvelope,
) ![]types.TicketBody {
    const span = trace.span(.verify_ticket_envelope);
    defer span.deinit();
    span.debug("Verifying {d} ticket envelopes", .{extrinsic.len});
    span.trace("Ring size: {d}, gamma_z: {any}, n2: {any}", .{
        ring_size,
        std.fmt.fmtSliceHexLower(gamma_z),
        std.fmt.fmtSliceHexLower(&n2),
    });

    // For now, map the extrinsic to the ticket setting the ticketbody.id to all 0s
    var tickets = try allocator.alloc(types.TicketBody, extrinsic.len);
    errdefer {
        span.debug("Cleanup after error - freeing tickets", .{});
        allocator.free(tickets);
    }

    const empty_aux_data = [_]u8{};

    if (extrinsic.len > 1) {
        // Use batch verification for multiple tickets - much faster for parallel processing
        span.debug("Using batch verification for {d} tickets", .{extrinsic.len});
        
        // Optimization: Use stack allocation for small batches (common case for tiny params)
        const MAX_STACK_TICKETS = 16;
        
        if (extrinsic.len <= MAX_STACK_TICKETS) {
            // Stack-allocated arrays - ZERO heap allocations for tiny params!
            var stack_vrf_inputs: [MAX_STACK_TICKETS][]const u8 = undefined;
            var stack_vrf_buffers: [MAX_STACK_TICKETS][48]u8 = undefined;
            var stack_aux_data: [MAX_STACK_TICKETS][]const u8 = undefined;
            var stack_signatures: [MAX_STACK_TICKETS]*const types.BandersnatchRingVrfSignature = undefined;
            
            // Setup stack arrays
            for (extrinsic, 0..) |extr, i| {
                const vrf_input_data = "jam_ticket_seal" ++ n2 ++ [_]u8{extr.attempt};
                @memcpy(&stack_vrf_buffers[i], vrf_input_data);
                
                stack_vrf_inputs[i] = &stack_vrf_buffers[i];
                stack_aux_data[i] = &empty_aux_data;
                stack_signatures[i] = &extr.signature;
            }
            
            // Use stack arrays for batch verification
            var batch_result = ring_vrf.batchVerifyRingSignaturesAgainstCommitment(
                allocator,
                gamma_z,
                ring_size,
                stack_vrf_inputs[0..extrinsic.len],
                stack_aux_data[0..extrinsic.len],
                stack_signatures[0..extrinsic.len],
            ) catch |e| {
                if (e == error.SignatureVerificationFailed) {
                    return Error.SignatureVerificationFailed;
                } else return e;
            };
            defer batch_result.deinit(allocator);
            
            // Process stack-based results
            for (extrinsic, 0..) |extr, i| {
                if (!batch_result.results[i]) {
                    span.err("Batch verification failed for ticket [{d}]", .{i});
                    return Error.SignatureVerificationFailed;
                }
                
                span.trace("Verified ticket envelope [{d}]: attempt={d}, output={s}", .{
                    i, extr.attempt, std.fmt.fmtSliceHexLower(&batch_result.outputs[i])
                });
                
                tickets[i].attempt = extr.attempt;
                tickets[i].id = batch_result.outputs[i];
            }
        } else {
            // Heap-allocated arrays for larger batches
            span.debug("Using heap allocation for large batch ({d} > {d} tickets)", .{extrinsic.len, MAX_STACK_TICKETS});
            
            var vrf_inputs = try allocator.alloc([]const u8, extrinsic.len);
            defer allocator.free(vrf_inputs);
            
            var vrf_input_buffers = try allocator.alloc([48]u8, extrinsic.len);
            defer allocator.free(vrf_input_buffers);
            
            var aux_data_array = try allocator.alloc([]const u8, extrinsic.len);
            defer allocator.free(aux_data_array);
            
            var signatures = try allocator.alloc(*const types.BandersnatchRingVrfSignature, extrinsic.len);
            defer allocator.free(signatures);
            
            // Setup inputs for heap-based batch verification
            for (extrinsic, 0..) |extr, i| {
                const vrf_input_data = "jam_ticket_seal" ++ n2 ++ [_]u8{extr.attempt};
                @memcpy(&vrf_input_buffers[i], vrf_input_data);
                
                vrf_inputs[i] = &vrf_input_buffers[i];
                aux_data_array[i] = &empty_aux_data;
                signatures[i] = &extr.signature;
            }
            
            // Perform heap-based batch verification
            var batch_result = ring_vrf.batchVerifyRingSignaturesAgainstCommitment(
                allocator,
                gamma_z,
                ring_size,
                vrf_inputs,
                aux_data_array,
                signatures,
            ) catch |e| {
                if (e == error.SignatureVerificationFailed) {
                    return Error.SignatureVerificationFailed;
                } else return e;
            };
            defer batch_result.deinit(allocator);
            
            // Process heap-based results
            for (extrinsic, 0..) |extr, i| {
                if (!batch_result.results[i]) {
                    span.err("Batch verification failed for ticket [{d}]", .{i});
                    return Error.SignatureVerificationFailed;
                }
                
                span.trace("Verified ticket envelope [{d}]: attempt={d}, output={s}", .{
                    i, extr.attempt, std.fmt.fmtSliceHexLower(&batch_result.outputs[i])
                });
                
                tickets[i].attempt = extr.attempt;
                tickets[i].id = batch_result.outputs[i];
            }
        }
    } else {
        // Single ticket - use regular verification to avoid allocation overhead
        for (extrinsic, 0..) |extr, i| {
            span.trace("Verifying ticket envelope [{d}]:", .{i});
            span.trace("  Attempt: {d}", .{extr.attempt});
            span.trace("  Signature: {s}", .{std.fmt.fmtSliceHexLower(&extr.signature)});

            // TODO: rewrite
            const vrf_input = "jam_ticket_seal" ++ n2 ++ [_]u8{extr.attempt};

            const output = try ring_vrf.verifyRingSignatureAgainstCommitment(
                gamma_z,
                ring_size,
                vrf_input,
                &empty_aux_data,
                &extr.signature,
            );
            span.trace("  VRF output (ticket ID): {s}", .{std.fmt.fmtSliceHexLower(&output)});

            tickets[i].attempt = extr.attempt;
            tickets[i].id = output;
        }
    }

    return tickets;
}
