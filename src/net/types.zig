const std = @import("std");

/// Creates a type-safe wrapper around u64 for ID types
pub fn Id(comptime IdType: type) type {
    return struct {
        id: IdType,

        const Self = @This();

        /// Create a new ID with the given id
        pub fn init(id: IdType) Self {
            return .{ .id = id };
        }

        /// Create a new ID from a raw value
        pub fn fromRaw(raw: IdType) Self {
            return .{ .id = raw };
        }

        /// Get the raw id value
        pub fn toRaw(self: Self) IdType {
            return self.id;
        }

        /// Compare for equality
        pub fn eql(self: Self, other: Self) bool {
            return self.id == other.id;
        }
    };
}

/// ConnectionId represents a unique identifier for a connection.
pub const ConnectionId = Id(u64);

/// StreamId represents a unique identifier for a stream within a connection.
pub const StreamId = Id(u64);
