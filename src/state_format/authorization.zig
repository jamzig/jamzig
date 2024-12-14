const std = @import("std");
const tfmt = @import("../types/fmt.zig");

const Alpha = @import("../authorization.zig").Alpha;

pub fn format(
    comptime core_count: u32,
    self: Alpha(core_count),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    var indented_writer = tfmt.IndentedWriter(@TypeOf(writer)).init(writer);
    var iw = indented_writer.writer();

    try iw.writeAll("Alpha\n");
    iw.context.indent();

    // Format pools
    try iw.writeAll("pools:\n");
    iw.context.indent();
    var has_pools = false;
    for (self.pools, 0..) |pool, i| {
        if (pool.len > 0) {
            has_pools = true;
            try iw.print("core {d}:\n", .{i});
            iw.context.indent();
            for (pool.constSlice()) |auth| {
                try iw.writeAll("authorizer: ");
                try tfmt.formatValue(auth, iw);
                try iw.writeAll("\n");
            }
            iw.context.outdent();
        }
    }
    if (!has_pools) {
        try iw.writeAll("<empty>\n");
    }
    iw.context.outdent();

    // Format queues
    try iw.writeAll("queues:\n");
    iw.context.indent();
    var has_queues = false;
    for (self.queues, 0..) |queue, i| {
        if (queue.len > 0) {
            has_queues = true;
            try iw.print("core {d}:\n", .{i});
            iw.context.indent();
            for (queue.constSlice()) |auth| {
                try iw.writeAll("authorizer: ");
                try tfmt.formatValue(auth, iw);
                try iw.writeAll("\n");
            }
            iw.context.outdent();
        }
    }
    if (!has_queues) {
        try iw.writeAll("<empty>\n");
    }
    iw.context.outdent();
}

// Test helper to demonstrate formatting
test "Alpha format demo" {
    const core_count = 4;
    var alpha = Alpha(core_count).init();

    // Add some test data
    const auth1 = [_]u8{0xA1} ++ [_]u8{0} ** 31;
    const auth2 = [_]u8{0xA2} ++ [_]u8{0} ** 31;
    const auth3 = [_]u8{0xA3} ++ [_]u8{0} ** 31;

    // Add to pools
    try alpha.pools[1].append(auth1);
    try alpha.pools[1].append(auth2);
    try alpha.pools[3].append(auth3);

    // Add to queues
    try alpha.queues[0].append(auth1);
    try alpha.queues[2].append(auth2);
    try alpha.queues[2].append(auth3);

    // Print formatted output
    std.debug.print("\n=== Alpha Format Demo ===\n", .{});
    std.debug.print("{}\n", .{alpha});
}
