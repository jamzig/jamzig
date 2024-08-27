const std = @import("std");
const safrole = @import("./libs/safrole.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_vector = try safrole.TestVector.init(allocator, "tests/vectors/jam/safrole/tiny/enact-epoch-change-with-no-tickets-1.json");
    std.debug.print("Test vector: {}\n", .{test_vector});
}
