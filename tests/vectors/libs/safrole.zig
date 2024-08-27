const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

const Input = struct {};

const PreState = struct {};

const Output = struct {};

const PostState = struct {};

pub const TestVector = struct {
    input: Input,
    pre_state: PreState,
    output: Output,
    post_state: PostState,

    pub fn init(allocator: Allocator, file_path: []const u8) !TestVector {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(buffer);

        const bytes_read = try file.readAll(buffer);
        if (bytes_read != file_size) {
            return error.IncompleteRead;
        }

        return try TestVector.parse(allocator, buffer);
    }

    pub fn parse(allocator: Allocator, json_str: []const u8) !TestVector {
        var parsed = try json.parseFromSlice(TestVector, allocator, json_str, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return parsed.value;
    }
};
