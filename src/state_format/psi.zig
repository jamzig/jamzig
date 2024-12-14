const std = @import("std");
const tfmt = @import("../types/fmt.zig");

pub fn format(
    self: *const @import("../disputes.zig").Psi,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    var indented_writer = tfmt.IndentedWriter(@TypeOf(writer)).init(writer);
    var iw = indented_writer.writer();

    try iw.writeAll("Psi {\n");
    iw.context.indent();
    defer iw.context.outdent();

    // Format good_set
    try iw.writeAll("good_set: {\n");
    iw.context.indent();
    for (self.good_set.keys()) |key| {
        try tfmt.formatValue(key, iw);
        try iw.writeAll(",\n");
    }
    iw.context.outdent();
    try iw.writeAll("}\n");

    // Format bad_set
    try iw.writeAll("bad_set: {\n");
    iw.context.indent();
    for (self.bad_set.keys()) |key| {
        try tfmt.formatValue(key, iw);
        try iw.writeAll(",\n");
    }
    iw.context.outdent();
    try iw.writeAll("}\n");

    // Format wonky_set
    try iw.writeAll("wonky_set: {\n");
    iw.context.indent();
    for (self.wonky_set.keys()) |key| {
        try tfmt.formatValue(key, iw);
        try iw.writeAll(",\n");
    }
    iw.context.outdent();
    try iw.writeAll("}\n");

    // Format punish_set
    try iw.writeAll("punish_set: {\n");
    iw.context.indent();
    for (self.punish_set.keys()) |key| {
        try tfmt.formatValue(key, iw);
        try iw.writeAll(",\n");
    }
    iw.context.outdent();
    try iw.writeAll("}\n");
}
