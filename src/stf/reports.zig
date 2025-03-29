const std = @import("std");
const state = @import("../state.zig");
const types = @import("../types.zig");

const Params = @import("../jam_params.zig").Params;
const StateTransition = @import("../state_delta.zig").StateTransition;

const reports = @import("../reports.zig");

pub const Error = error{};

pub fn accumulateWorkReports(
    comptime params: Params,
    stx: *StateTransition(params),
) !void {
    _ = stx;
    // Process work reports and transition δ, χ, ι, and φ
    @panic("Not implemented");
}

pub fn transition(
    comptime params: Params,
    allocator: std.mem.Allocator,
    stx: *StateTransition(params),
    block: *const types.Block,
) !void {
    // NOTE: disable to make test passing, track pi based on result?
    // const pi: *state.Pi = try stx.ensure(.pi_prime);

    const validated = try reports.ValidatedGuaranteeExtrinsic.validate(
        params,
        allocator,
        stx,
        block.extrinsic.guarantees,
    );

    // Process
    var result = try reports.processGuaranteeExtrinsic(
        params,
        allocator,
        stx,
        validated,
    );
    defer result.deinit(allocator);

    const pi: *state.Pi = try stx.ensure(.pi_prime);
    const kappa: *const types.ValidatorSet = try stx.ensure(.kappa);
    for (result.reporters) |validator_key| {
        const validator_index = try kappa.findValidatorIndex(.Ed25519Public, validator_key);
        var stats = try pi.getValidatorStats(validator_index);
        stats.updateReportsGuaranteed(1);
    }

    // Since we have validated guarantees here lets run through them
    // and update appropiate core statistics.
    // TODO: put this in it own statistics stf
    for (validated.guarantees) |guarantee| {
        const core_stats = try pi.getCoreStats(guarantee.report.core_index);

        const report = guarantee.report;

        for (report.results) |r| {
            core_stats.gas_used += r.refine_load.gas_used;
            core_stats.imports += r.refine_load.imports;
            core_stats.extrinsic_count += r.refine_load.extrinsic_count;
            core_stats.extrinsic_size += r.refine_load.extrinsic_size;
            core_stats.exports += r.refine_load.exports;

            // This is set when we have an availability assurance
            // core_stats.popularity += 0;
        }

        core_stats.bundle_size += report.package_spec.length;

        // FIXME: These should be based on the ready reports, as this
        // signals they are assured and thus loaded
        core_stats.da_load += report.package_spec.exports_count +
            (params.segmentSizeInOctets() *
                try std.math.divCeil(u32, report.package_spec.exports_count * 65, 64));
    }
}
