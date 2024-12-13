const std = @import("std");
const types = @import("types.zig");
const state = @import("state.zig");

/// Process a block's assurance extrinsic to determine which work reports have
/// become available based on validator assurances
pub fn processAssuranceExtrinsic(
    comptime params: @import("jam_params.zig").Params,
    allocator: std.mem.Allocator,
    assurances_extrinsic: types.AssurancesExtrinsic, // assume this is validator TODO: use type system
    pending_reports: *state.Rho(params.core_count),
) ![]types.WorkReport {
    // Track which cores have super-majority assurance
    var assured_reports = std.ArrayList(types.WorkReport).init(allocator);
    defer assured_reports.deinit();

    // Just track counts per core instead of individual validator bits
    var core_assurance_counts = [_]usize{0} ** params.core_count;

    // Process each assurance in the extrinsic
    for (assurances_extrinsic.data) |assurance| {
        const bytes_per_field = (params.core_count + 7) / 8;

        var byte_idx: usize = 0;
        while (byte_idx < bytes_per_field) : (byte_idx += 1) {
            const byte = assurance.bitfield[byte_idx];
            if (byte == 0) continue; // Skip empty bytes

            var bit_pos: u3 = 0;
            while (bit_pos < 8) : (bit_pos += 1) {
                const core_idx = byte_idx * 8 + bit_pos;
                if (core_idx >= params.core_count) break;

                if ((byte & (@as(u8, 1) << bit_pos)) != 0) {
                    core_assurance_counts[core_idx] += 1;
                }
            }
        }
    }

    // Check which cores have super-majority
    const super_majority = params.validators_super_majority;

    for (core_assurance_counts, 0..) |count, core_idx| {
        // If super-majority reached and core has pending report
        if (count > super_majority and
            pending_reports.items[core_idx] != null)
        {
            try assured_reports.append(try pending_reports.reports[core_idx].?.assignment.deepClone(allocator));
        }
    }

    return assured_reports.toOwnedSlice();
}
