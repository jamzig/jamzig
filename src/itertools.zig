const std = @import("std");

// Iterator utilities
pub const collect = @import("itertools/collect.zig");
pub const map_struct_field = @import("itertools/map_struct_field.zig");
pub const multi_slice = @import("itertools/multi_slice.zig");

// Re-export all public functionality
pub const collectIntoAppendable = collect.collectIntoAppendable;
pub const collectIntoSet = collect.collectIntoSet;
pub const MapStructFieldIter = map_struct_field.MapStructFieldIter;
pub const MultiSliceIter = multi_slice.MultiSliceIter;

test {
    // Run tests from all modules
    std.testing.refAllDecls(@This());
    _ = @import("itertools/collect.zig");
    _ = @import("itertools/map_struct_field.zig");
    _ = @import("itertools/multi_slice.zig");
}
