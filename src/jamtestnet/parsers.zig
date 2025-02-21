pub const bin = struct {
    pub const state_transition = @import("parsers/bin/state_transition.zig");
};

pub const json = struct {
    // Removed, binary is more convenient
};
