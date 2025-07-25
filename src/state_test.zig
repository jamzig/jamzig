const std = @import("std");
const testing = std.testing;

const JamState = @import("state.zig").JamState;

test "JamStateFormat" {
    const allocator = testing.allocator;
    const TINY = @import("jam_params.zig").TINY_PARAMS;

    var state = try JamState(TINY).init(allocator);
    defer state.deinit(allocator);

    std.debug.print("FORMAT: \n\n{any}\n", .{state});
}
