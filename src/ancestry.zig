const std = @import("std");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const HeaderHash = types.HeaderHash;
const TimeSlot = types.TimeSlot;

/// Ancestry component for storing historical block headers
/// Provides O(1) lookup for header hash -> timeslot mapping
/// Used for validating lookup-anchors in work reports
pub const Ancestry = struct {
    /// Map of header_hash -> timeslot for efficient lookup
    headers: std.AutoHashMap(HeaderHash, TimeSlot),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Ancestry {
        return .{
            .headers = std.AutoHashMap(HeaderHash, TimeSlot).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Ancestry) void {
        self.headers.deinit();
        self.* = undefined;
    }

    /// Deep clone the ancestry
    pub fn deepClone(self: *const Ancestry, allocator: Allocator) !Ancestry {
        var new_ancestry = Ancestry.init(allocator);
        errdefer new_ancestry.deinit();

        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            try new_ancestry.headers.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        return new_ancestry;
    }

    /// Add a header hash and its timeslot to the ancestry
    pub fn addHeader(self: *Ancestry, hash: HeaderHash, timeslot: TimeSlot) !void {
        try self.headers.put(hash, timeslot);
    }

    /// Look up the timeslot for a given header hash
    pub fn lookupTimeslot(self: *const Ancestry, hash: HeaderHash) ?TimeSlot {
        return self.headers.get(hash);
    }

    /// Remove entries older than the specified slot
    pub fn pruneOldEntries(self: *Ancestry, current_slot: TimeSlot, max_age: u32) !void {
        const cutoff_slot = current_slot -| max_age;

        var entries_to_remove = std.ArrayList(HeaderHash).init(self.allocator);
        defer entries_to_remove.deinit();

        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.* < cutoff_slot) {
                try entries_to_remove.append(entry.key_ptr.*);
            }
        }

        for (entries_to_remove.items) |hash| {
            _ = self.headers.remove(hash);
        }
    }

    /// Get the number of entries in the ancestry
    pub fn count(self: *const Ancestry) u32 {
        return @intCast(self.headers.count());
    }
};