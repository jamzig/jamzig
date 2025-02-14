const std = @import("std");

/// Collects iterator values into an appendable container (e.g. ArrayList)
pub fn collectIntoAppendable(
    iterator: anytype,
    container: anytype,
) !void {
    while (try iterator.next()) |item| {
        try container.append(item);
    }
}

/// Collects iterator values into a HashSet
pub fn collectIntoSet(
    iterator: anytype,
    set: anytype,
) !void {
    while (try iterator.next()) |item| {
        try set.put(item, {});
    }
}

test "collectIntoAppendable - basic usage" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a simple number iterator
    const NumberIterator = struct {
        current: u32 = 0,
        max: u32,

        pub fn init(max: u32) @This() {
            return .{ .max = max };
        }

        pub fn next(self: *@This()) !?u32 {
            if (self.current >= self.max) return null;
            const value = self.current;
            self.current += 1;
            return value;
        }
    };

    // Test collecting numbers 0 through 4
    var iter = NumberIterator.init(5);
    var list = std.ArrayList(u32).init(allocator);
    defer list.deinit();

    try collectIntoAppendable(u32, &iter, &list);
    const numbers = list.items;

    try testing.expectEqual(@as(usize, 5), numbers.len);
    for (numbers, 0..) |num, i| {
        try testing.expectEqual(@as(u32, @intCast(i)), num);
    }
}

test "collectIntoSet - basic usage" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a simple number iterator with duplicates
    const NumberIterator = struct {
        numbers: []const u32,
        position: usize = 0,

        pub fn init(numbers: []const u32) @This() {
            return .{ .numbers = numbers };
        }

        pub fn next(self: *@This()) !?u32 {
            if (self.position >= self.numbers.len) return null;
            const value = self.numbers[self.position];
            self.position += 1;
            return value;
        }
    };

    // Test collecting numbers with duplicates
    const numbers = [_]u32{ 1, 2, 2, 3, 3, 3, 4, 4, 4, 4 };
    var iter = NumberIterator.init(&numbers);
    var set = std.AutoHashMap(u32, void).init(allocator);
    defer set.deinit();

    try collectIntoSet(u32, &iter, &set);

    // Verify set size (should be 4 unique numbers)
    try testing.expectEqual(@as(usize, 4), set.count());

    // Verify all unique numbers are present
    try testing.expect(set.contains(1));
    try testing.expect(set.contains(2));
    try testing.expect(set.contains(3));
    try testing.expect(set.contains(4));

    // Verify a number not in the original sequence is not present
    try testing.expect(!set.contains(5));
}
