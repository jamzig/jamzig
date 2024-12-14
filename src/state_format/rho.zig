const std = @import("std");
const Rho = @import("../pending_reports.zig").Rho;

const tfmt = @import("../types/fmt.zig");

pub fn format(
    comptime core_count: u32,
    self: *const Rho(core_count),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    var indented_writer = tfmt.IndentedWriter(@TypeOf(writer)).init(writer);
    var iw = indented_writer.writer();

    try iw.writeAll("Rho: (omitted cores are null)\n");
    iw.context.indent();
    defer iw.context.outdent();

    for (self.reports, 0..) |entry, i| {
        if (entry) |e| {
            const hash = e.cached_hash orelse try e.hash_uncached(self.allocator);
            try iw.print("Core {d}:\n", .{i});
            iw.context.indent();
            defer iw.context.outdent();

            try iw.print("work_package_hash: {s}\n", .{std.fmt.fmtSliceHexLower(&hash)});
            try iw.print("assignment: ", .{});

            // Format the assignment
            iw.context.indent();
            defer iw.context.outdent();

            try tfmt.formatValue(e.assignment, iw);
        } else {
            // try iw.print("Core {d}: no pending reports\n", .{i});
        }
    }
}
