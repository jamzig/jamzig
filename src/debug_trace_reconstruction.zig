const std = @import("std");
const testing = std.testing;
const state_dictionary = @import("state_dictionary.zig");
const state = @import("state.zig");
const jam_params = @import("jam_params.zig");

test "debug fallback trace keyval reconstruction" {
    const allocator = testing.allocator;

    // Load trace JSON to get keyvals
    const trace_file = try std.fs.cwd().openFile(
        "src/jamtestvectors/data/traces/fallback/00000001.json",
        .{},
    );
    defer trace_file.close();

    const trace_json = try trace_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(trace_json);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        trace_json,
        .{},
    );
    defer parsed.deinit();

    const pre_state = parsed.value.object.get("pre_state").?;
    const expected_root_hex = pre_state.object.get("state_root").?.string;
    const keyvals = pre_state.object.get("keyvals").?.array;

    std.debug.print("\n=== Trace Pre-State Debug ===\n", .{});
    std.debug.print("Expected root: {s}\n", .{expected_root_hex});
    std.debug.print("Keyval count: {d}\n\n", .{keyvals.items.len});

    // Build merklization dictionary from keyvals
    var dict = state_dictionary.MerklizationDictionary.init(allocator);
    defer dict.deinit();

    for (keyvals.items, 0..) |kv_json, i| {
        const key_hex = kv_json.object.get("key").?.string;
        const value_hex = kv_json.object.get("value").?.string;

        // Decode hex strings (remove 0x prefix) - allocate buffers
        var key_bytes = try allocator.alloc(u8, (key_hex.len - 2) / 2);
        defer allocator.free(key_bytes);
        _ = try std.fmt.hexToBytes(key_bytes, key_hex[2..]);

        var value_bytes_temp = try allocator.alloc(u8, (value_hex.len - 2) / 2);
        _ = try std.fmt.hexToBytes(value_bytes_temp, value_hex[2..]);
        const value_bytes = value_bytes_temp; // Transfer ownership to dict
        
        if (i < 3) {
            std.debug.print("Keyval {d}:\n", .{i});
            std.debug.print("  Key: {s}\n", .{std.fmt.fmtSliceHexLower(key_bytes)});
            std.debug.print("  Value len: {d}, first bytes: {s}\n", .{
                value_bytes.len,
                std.fmt.fmtSliceHexLower(value_bytes[0..@min(20, value_bytes.len)]),
            });
        }
        
        // Add to dictionary
        var key: [31]u8 = undefined;
        @memcpy(&key, key_bytes);
        try dict.entries.put(key, .{
            .key = key,
            .value = value_bytes,
        });
    }
    
    // Build state root from dictionary
    const actual_root = try dict.buildStateRoot(allocator);
    
    std.debug.print("\n=== Reconstruction Result ===\n", .{});
    std.debug.print("Actual root:   {s}\n", .{std.fmt.fmtSliceHexLower(&actual_root)});
    std.debug.print("Expected root: {s}\n", .{expected_root_hex[2..]});
    
    if (!std.mem.eql(u8, &actual_root, &std.fmt.hexToBytes(&[_]u8{0} ** 32, expected_root_hex[2..]) catch unreachable)) {
        std.debug.print("\n❌ MISMATCH!\n", .{});
    } else {
        std.debug.print("\n✅ MATCH!\n", .{});
    }
}
