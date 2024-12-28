const std = @import("std");
const types = @import("../types.zig");
const jamstate = @import("../state.zig");
const jam_params = @import("../jam_params.zig");

// Helper function to print validator information with proper indentation
fn printValidatorSet(validators: ?types.ValidatorSet, name: []const u8, symbol: []const u8) void {
    if (validators) |set| {
        std.debug.print("    {s} Validators ({s}): {d} validators\n", .{ name, symbol, set.validators.len });
        for (set.validators, 0..) |validator, i| {
            // Using fmtSliceHexLower for consistent hex formatting
            std.debug.print("      {s}[{d}]: 0x{s}\n", .{
                symbol,
                i,
                std.fmt.fmtSliceHexLower(validator.bandersnatch[0..4]),
            });
        }
    }
}

// Helper function to print ticket information
fn printTicket(ticket: types.TicketBody, index: usize) void {
    std.debug.print("      Ticket[{d}]: ID=0x{s}, Attempt={d}\n", .{
        index,
        std.fmt.fmtSliceHexLower(ticket.id[0..4]),
        ticket.attempt,
    });
}

// Helper function to print public key information
fn printPublicKey(key: types.BandersnatchPublic, index: usize) void {
    std.debug.print("      Key[{d}]: 0x{s}\n", .{
        index,
        std.fmt.fmtSliceHexLower(key[0..4]),
    });
}

// Helper function to print important state information
pub fn printStateTransitionDebug(
    comptime params: jam_params.Params,
    state: *const jamstate.JamState(params),
    block: *const types.Block,
) void {
    // Print a separator for visual clarity using minimal style
    std.debug.print("\n▶ State Transition Debug\n", .{});

    // Time-related information section
    const current_epoch = block.header.slot / params.epoch_length;
    const slot_in_epoch = block.header.slot % params.epoch_length;

    std.debug.print("\n→ Time Information\n", .{});
    std.debug.print("    Slot: {d}\n", .{block.header.slot});
    std.debug.print("    Current Epoch: {d}\n", .{current_epoch});
    std.debug.print("    Slot in Epoch: {d}\n", .{slot_in_epoch});
    std.debug.print("    Block Author Index: {d}\n", .{block.header.author_index});

    // Validator sets section
    std.debug.print("\n→ Validator Sets\n", .{});
    printValidatorSet(state.kappa, "Active", "κ");
    printValidatorSet(state.iota, "Upcoming", "ι");
    printValidatorSet(state.lambda, "Historical", "λ");

    // Consensus state section
    std.debug.print("\n→ Consensus State\n", .{});
    if (state.gamma) |gamma| {
        printValidatorSet(gamma.k, "Active", "γk");

        std.debug.print("    Consensus Mode (γs):\n", .{});
        switch (gamma.s) {
            .tickets => |tickets| {
                std.debug.print("      Mode: Tickets (count: {d})\n", .{tickets.len});
                for (tickets, 0..) |ticket, i| {
                    printTicket(ticket, i);
                }
            },
            .keys => |keys| {
                std.debug.print("      Mode: Fallback Keys (count: {d})\n", .{keys.len});
                for (keys, 0..) |key, i| {
                    printPublicKey(key, i);
                }
            },
        }
    }

    // Entropy state section
    if (state.eta) |eta| {
        std.debug.print("\n→ Entropy State (η)\n", .{});
        for (eta, 0..) |e, i| {
            // Using fmtSliceHexLower for start and end of entropy
            std.debug.print("    η[{d}]: 0x{s}...{s}\n", .{
                i,
                std.fmt.fmtSliceHexLower(e[0..4]),
                std.fmt.fmtSliceHexLower(e[28..32]),
            });
        }
    }
}
