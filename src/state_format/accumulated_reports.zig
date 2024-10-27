const std = @import("std");
const Xi = @import("../accumulated_reports.zig").Xi;

pub fn format(
    comptime epoch_size: usize,
    self: *const Xi(epoch_size),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    try writer.writeAll("Xi{\n");
    for (self.entries, 0..) |slot_entries, i| {
        if (slot_entries.count() > 0) {
            try writer.print("  slot {d}: {d} reports\n", .{ i, slot_entries.count() });
            var it = slot_entries.iterator();
            while (it.next()) |entry| {
                try writer.print("    {s} -> {s}\n", .{
                    std.fmt.fmtSliceHexLower(&entry.key_ptr.*),
                    std.fmt.fmtSliceHexLower(&entry.value_ptr.*),
                });
            }
        }
    }
    try writer.writeAll("}");
}
