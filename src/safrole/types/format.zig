const std = @import("std");
const types = @import("../types.zig");

pub fn formatState(state: types.State, writer: anytype) !void {
    try writer.writeAll("State {\n");
    try writer.print("  tau: {}\n", .{state.tau});
    try writer.writeAll("  eta: [\n");
    for (state.eta) |hash| {
        try writer.print("    0x{x}\n", .{std.fmt.fmtSliceHexLower(&hash)});
    }
    try writer.writeAll("  ]\n");
    try writer.print("  lambda: {} validators\n", .{state.lambda.len});
    try writer.print("  kappa: {} validators\n", .{state.kappa.len});
    try writer.print("  gamma_k: {} validators\n", .{state.gamma_k.len});
    try writer.print("  iota: {} validators\n", .{state.iota.len});
    try writer.print("  gamma_a: {} tickets\n", .{state.gamma_a.len});
    try writer.writeAll("  gamma_s: ");
    switch (state.gamma_s) {
        .tickets => |tickets| try writer.print("{} tickets\n", .{tickets.len}),
        .keys => |keys| try writer.print("{} keys\n", .{keys.len}),
    }
    try writer.print("  gamma_z: 0x{x}\n", .{std.fmt.fmtSliceHexLower(&state.gamma_z)});
    try writer.writeAll("}");
}
