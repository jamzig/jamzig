const std = @import("std");
const diffz = @import("diffz");
const safrole = @import("../safrole.zig");

const DiffList = std.ArrayListUnmanaged(diffz.Diff);

const dmp = diffz{
    .diff_timeout = 250,
    .diff_check_lines_over = 10,
};

pub const Error = error{OutOfMemory} || diffz.DiffError;

pub fn diffSlice(
    allocator: std.mem.Allocator,
    before: []const u8,
    after: []const u8,
) Error!DiffList {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    return try dmp.diff(arena.allocator(), before, after, true);
}

pub fn diffStates(
    allocator: std.mem.Allocator,
    before: *const safrole.types.State,
    after: *const safrole.types.State,
) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_alloc = arena.allocator();

    // Print both before and after states
    const before_str = try std.fmt.allocPrint(arena_alloc, "{any}", .{before});
    const after_str = try std.fmt.allocPrint(arena_alloc, "{any}", .{after});

    var diffs = try dmp.diff(
        arena_alloc,
        before_str,
        after_str,
        true,
    );
    defer diffs.deinit(arena_alloc);

    const diffs_slice = try diffs.toOwnedSlice(arena_alloc);
    defer arena_alloc.free(diffs_slice);

    const patch = try generatePatchOutput(allocator, diffs_slice, 4);
    defer allocator.free(patch);

    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{s}\n", .{patch});

    // for (diffs.items) |diff| {
    //     try std.fmt.format(buffer.writer(), "{any}\n", .{diff});
    // }

    return buffer.toOwnedSlice();
}

pub fn generatePatchOutput(
    allocator: std.mem.Allocator,
    diffs: []diffz.Diff,
    context_lines: usize,
) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    var line_number: usize = 1;
    var in_hunk: bool = false;

    for (diffs) |diff| {
        var lines = std.mem.splitSequence(u8, diff.text, "\n");
        switch (diff.operation) {
            .equal => {
                while (lines.next()) |line| {
                    if (in_hunk) {
                        try std.fmt.format(buffer.writer(), " {s}\n", .{line});
                    }
                    line_number += 1;
                }
                in_hunk = false;
            },
            .insert, .delete => {
                if (!in_hunk) {
                    try std.fmt.format(buffer.writer(), "@@ -{d},{d} +{d},{d} @@\n", .{ line_number - context_lines, context_lines * 2, line_number - context_lines, context_lines * 2 });
                    in_hunk = true;
                }
                while (lines.next()) |line| {
                    const prefix = if (diff.operation == .insert) "+" else "-";
                    try std.fmt.format(buffer.writer(), "{s}{s}\n", .{ prefix, line });
                    if (diff.operation == .delete) {
                        line_number += 1;
                    }
                }
            },
        }
    }

    return try buffer.toOwnedSlice();
}

test "diff between two strings" {
    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();

    const string1 = "Hello world!";
    const string2 = "Hello brave new world!";

    var diffs = try dmp.diff(
        arena_allocator,
        string1,
        string2,
        true,
    );
    defer diffs.deinit(arena_allocator);

    for (diffs.items) |diff| {
        std.debug.print("{any}\n", .{diff});
    }
}
