const std = @import("std");
const tfmt = @import("../types/fmt.zig");

const Delta = @import("../services.zig").Delta;

pub fn format(
    self: *const Delta,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    var indented_writer = tfmt.IndentedWriter(@TypeOf(writer)).init(writer);
    var iw = indented_writer.writer();

    try iw.writeAll("Delta\n");
    iw.context.indent();

    try tfmt.formatValue(self.*, iw, .{});
}
