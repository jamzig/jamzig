const std = @import("std");
const state = @import("../state.zig");
const types = @import("../types.zig");
const state_decoding = @import("../state_decoding.zig");
const state_dictionary = @import("../state_dictionary.zig");
const services = @import("../services.zig");

const Blake2b256 = std.crypto.hash.blake2.Blake2b(256);

const log = std.log.scoped(.state_dictionary_reconstruct);

/// Reconstructs base service account data from key type 255
pub fn reconstructServiceAccountBase(
    allocator: std.mem.Allocator,
    delta: *state.Delta,
    key: [32]u8,
    value: []const u8,
) !void {
    var stream = std.io.fixedBufferStream(value);
    const reader = stream.reader();

    const dkey = state_dictionary.deconstructByteServiceIndexKey(key);
    std.debug.assert(dkey.byte == 255);

    // Decode base account data using existing decoder
    try state_decoding.delta.decodeServiceAccountBase(allocator, delta, dkey.service_index, reader);
}

/// Reconstructs a storage entry for a service account by reconstructing the full hash
pub fn reconstructStorageEntry(
    allocator: std.mem.Allocator,
    delta: *state.Delta,
    key: [32]u8,
    value: []const u8,
) !void {
    const dkey = state_dictionary.deconstructServiceIndexHashKey(key);
    const dhash = state_dictionary.deconstructStorageKey(dkey.hash.hash) orelse return error.InvalidKey;

    // Get or create the account
    var account = try delta.getOrCreateAccount(dkey.service_index);

    // Create owned copy of value and store with full hash
    const owned_value = try allocator.dupe(u8, value);
    errdefer allocator.free(owned_value);

    // Calculate hash of the value
    var hash_of_value: [32]u8 = undefined;
    Blake2b256.hash(value, &hash_of_value, .{});

    if (!dhash.matches(&hash_of_value)) {
        return error.DeconstructedKeyHashMismatch;
    }

    try account.storage.put(hash_of_value, owned_value);
}

/// Reconstructs a preimage entry for a service account by reconstructing the full hash
pub fn reconstructPreimageEntry(
    allocator: std.mem.Allocator,
    delta: *state.Delta,
    tau: ?types.TimeSlot,
    key: [32]u8,
    value: []const u8,
) !void {
    // Calculate hash of the value

    const dkey = state_dictionary.deconstructServiceIndexHashKey(key);
    const dhash = state_dictionary.deconstructPreimageKey(dkey.hash.hash) orelse return error.InvalidKey;

    // NOTE: this dhash contains a lossy hash of the preimage hash which we could use
    // to rebuild the state. But it's messy.

    // Get or create the account
    var account: *services.ServiceAccount = //
        try delta.getOrCreateAccount(dkey.service_index);

    // Create owned copy of value and store with full hash
    const owned_value = try allocator.dupe(u8, value);
    errdefer allocator.free(owned_value);

    // Calculate hash of the value
    var hash_of_value: [32]u8 = undefined;
    Blake2b256.hash(value, &hash_of_value, .{});

    if (!dhash.matches(&hash_of_value)) {
        return error.DeconstructedKeyHashMismatch;
    }

    // we have to decode the value to add it the account preimages, but we also do
    // not have access to the hash
    try account.preimages.put(hash_of_value, owned_value);

    // GP0.5.0 @ 9.2.1 The state of the lookup system natu-
    // rally satisfies a number of invariants. Firstly, any preim-
    // age value must correspond to its hash.

    if (tau == null) {
        log.warn("tau not set yet", .{});
    }
    try account.integratePreimageLookup(
        hash_of_value,
        @intCast(value.len),
        tau,
    );
}

pub fn reconstructPreimageLookupEntry(
    allocator: std.mem.Allocator,
    delta: *state.Delta,
    key: [32]u8,
    value: []const u8,
) !void {
    _ = allocator;

    // Deconstruct the dkey and the preimageLookupEntry
    const dkey = state_dictionary.deconstructServiceIndexHashKey(key);
    const dhash = state_dictionary.deconstructPreimageLookupKey(dkey.hash.hash);

    // Now walk the delta to see if we have on the service a preimage which matches our hash
    var account = delta.getAccount(dkey.service_index) orelse return error.PreimageLookupEntryCannotBeReconstructedAccountMissing;
    var key_iter = account.preimages.keyIterator();

    var restored_hash: ?types.OpaqueHash = null;
    while (key_iter.next()) |pih| {
        // We need to compare against the hash of hash
        var hash_of_pih: types.OpaqueHash = undefined;
        Blake2b256.hash(pih, &hash_of_pih, .{});
        if (dhash.lossy_hash_of_hash.matches(&hash_of_pih)) {
            restored_hash = pih.*;
            break;
        }
    }

    // TODO: check if the length is correct against the preimage

    if (restored_hash == null) {
        return error.PreimageLookupEntryCannotBeReconstructedMissingHashInPreImages;
    }

    // decode the entry
    var stream = std.io.fixedBufferStream(value);
    const entry = try state_decoding.delta.decodePreimageLookup(
        stream.reader(),
    );

    // add it to the account
    try account.preimage_lookups.put(
        services.PreimageLookupKey{ .hash = restored_hash.?, .length = dhash.length },
        entry,
    );
}

test "reconstructStorageEntry with hash reconstruction" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var delta = state.Delta.init(allocator);
    defer delta.deinit();

    const service_id: u32 = 42;
    const value = "test value";

    // Calculate hash of value to get lossy hash
    var full_hash: [32]u8 = undefined;
    Blake2b256.hash(value, &full_hash, .{});

    // Build the key
    const key = state_dictionary.constructServiceIndexHashKey(
        service_id,
        state_dictionary.buildStorageKey(full_hash),
    );

    // Test reconstruction
    try reconstructStorageEntry(allocator, &delta, key, value);

    // Verify storage entry
    const account = delta.accounts.get(service_id) orelse return error.AccountNotFound;
    const stored_value = account.storage.get(full_hash) orelse return error.ValueNotFound;
    try testing.expectEqualStrings(value, stored_value);
}

test "reconstructPreimageEntry with hash reconstruction" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var delta = state.Delta.init(allocator);
    defer delta.deinit();

    const service_id: u32 = 42;
    const value = "test preimage value";

    // Calculate hash of value to get lossy hash
    var full_hash: [32]u8 = undefined;
    Blake2b256.hash(value, &full_hash, .{});

    const key = state_dictionary.constructServiceIndexHashKey(
        service_id,
        state_dictionary.buildPreimageKey(full_hash),
    );

    // Test reconstruction
    try reconstructPreimageEntry(allocator, &delta, null, key, value);

    // Verify preimage entry
    const account = delta.accounts.get(service_id) orelse return error.AccountNotFound;
    const stored_value = account.preimages.get(full_hash) orelse return error.ValueNotFound;
    try testing.expectEqualStrings(value, stored_value);
}
