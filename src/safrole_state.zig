const std = @import("std");
const types = @import("types.zig");

// TODO: move this to a seperate file
pub const Gamma = struct {
    k: types.GammaK,
    z: types.GammaZ,
    s: types.GammaS,
    a: types.GammaA,

    pub fn init(allocator: std.mem.Allocator) !Gamma {
        return Gamma{
            .k = try allocator.alloc(types.ValidatorData, 0),
            .z = std.mem.zeroes(types.BandersnatchVrfRoot),
            .s = .{ .tickets = try allocator.alloc(types.TicketBody, 0) },
            .a = try allocator.alloc(types.TicketBody, 0),
        };
    }

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try @import("state_json/safrole_state.zig").jsonStringify(self, jw);
    }

    pub fn format(
        self: *const @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try @import("state_format/safrole_state.zig").format(self, fmt, options, writer);
    }

    pub fn deinit(self: *Gamma, allocator: std.mem.Allocator) void {
        allocator.free(self.k);
        allocator.free(self.s.tickets);
        allocator.free(self.a);
    }
};
