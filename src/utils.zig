const std = @import("std");

/// Generic map function that allocates memory and applies a transformation function
pub fn mapAlloc(
    comptime T: type,
    comptime U: type,
    allocator: std.mem.Allocator,
    items: []const T,
    transform: fn (T) U,
) ![]U {
    const result = try allocator.alloc(U, items.len);
    errdefer allocator.free(result);

    for (items, result) |item, *target| {
        target.* = transform(item);
    }

    return result;
}

fn square(x: i32) i32 {
    return x * x;
}

const testing = std.testing;
const expectEqual = testing.expectEqual;

test mapAlloc {

    // Setup
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const numbers = [_]i32{ 1, 2, 3, 4, 5 };

    // Use the map function
    const squared_numbers = try mapAlloc(i32, i32, allocator, &numbers, square);
    defer allocator.free(squared_numbers);

    // Check results
    try expectEqual(@as(usize, 5), squared_numbers.len);
    try expectEqual(@as(i32, 1), squared_numbers[0]);
    try expectEqual(@as(i32, 4), squared_numbers[1]);
    try expectEqual(@as(i32, 9), squared_numbers[2]);
    try expectEqual(@as(i32, 16), squared_numbers[3]);
    try expectEqual(@as(i32, 25), squared_numbers[4]);
}
