const std = @import("std");
const state = @import("../state.zig");
const state_decoding = @import("../state_decoding.zig");
const types = @import("../types.zig");
const delta_reconstruction = @import("delta_reconstruction.zig");

const MerklizationDictionary = @import("../state_dictionary.zig").MerklizationDictionary;
const Params = @import("../jam_params.zig").Params;

const detectKeyType = @import("../state_dictionary/key_type_detection.zig").detectKeyType;

const trace = @import("../tracing.zig").scoped(.state_dictionary_reconstruct);

/// Reconstructs a JamState from a MerklizationDictionary by decoding its entries
pub fn reconstructState(
    comptime params: Params,
    allocator: std.mem.Allocator,
    dict: *const MerklizationDictionary,
) !state.JamState(params) {
    var span = trace.span(.reconstruct_state);
    defer span.deinit();

    span.debug("Starting state reconstruction with dictionary size: {d}", .{dict.entries.count()});

    var jam_state = try state.JamState(params).init(allocator);
    errdefer jam_state.deinit(allocator);
    span.debug("Initialized empty JamState", .{});

    // Helper function to get reader for value

    const getReader = struct {
        fn get(value: []const u8) std.io.FixedBufferStream([]const u8).Reader {
            var stream = std.io.fixedBufferStream(value);
            return stream.reader();
        }
    }.get;

    // Iterate through all entries
    var it = dict.entries.iterator();
    var entry_count: usize = 0;
    while (it.next()) |entry| {
        entry_count += 1;
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        var entry_span = span.child(.process_entry);
        defer entry_span.deinit();

        entry_span.debug("Processing entry {d}/{d}: key length={d}, value length={d}", .{ entry_count, dict.entries.count(), key.len, value.len });

        const key_type = detectKeyType(key);
        entry_span.trace("Key type: {s}, key: 0x{s}", .{ @tagName(key_type), std.fmt.fmtSliceHexLower(&key) });

        switch (key_type) {
            .state_component => switch (key[0]) {
                1 => {
                    var component_span = entry_span.child(.decode_alpha);
                    defer component_span.deinit();
                    component_span.debug("Decoding alpha component (id={d})", .{key[0]});
                    jam_state.alpha = try state_decoding.alpha.decode(params.core_count, getReader(value));
                },
                2 => {
                    var component_span = entry_span.child(.decode_phi);
                    defer component_span.deinit();
                    component_span.debug("Decoding phi component (id={d})", .{key[0]});
                    jam_state.phi = try state_decoding.phi.decode(params.core_count, params.max_authorizations_queue_items, allocator, getReader(value));
                },

                3 => {
                    entry_span.debug("Decoding beta component (id={d})", .{key[0]});
                    jam_state.beta = try state_decoding.beta.decode(allocator, getReader(value));
                },
                4 => {
                    entry_span.debug("Decoding gamma component (id={d})", .{key[0]});
                    jam_state.gamma = try state_decoding.gamma.decode(params, allocator, getReader(value));
                },
                5 => {
                    entry_span.debug("Decoding psi component (id={d})", .{key[0]});
                    jam_state.psi = try state_decoding.psi.decode(allocator, getReader(value));
                },
                6 => {
                    entry_span.debug("Decoding eta component (id={d})", .{key[0]});
                    jam_state.eta = try state_decoding.eta.decode(getReader(value));
                },
                7 => {
                    entry_span.debug("Decoding iota component (id={d})", .{key[0]});
                    jam_state.iota = try state_decoding.iota.decode(allocator, params.validators_count, getReader(value));
                },
                8 => {
                    entry_span.debug("Decoding kappa component (id={d})", .{key[0]});
                    jam_state.kappa = try state_decoding.kappa.decode(allocator, params.validators_count, getReader(value));
                },
                9 => {
                    entry_span.debug("Decoding lambda component (id={d})", .{key[0]});
                    jam_state.lambda = try state_decoding.lambda.decode(allocator, params.validators_count, getReader(value));
                },
                10 => {
                    entry_span.debug("Decoding rho component (id={d})", .{key[0]});
                    jam_state.rho = try state_decoding.rho.decode(params, allocator, getReader(value));
                },
                11 => {
                    entry_span.debug("Decoding tau component (id={d})", .{key[0]});
                    jam_state.tau = try state_decoding.tau.decode(getReader(value));
                },
                12 => {
                    entry_span.debug("Decoding chi component (id={d})", .{key[0]});
                    jam_state.chi = try state_decoding.chi.decode(allocator, getReader(value));
                },
                13 => {
                    entry_span.debug("Decoding pi component (id={d})", .{key[0]});
                    jam_state.pi = try state_decoding.pi.decode(params.validators_count, getReader(value), allocator);
                },
                14 => {
                    entry_span.debug("Decoding theta component (id={d})", .{key[0]});
                    jam_state.theta = try state_decoding.theta.decode(params.epoch_length, allocator, getReader(value));
                },
                15 => {
                    entry_span.debug("Decoding xi component (id={d})", .{key[0]});
                    jam_state.xi = try state_decoding.xi.decode(params.epoch_length, allocator, getReader(value));
                },
                else => {
                    entry_span.err("Unknown state component ID: {d}", .{key[0]});
                    return error.UnknownStateComponent;
                },
            },
            .delta_base => {
                var delta_span = entry_span.child(.process_delta_base);
                defer delta_span.deinit();
                delta_span.debug("Processing delta base entry", .{});
                if (jam_state.delta == null) {
                    delta_span.debug("Initializing delta state", .{});
                    jam_state.delta = state.Delta.init(allocator);
                }

                try delta_reconstruction.reconstructServiceAccountBase(allocator, &jam_state.delta.?, key, value);
            },
            .delta_storage => {
                var storage_span = entry_span.child(.process_delta_storage);
                defer storage_span.deinit();
                storage_span.debug("Processing delta storage entry", .{});
                if (jam_state.delta == null) {
                    storage_span.debug("Initializing delta state", .{});
                    jam_state.delta = state.Delta.init(allocator);
                }

                try delta_reconstruction.reconstructStorageEntry(allocator, &jam_state.delta.?, key, value);
            },
            .delta_preimage => {
                var preimage_span = entry_span.child(.process_delta_preimage);
                defer preimage_span.deinit();
                preimage_span.debug("Processing delta preimage entry", .{});
                if (jam_state.delta == null) {
                    preimage_span.debug("Initializing delta state", .{});
                    jam_state.delta = state.Delta.init(allocator);
                }

                try delta_reconstruction.reconstructPreimageEntry(allocator, &jam_state.delta.?, jam_state.tau, key, value);
            },
            .delta_lookup => {
                var lookup_span = entry_span.child(.process_delta_lookup);
                defer lookup_span.deinit();
                lookup_span.debug("Processing delta lookup entry", .{});
                if (jam_state.delta == null) {
                    lookup_span.debug("Initializing delta state", .{});
                    jam_state.delta = state.Delta.init(allocator);
                }

                try delta_reconstruction.reconstructPreimageLookupEntry(allocator, &jam_state.delta.?, key, value);
            },
            .unknown => {
                entry_span.err("Invalid key encountered: {any}", .{key});
                return error.InvalidKey;
            },
        }
    }

    span.debug("State reconstruction completed successfully. Processed {d} entries", .{entry_count});

    return jam_state;
}
