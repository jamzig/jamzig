const std = @import("std");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const HeaderHash = types.HeaderHash;
const TimeSlot = types.TimeSlot;

/// Auxiliary data structure containing implementation-specific supporting data
/// that is not part of the consensus state but needed for validation.
/// This is separate from the core JAM state (σ) which gets merklized.
pub const Auxiliary = struct {
    /// Ancestry headers for lookup-anchor validation (L=24 hours)
    ancestry: ?Ancestry = null,

    /// Empty auxiliary data with all fields null
    pub const Empty = Auxiliary{
        .ancestry = null,
    };

    pub fn deinit(self: *Auxiliary, allocator: Allocator) void {
        if (self.ancestry) |*anc| {
            anc.deinit(allocator);
        }
        self.* = undefined;
    }
};

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

    pub fn deinit(self: *Ancestry, allocator: Allocator) void {
        _ = allocator;
        self.headers.deinit();
        self.* = undefined;
    }

    /// Add a header hash and its timeslot to the ancestry
    pub fn addHeader(self: *Ancestry, hash: HeaderHash, timeslot: TimeSlot) !void {
        try self.headers.put(hash, timeslot);
    }

    /// Look up the timeslot for a given header hash
    pub fn lookupTimeslot(self: *const Ancestry, hash: HeaderHash) ?TimeSlot {
        return self.headers.get(hash);
    }
};

