const std = @import("std");
const types = @import("../../../types.zig");
const codec = @import("../../../codec.zig");
const state_dictionary = @import("../../../state_dictionary.zig");

pub const KeyVal = struct {
    key: []const u8,
    val: []const u8,

    pub fn decode(_: anytype, reader: anytype, allocator: std.mem.Allocator) !@This() {
        // Read key length and data
        const key_len = try codec.readInteger(reader);
        const key = try allocator.alloc(u8, @intCast(key_len));
        try reader.readNoEof(key);

        // Read value length and data
        const val_len = try codec.readInteger(reader);
        const val = try allocator.alloc(u8, @intCast(val_len));
        try reader.readNoEof(val);

        return KeyVal{
            .key = key,
            .val = val,
        };
    }

    pub fn deinit(self: *const KeyVal, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.val);
    }
};

pub const StateSnapshotRaw = struct {
    state_root: types.StateRoot,
    keyvals: []KeyVal,

    pub fn deinit(self: *StateSnapshotRaw, allocator: std.mem.Allocator) void {
        for (self.keyvals) |*keyval| {
            keyval.deinit(allocator);
        }
        allocator.free(self.keyvals);
    }
};

pub const TestStateTransition = struct {
    pre_state: StateSnapshotRaw,
    block: types.Block,
    post_state: StateSnapshotRaw,

    pub fn deinit(self: *TestStateTransition, allocator: std.mem.Allocator) void {
        self.pre_state.deinit(allocator);
        self.block.deinit(allocator);
        self.post_state.deinit(allocator);
    }

    pub fn pre_state_as_merklization_dict(self: *const TestStateTransition, allocator: std.mem.Allocator) !state_dictionary.MerklizationDictionary {
        return keyValArrayToMerklizationDict(allocator, self.pre_state.keyvals, "pre_state");
    }

    pub fn post_state_as_merklization_dict(self: *const TestStateTransition, allocator: std.mem.Allocator) !state_dictionary.MerklizationDictionary {
        return keyValArrayToMerklizationDict(allocator, self.post_state.keyvals, "post_state");
    }

    fn keyValArrayToMerklizationDict(allocator: std.mem.Allocator, keyvals: []const KeyVal, context: []const u8) !state_dictionary.MerklizationDictionary {
        var dict = state_dictionary.MerklizationDictionary.init(allocator);
        errdefer dict.deinit();

        for (keyvals) |keyval| {
            const key = keyValToKey(keyval.key) catch |err| {
                std.log.err("Invalid key length in {s} keyval: expected 32 bytes, got {d} bytes", .{ context, keyval.key.len });
                return err;
            };
            try dict.entries.put(key, try allocator.dupe(u8, keyval.val));
        }

        return dict;
    }

    fn keyValToKey(key_bytes: []const u8) !types.StateRoot {
        if (key_bytes.len != 32) {
            return error.InvalidKeyLength;
        }
        var key: types.StateRoot = undefined;
        @memcpy(&key, key_bytes);
        return key;
    }
};

pub fn loadTestVector(
    comptime params: @import("../../../jam_params.zig").Params,
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !TestStateTransition {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const reader = file.reader();
    return try codec.deserializeAlloc(TestStateTransition, params, allocator, reader);
}
