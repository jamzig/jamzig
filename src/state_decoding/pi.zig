const std = @import("std");
const testing = std.testing;
const validator_statistics = @import("../validator_stats.zig");
const codec = @import("../codec.zig");

const Pi = validator_statistics.Pi;

const ValidatorStats = validator_statistics.ValidatorStats;
const CoreActivityRecord = validator_statistics.CoreActivityRecord;
const ServiceActivityRecord = validator_statistics.ServiceActivityRecord;
const ValidatorIndex = @import("../types.zig").ValidatorIndex;
const ServiceId = @import("../types.zig").ServiceId;

pub fn decode(validators_count: u32, core_count: u32, reader: anytype, allocator: std.mem.Allocator) !Pi {
    var pi = try Pi.init(allocator, validators_count, core_count);
    errdefer pi.deinit();

    try decodeEpochStats(validators_count, reader, &pi.current_epoch_stats);
    try decodeEpochStats(validators_count, reader, &pi.previous_epoch_stats);
    try decodeCoreStats(core_count, reader, &pi.core_stats);
    try decodeServiceStats(reader, &pi.service_stats);

    return pi;
}

fn decodeEpochStats(validators_count: u32, reader: anytype, stats: *std.ArrayList(ValidatorStats)) !void {
    for (0..validators_count) |_| {
        const blocks_produced = try reader.readInt(u32, .little);
        const tickets_introduced = try reader.readInt(u32, .little);
        const preimages_introduced = try reader.readInt(u32, .little);
        const octets_across_preimages = try reader.readInt(u32, .little);
        const reports_guaranteed = try reader.readInt(u32, .little);
        const availability_assurances = try reader.readInt(u32, .little);

        try stats.append(ValidatorStats{
            .blocks_produced = blocks_produced,
            .tickets_introduced = tickets_introduced,
            .preimages_introduced = preimages_introduced,
            .octets_across_preimages = octets_across_preimages,
            .reports_guaranteed = reports_guaranteed,
            .availability_assurances = availability_assurances,
        });
    }
}

fn decodeCoreStats(core_count: u32, reader: anytype, stats: *std.ArrayList(CoreActivityRecord)) !void {
    for (0..core_count) |_| {
        const gas_used = try reader.readInt(u64, .little);
        const imports = try reader.readInt(u16, .little);
        const extrinsic_count = try reader.readInt(u16, .little);
        const extrinsic_size = try reader.readInt(u32, .little);
        const exports = try reader.readInt(u16, .little);
        const bundle_size = try reader.readInt(u32, .little);
        const da_load = try reader.readInt(u32, .little);
        const popularity = try reader.readInt(u16, .little);

        try stats.append(CoreActivityRecord{
            .gas_used = gas_used,
            .imports = imports,
            .extrinsic_count = extrinsic_count,
            .extrinsic_size = extrinsic_size,
            .exports = exports,
            .bundle_size = bundle_size,
            .da_load = da_load,
            .popularity = popularity,
        });
    }
}

fn decodeServiceStats(reader: anytype, stats: *std.AutoHashMap(ServiceId, ServiceActivityRecord)) !void {
    const service_count = try reader.readInt(u32, .little);

    for (0..service_count) |_| {
        const service_id = try reader.readInt(u32, .little);

        const provided_count = try reader.readInt(u16, .little);
        const provided_size = try reader.readInt(u32, .little);

        const refinement_count = try reader.readInt(u32, .little);
        const refinement_gas_used = try reader.readInt(u64, .little);

        const imports = try reader.readInt(u32, .little);
        const extrinsic_count = try reader.readInt(u32, .little);
        const extrinsic_size = try reader.readInt(u32, .little);
        const exports = try reader.readInt(u32, .little);

        const accumulate_count = try reader.readInt(u32, .little);
        const accumulate_gas_used = try reader.readInt(u64, .little);

        const on_transfers_count = try reader.readInt(u32, .little);
        const on_transfers_gas_used = try reader.readInt(u64, .little);

        const record = ServiceActivityRecord{
            .provided_count = provided_count,
            .provided_size = provided_size,
            .refinement_count = refinement_count,
            .refinement_gas_used = refinement_gas_used,
            .imports = imports,
            .extrinsic_count = extrinsic_count,
            .extrinsic_size = extrinsic_size,
            .exports = exports,
            .accumulate_count = accumulate_count,
            .accumulate_gas_used = accumulate_gas_used,
            .on_transfers_count = on_transfers_count,
            .on_transfers_gas_used = on_transfers_gas_used,
        };

        try stats.put(service_id, record);
    }
}
