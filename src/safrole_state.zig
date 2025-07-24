const std = @import("std");
const types = @import("types.zig");

// TODO: move this to a seperate file
pub fn Gamma(comptime validators_count: u32, comptime epoch_length: u32) type {
    return struct {
        k: types.GammaK,
        z: types.GammaZ,
        s: types.GammaS,
        a: types.GammaA,

        pub fn init(allocator: std.mem.Allocator) !Gamma(validators_count, epoch_length) {
            return Gamma(validators_count, epoch_length){
                .k = try types.GammaK.init(allocator, validators_count),
                .z = std.mem.zeroes(types.BandersnatchVrfRoot),
                .s = .{ .tickets = try allocator.alloc(types.TicketBody, epoch_length) },
                .a = &[_]types.TicketBody{},
            };
        }


        pub fn format(
            self: *const @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            const tfmt = @import("types/fmt.zig");
            const formatter = tfmt.Format(@TypeOf(self.*)){
                .value = self.*,
                .options = .{},
            };
            try formatter.format(fmt, options, writer);
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.k.deinit(allocator);
            self.s.deinit(allocator);
            allocator.free(self.a);
            self.* = undefined;
        }

        pub fn deepClone(self: *const @This(), allocator: std.mem.Allocator) !Gamma(validators_count, epoch_length) {
            return .{
                .k = try self.k.deepClone(allocator),
                .z = self.z,
                .s = try self.s.deepClone(allocator),
                .a = try allocator.dupe(types.TicketBody, self.a),
            };
        }
    };
}
