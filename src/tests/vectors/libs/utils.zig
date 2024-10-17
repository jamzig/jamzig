const std = @import("std");

pub fn TestVector(comptime T: type) type {
    return struct {
        expected: std.json.Parsed(T),
        allocator: std.mem.Allocator,

        pub fn build_from(
            allocator: std.mem.Allocator,
            json_path: []const u8,
        ) !TestVector(T) {
            const file = try std.fs.cwd().openFile(json_path, .{});
            defer file.close();

            const json_buffer = try file.readToEndAlloc(allocator, 5 * 1024 * 1024);
            defer allocator.free(json_buffer);

            var diagnostics = std.json.Diagnostics{};
            var scanner = std.json.Scanner.initCompleteInput(allocator, json_buffer);
            scanner.enableDiagnostics(&diagnostics);
            defer scanner.deinit();

            const expected = std.json.parseFromTokenSource(
                T,
                allocator,
                &scanner,
                .{
                    .ignore_unknown_fields = true,
                    .parse_numbers = false,
                },
            ) catch |err| {
                std.debug.print("Could not parse {s} [{s}]: {}\n{any}", .{ @typeName(T), json_path, err, diagnostics });
                return err;
            };

            return .{
                .expected = expected,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: @This()) void {
            self.expected.deinit();
        }
    };
}
