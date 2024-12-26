const std = @import("std");
const blob_dict = @import("../../codec/blob_dict.zig");
const state_dictionary = @import("../../state_dictionary.zig");

const MerklizationDictionary = state_dictionary.MerklizationDictionary;

/// Loads a state dictionary from a binary file.
/// The binary file should contain serialized key-value pairs where keys are 32-byte arrays
/// and values are variable-length byte arrays.
pub fn blobDictToMerklizationDictionary(allocator: std.mem.Allocator, blob: blob_dict.BlobDict) !MerklizationDictionary {
    // Convert BlobDict to MerklizationDictionary
    var dict = MerklizationDictionary.init(allocator);
    errdefer dict.deinit();

    // Transfer ownership of entries from BlobDict to MerklizationDictionary
    var it = blob.map.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = try allocator.dupe(u8, entry.value_ptr.*);

        // Note: No need to copy key/value as we're transferring ownership
        try dict.entries.put(key, value);
    }

    return dict;
}
