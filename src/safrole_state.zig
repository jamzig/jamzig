const std = @import("std");
const types = @import("types.zig");

// TODO: move this to a seperate file
pub const Gamma = struct {
    k: types.GammaK,
    z: types.GammaZ,
    s: types.GammaS,
    a: types.GammaA,

    pub fn init(allocator: std.mem.Allocator, validators_count: u32) !Gamma {
        return Gamma{
            .k = try types.GammaK.init(allocator, validators_count),
            .z = std.mem.zeroes(types.BandersnatchVrfRoot),
            .s = .{ .tickets = try allocator.alloc(types.TicketBody, validators_count) },
            .a = try allocator.alloc(types.TicketBody, validators_count),
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
        self.k.deinit(allocator);
        self.s.deinit(allocator);
        allocator.free(self.a);
    }
};
