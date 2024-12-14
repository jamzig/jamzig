const std = @import("std");
const Rho = @import("../pending_reports.zig").Rho;

pub fn format(
    comptime core_count: u32,
    self: *const Rho(core_count),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    try writer.writeAll("Rho{\n");
    try writer.writeAll("  Reports:\n");

    for (self.reports, 0..) |entry, i| {
        if (entry) |e| {
            const hash = e.cached_hash orelse try e.hash_uncached(self.allocator);
            try writer.print("    Core {d}: {{\n", .{i});
            try writer.print("      hash: {s}\n", .{std.fmt.fmtSliceHexLower(&hash)});
            try writer.print("      timeout: {d}\n", .{e.assignment.timeout});
            // try writer.print("      report: {s}\n", .{e.assignment.report});
            try writer.writeAll("    }\n");
        } else {
            try writer.print("    Core {d}: no pending reports\n", .{i});
        }
    }

    try writer.writeAll("}");
}
