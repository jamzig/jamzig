const std = @import("std");
const testing = std.testing;
const state = @import("../state.zig");
const types = @import("../types.zig");
const state_dictionary = @import("../state_dictionary.zig");
const MerklizationDictionary = @import("../state_dictionary.zig").MerklizationDictionary;
const delta_reconstruction = @import("delta_reconstruction.zig");
const Params = @import("../jam_params.zig").Params;
const reconstruct = @import("reconstruct.zig");

const Blake2b256 = std.crypto.hash.blake2.Blake2b(256);

const TINY = @import("../jam_params.zig").TINY_PARAMS;

test "reconstruct delta base account" {
    // Setup
    const allocator = testing.allocator;

    var delta = state.Delta.init(allocator);
    defer delta.deinit();

    const service_id: u32 = 42;

    // Create a base account key (type 255)
    const base_key = state_dictionary.constructByteServiceIndexKey(255, service_id);

    // Create sample account data
    const base_value = [_]u8{1} ** 68; // Sample account data

    // Test reconstruction
    try delta_reconstruction.reconstructServiceAccountBase(allocator, &delta, base_key, &base_value);

    // Verify
    try testing.expect(delta.accounts.contains(service_id));
}

test "reconstruct delta storage entry" {
    const allocator = testing.allocator;
    var delta = state.Delta.init(allocator);
    defer delta.deinit();

    const service_id: u32 = 42;
    const value = [_]u8{ 5, 6, 7, 8 };

    // Calculate actual hash of the value
    var hash: [32]u8 = undefined;
    Blake2b256.hash(&value, &hash, .{});

    // Create storage key (MSB set)
    const key: [32]u8 = state_dictionary.constructServiceIndexHashKey(
        service_id,
        state_dictionary.buildStorageKey(hash),
    );

    // Test reconstruction
    try delta_reconstruction.reconstructStorageEntry(allocator, &delta, key, &value);

    // Verify
    const account = delta.accounts.get(service_id) orelse return error.AccountNotFound;
    try testing.expect(account.storage.contains(hash));
    try testing.expectEqualSlices(u8, &value, account.storage.get(hash).?);
}

test "reconstruct delta preimage entry" {
    const allocator = testing.allocator;
    var delta = state.Delta.init(allocator);
    defer delta.deinit();

    const service_id: u32 = 42;
    const value = [_]u8{ 5, 6, 7, 8 };

    // Calculate actual hash of the value
    var hash: [32]u8 = undefined;
    Blake2b256.hash(&value, &hash, .{});

    // Create storage key (MSB set)
    const key: [32]u8 = state_dictionary.constructServiceIndexHashKey(
        service_id,
        state_dictionary.buildPreimageKey(hash),
    );

    // Test reconstruction
    try delta_reconstruction.reconstructPreimageEntry(allocator, &delta, null, key, &value);

    // Verify
    const account = delta.accounts.get(service_id) orelse return error.AccountNotFound;
    try testing.expect(account.preimages.contains(hash));
    try testing.expectEqualSlices(u8, &value, account.preimages.get(hash).?);
}
