const std = @import("std");
const types = @import("types.zig");

const WorkPackageHash = types.WorkPackageHash;

pub fn Xi(comptime epoch_size: usize) type {
    return struct {
        // Array of sets, each containing work package hashes
        entries: [epoch_size]std.AutoHashMapUnmanaged(WorkPackageHash, void),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .entries = [_]std.AutoHashMapUnmanaged(WorkPackageHash, void){.{}} ** epoch_size,
                .allocator = allocator,
            };
        }

        pub fn deepClone(self: *const @This(), allocator: std.mem.Allocator) !@This() {
            var cloned = @This(){
                .entries = undefined,
                .allocator = allocator,
            };
            for (self.entries, 0..) |slot_entries, i| {
                cloned.entries[i] = std.AutoHashSetUnmanaged(WorkPackageHash){};
                var iterator = slot_entries.iterator();
                while (iterator.next()) |entry| {
                    try cloned.entries[i].put(allocator, entry.*);
                }
            }
            return cloned;
        }

        pub fn deinit(self: *@This()) void {
            for (&self.entries) |*slot_entries| {
                slot_entries.deinit(self.allocator);
            }
            self.* = undefined;
        }

        pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
            try @import("state_json/accumulated_reports.zig").jsonStringify(epoch_size, self, jw);
        }

        pub fn format(
            self: *const @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try @import("state_format/accumulated_reports.zig").format(epoch_size, self, fmt, options, writer);
        }

        pub fn addWorkPackageToTimeSlot(
            self: *@This(),
            time_slot: types.TimeSlot,
            work_package_hash: WorkPackageHash,
        ) !void {
            try self.entries[time_slot].put(self.allocator, work_package_hash, {});
        }

        pub fn containsWorkPackage(
            self: *const @This(),
            work_package_hash: WorkPackageHash,
        ) bool {
            for (self.entries) |slot_entries| {
                if (slot_entries.contains(work_package_hash)) {
                    return true;
                }
            }
            return false;
        }
    };
}

const testing = std.testing;
test "Xi - init, add entries, and verify" {
    const allocator = std.testing.allocator;
    var xi = Xi(12).init(allocator);
    defer xi.deinit();

    // Create sample work package hash
    const work_package_hash = [_]u8{1} ** 32;

    // Add work package to time slot
    try xi.addWorkPackageToTimeSlot(2, work_package_hash);

    // Verify the contents
    try testing.expectEqual(@as(usize, 12), xi.entries.len);
    try testing.expectEqual(@as(usize, 1), xi.entries[2].count());
    try testing.expect(xi.entries[2].contains(work_package_hash));
    try testing.expect(xi.containsWorkPackage(work_package_hash));
}
