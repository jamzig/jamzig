const std = @import("std");
const state = @import("../state.zig");
const types = @import("../types.zig");
const services = @import("../services.zig");
const DecodingError = @import("../state_decoding.zig").DecodingError;

/// Decodes base service account data and adds/updates the account in delta
/// Base account data includes service info like code hash, balance, gas limits etc
pub fn decodeServiceAccountBase(
    _: std.mem.Allocator,
    delta: *state.Delta,
    service_id: types.ServiceId,
    reader: anytype,
) !void {
    // Read basic service info fields from the encoded data
    const code_hash = try readHash(reader);

    // se_8 encoded fields (8 bytes each)
    const balance = try reader.readInt(types.U64, .little);
    const min_item_gas = try reader.readInt(types.Gas, .little);
    const min_memo_gas = try reader.readInt(types.Gas, .little);
    const bytes = try reader.readInt(types.U64, .little);

    const storage_offset = try reader.readInt(types.U64, .little); // NEW: a_f

    // se_4 encoded fields (4 bytes each)
    const items = try reader.readInt(types.U32, .little);
    const creation_slot = try reader.readInt(types.U32, .little); // NEW: a_r
    const last_accumulation_slot = try reader.readInt(types.U32, .little); // NEW: a_a
    const parent_service = try reader.readInt(types.U32, .little); // NEW: a_p

    // Construct account
    var account = try delta.getOrCreateAccount(service_id);
    account.code_hash = code_hash;
    account.balance = balance;
    account.min_gas_accumulate = min_item_gas;
    account.min_gas_on_transfer = min_memo_gas;
    account.storage_offset = storage_offset; // gratis storage offset
    account.creation_slot = creation_slot;
    account.last_accumulation_slot = last_accumulation_slot;
    account.parent_service = parent_service;

    // Initialize tracking fields based on deserialized footprint values
    // These will be properly recalculated as data is loaded, but we set initial
    // estimates based on the serialized footprint
    // Note: a_i includes both storage items and 2*preimage_lookups
    // We can't distinguish exactly, but will be corrected as data loads
    account.storage_items = items; // This is the total a_i, will be refined
    account.storage_bytes = bytes; // This is the total a_o
    account.preimage_count = 0; // Will be updated as preimages are loaded
    account.preimage_bytes = 0; // Will be updated as preimages are loaded
    account.preimage_lookup_count = 0; // Will be updated as lookups are loaded
}

/// Decodes a preimage lookup from the encoded format: E(↕[E_4(x) | x <− t])
/// The encoding consists of a length prefix followed by timestamps
pub fn decodePreimageLookup(reader: anytype) !services.PreimageLookup {

    // Read timestamp count
    const codec = @import("../codec.zig");
    const timestamp_count = try codec.readInteger(reader);
    if (timestamp_count > 3) return error.InvalidData;

    // Initialize lookup with null status
    var lookup = services.PreimageLookup{
        .status = .{ null, null, null },
    };

    // Read timestamps
    for (0..timestamp_count) |i| {
        const timestamp = try reader.readInt(u32, .little);
        lookup.status[i] = timestamp;
    }

    return lookup;
}

/// Helper function to read a 32-byte hash
fn readHash(reader: anytype) !types.OpaqueHash {
    var hash: types.OpaqueHash = undefined;
    const bytes_read = try reader.readAll(&hash);
    if (bytes_read != hash.len) {
        return DecodingError.EndOfStream;
    }
    return hash;
}
