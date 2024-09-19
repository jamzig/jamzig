const std = @import("std");
const types = @import("../types.zig");

pub fn formatHeader(header: types.Header, writer: anytype) !void {
    try writer.print("Header {{\n", .{});
    try writer.print("  parent: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&header.parent)});
    try writer.print("  parent_state_root: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&header.parent_state_root)});
    try writer.print("  extrinsic_hash: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&header.extrinsic_hash)});
    try writer.print("  slot: {d}\n", .{header.slot});

    if (header.epoch_mark) |epoch_mark| {
        try writer.print("  epoch_mark: {{\n", .{});
        try writer.print("    entropy: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&epoch_mark.entropy)});
        try writer.print("    validators: [\n", .{});
        for (epoch_mark.validators) |validator| {
            try writer.print("      0x{s}\n", .{std.fmt.fmtSliceHexLower(&validator)});
        }
        try writer.print("    ]\n", .{});
        try writer.print("  }}\n", .{});
    } else {
        try writer.print("  epoch_mark: null\n", .{});
    }

    if (header.tickets_mark) |tickets_mark| {
        try writer.print("  tickets_mark: [\n", .{});
        for (tickets_mark.tickets) |ticket| {
            try writer.print("    {{ id: 0x{s}, attempt: {d} }}\n", .{ std.fmt.fmtSliceHexLower(&ticket.id), ticket.attempt });
        }
        try writer.print("  ]\n", .{});
    } else {
        try writer.print("  tickets_mark: null\n", .{});
    }

    try writer.print("  offenders_mark: [\n", .{});
    for (header.offenders_mark) |offender| {
        try writer.print("    0x{s}\n", .{std.fmt.fmtSliceHexLower(&offender)});
    }
    try writer.print("  ]\n", .{});

    try writer.print("  author_index: {d}\n", .{header.author_index});
    try writer.print("  entropy_source: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&header.entropy_source)});
    try writer.print("  seal: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&header.seal)});
    try writer.print("}}\n", .{});
}
