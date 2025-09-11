// Shared memory types for all PVM memory implementations

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Memory slice with optional ownership management
pub const MemorySlice = struct {
    buffer: []const u8,
    allocator: ?Allocator = null,

    /// Take ownership of the buffer, this object is not responsible for freeing it anymore
    /// but it will point to the buffer, which could be internal memory. If it was pointing
    /// to internal memory, we will dupe so the caller can safely use it
    pub fn takeBufferOwnership(self: *MemorySlice, allocator: Allocator) ![]const u8 {
        if (self.allocator) |_| {
            self.allocator = null; // Clear allocator reference
            return self.buffer;
        } else {
            // Buffer is internal memory, create a copy for the caller
            const owned_copy = try allocator.dupe(u8, self.buffer);
            return owned_copy;
        }
    }

    pub fn deinit(self: *MemorySlice) void {
        if (self.allocator) |alloc| {
            alloc.free(self.buffer);
            self.allocator = null;
        }
        self.* = undefined;
    }
};

/// Memory access violation information
pub const ViolationInfo = struct {
    violation_type: ViolationType,
    address: u32, // aligned to page
    attempted_size: usize,
};

/// Types of memory access violations
pub const ViolationType = enum {
    WriteProtection,
    AccessViolation,
    NonAllocated,
};

/// Page access flags
pub const PageFlags = enum {
    ReadOnly,
    ReadWrite,
};

/// Result of memory access pointer lookup
pub const MemoryAccessResult = union(enum) {
    success: [*]u8,
    violation: ViolationInfo,
};

