const std = @import("std");
const types = @import("types.zig");
const jamstate = @import("state.zig");
const state_encoder = @import("state_encoding.zig");

/// Constructs a 32-byte key with the input byte as the first element and zeros for the rest.
///
/// @param input - The byte to use as the first element of the key
/// @return A 32-byte array representing the key
fn constructSimpleByteKey(input: u8) [32]u8 {
    var result: [32]u8 = [_]u8{0} ** 32;
    result[0] = input;
    return result;
}

/// Constructs a 32-byte key using a byte and a service index.
/// The first byte is set to the input byte, followed by the 4-byte service index in little-endian format.
///
/// @param i - The byte to use as the first element of the key
/// @param s - The service index to encode in the key
/// @return A 32-byte array representing the key
fn constructByteServiceIndexKey(i: u8, s: u32) [32]u8 {
    var result: [32]u8 = [_]u8{0} ** 32;

    result[0] = i;
    std.mem.writeInt(u32, result[1..5], s, .little);
    return result;
}

/// Constructs a 32-byte key by interleaving a service index with a hash.
/// The service index bytes are interleaved with the first 4 bytes of the hash,
/// followed by the remaining 24 bytes of the hash.
///
/// @param s - The service index to encode in the key
/// @param h - A 32-byte hash to incorporate into the key
/// @return A 32-byte array representing the key
fn constructServiceIndexHashKey(s: u32, h: [32]u8) [32]u8 {
    var result: [32]u8 = [_]u8{0} ** 32;

    // Write service index in pieces
    var service_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &service_bytes, s, .little);

    // Interleave service bytes with hash
    result[0] = service_bytes[0];
    result[1] = h[0];
    result[2] = service_bytes[1];
    result[3] = h[1];
    result[4] = service_bytes[2];
    result[5] = h[2];
    result[6] = service_bytes[3];
    result[7] = h[3];

    // Copy remaining hash bytes
    std.mem.copyForwards(u8, result[8..], h[4..28]);
    return result;
}

/// Maps a state component to its encoding using the appropriate state key
pub fn buildStateMerklizationDictionary(
    allocator: std.mem.Allocator,
    state: *const jamstate.JamState,
) !std.AutoHashMap([32]u8, []const u8) {
    var map = std.AutoHashMap([32]u8, []const u8).init(allocator);
    errdefer map.deinit();

    // Encode the simple state components using specific encoders
    {
        // Alpha (1)
        const alpha_key = constructSimpleByteKey(1);
        var alpha_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeAlpha(&state.alpha, alpha_value.writer());
        try map.put(alpha_key, try alpha_value.toOwnedSlice());

        // Phi (2)
        const phi_key = constructSimpleByteKey(2);
        var phi_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodePhi(&state.phi, phi_value.writer());
        try map.put(phi_key, try phi_value.toOwnedSlice());

        // Beta (3)
        const beta_key = constructSimpleByteKey(3);
        var beta_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeBeta(&state.beta, beta_value.writer());
        try map.put(beta_key, try beta_value.toOwnedSlice());

        // Gamma (4)
        const gamma_key = constructSimpleByteKey(4);
        var gamma_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeGamma(&state.gamma, gamma_value.writer());
        try map.put(gamma_key, try gamma_value.toOwnedSlice());

        // Psi (5)
        const psi_key = constructSimpleByteKey(5);
        var psi_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodePsi(&state.psi, psi_value.writer());
        try map.put(psi_key, try psi_value.toOwnedSlice());

        // Eta (6)
        const eta_key = constructSimpleByteKey(6);
        var eta_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeEta(&state.eta, eta_value.writer());
        try map.put(eta_key, try eta_value.toOwnedSlice());

        // Iota (7)
        const iota_key = constructSimpleByteKey(7);
        var iota_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeIota(state.iota, iota_value.writer());
        try map.put(iota_key, try iota_value.toOwnedSlice());

        // Kappa (8)
        const kappa_key = constructSimpleByteKey(8);
        var kappa_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeKappa(state.kappa, kappa_value.writer());
        try map.put(kappa_key, try kappa_value.toOwnedSlice());

        // Lambda (9)
        const lambda_key = constructSimpleByteKey(9);
        var lambda_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeLambda(state.lambda, lambda_value.writer());
        try map.put(lambda_key, try lambda_value.toOwnedSlice());

        // Rho (10)
        const rho_key = constructSimpleByteKey(10);
        var rho_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeRho(&state.rho, rho_value.writer());
        try map.put(rho_key, try rho_value.toOwnedSlice());

        // Tau (11)
        const tau_key = constructSimpleByteKey(11);
        var tau_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeTau(state.tau, tau_value.writer());
        try map.put(tau_key, try tau_value.toOwnedSlice());

        // Chi (12)
        const chi_key = constructSimpleByteKey(12);
        var chi_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeChi(&state.chi, chi_value.writer());
        try map.put(chi_key, try chi_value.toOwnedSlice());

        // Pi (13)
        const pi_key = constructSimpleByteKey(13);
        var pi_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodePi(&state.pi, pi_value.writer());
        try map.put(pi_key, try pi_value.toOwnedSlice());

        // Theta (14)
        const theta_key = constructSimpleByteKey(14);
        var theta_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeTheta(&state.theta, theta_value.writer());
        try map.put(theta_key, try theta_value.toOwnedSlice());

        // Xi (15)
        const xi_key = constructSimpleByteKey(15);
        var xi_value = std.ArrayList(u8).init(allocator);
        try state_encoder.encodeXi(&state.xi.entries, xi_value.writer());
        try map.put(xi_key, try xi_value.toOwnedSlice());
    }

    // Handle delta component (service accounts) specially
    if (state.delta.accounts.count() > 0) {
        var service_iter = state.delta.accounts.iterator();
        while (service_iter.next()) |service_entry| {
            const service_idx = service_entry.key_ptr.*;
            const account = service_entry.value_ptr;

            // Base account data
            const base_key = constructByteServiceIndexKey(255, service_idx);
            var base_value = std.ArrayList(u8).init(allocator);
            try state_encoder.encodeServiceAccountBase(account, base_value.writer());
            try map.put(base_key, try base_value.toOwnedSlice());

            // Storage entries
            var storage_iter = account.storage.iterator();
            while (storage_iter.next()) |storage_entry| {
                const storage_key = constructServiceIndexHashKey(service_idx, storage_entry.key_ptr.*);
                try map.put(storage_key, storage_entry.value_ptr.*);
            }

            // Preimage lookups
            var preimage_iter = account.preimages.iterator();
            while (preimage_iter.next()) |preimage_entry| {
                const preimage_key = constructServiceIndexHashKey(service_idx, preimage_entry.key_ptr.*);
                try map.put(preimage_key, preimage_entry.value_ptr.*);
            }

            // Preimage timestamps
            var lookup_iter = account.preimage_lookups.iterator();
            while (lookup_iter.next()) |lookup_entry| {
                const delta_encoder = state_encoder.delta;

                var modified_hash = std.ArrayList(u8).init(allocator);
                delta_encoder.encodePreimageKey(lookup_entry.key_ptr.*, modified_hash.writer());

                var timestamp_value = std.ArrayList(u8).init(allocator);
                try delta_encoder.encodePreimageLookup(lookup_entry.value_ptr.*, timestamp_value.writer());

                const lookup_key = constructServiceIndexHashKey(service_idx, modified_hash.toOwnedSlice());
                try map.put(lookup_key, try timestamp_value.toOwnedSlice());
            }
        }
    }

    return map;
}

//  _   _       _ _  _____         _
// | | | |_ __ (_) ||_   _|__  ___| |_
// | | | | '_ \| | __|| |/ _ \/ __| __|
// | |_| | | | | | |_ | |  __/\__ \ |_
//  \___/|_| |_|_|\__||_|\___||___/\__|

const testing = std.testing;

test "buildStateMerklizationDictionary" {
    const allocator = std.testing.allocator;
    const state = try jamstate.JamState.init(allocator);

    const map = try buildStateMerklizationDictionary(allocator, &state);

    _ = map;
}

test "constructSimpleByteKey" {
    const key = constructSimpleByteKey(42);
    try testing.expectEqual(@as(u8, 42), key[0]);
    for (key[1..]) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}

test "constructByteServiceIndexKey" {
    const key = constructByteServiceIndexKey(0xFF, 0x12345678);
    try testing.expectEqual(@as(u8, 0xFF), key[0]);
    try testing.expectEqual(@as(u32, 0x12345678), std.mem.readInt(u32, key[1..5], .little));
    for (key[5..]) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}

test "constructServiceIndexHashKey" {
    const service_index: u32 = 0x12345678;
    var hash: [32]u8 = [_]u8{0} ** 32;
    for (&hash, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    const key = constructServiceIndexHashKey(service_index, hash);

    try testing.expectEqual(@as(u8, 0x78), key[0]);
    try testing.expectEqual(@as(u8, 0x00), key[1]);
    try testing.expectEqual(@as(u8, 0x56), key[2]);
    try testing.expectEqual(@as(u8, 0x01), key[3]);
    try testing.expectEqual(@as(u8, 0x34), key[4]);
    try testing.expectEqual(@as(u8, 0x02), key[5]);
    try testing.expectEqual(@as(u8, 0x12), key[6]);
    try testing.expectEqual(@as(u8, 0x03), key[7]);

    try testing.expectEqualSlices(u8, hash[4..28], key[8..]);
}
