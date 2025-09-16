const std = @import("std");
const messages = @import("messages.zig");

/// Target interface that all fuzz protocol targets must implement
/// This provides a unified API for both socket-based and embedded targets
pub fn TargetInterface(comptime Self: type) type {
    return struct {
        /// Configuration type for this target
        const Config = Self.Config;

        /// Initialize the target with given configuration
        pub const init = Self.init;

        /// Send a message to the target
        pub const sendMessage = Self.sendMessage;

        /// Read a response message from the target
        pub const readMessage = Self.readMessage;

        /// Clean up target resources
        pub const deinit = Self.deinit;

        /// Optional: Connect to target (for socket-based targets)
        pub const connectToTarget = if (@hasDecl(Self, "connectToTarget")) Self.connectToTarget else null;

        /// Optional: Disconnect from target (for socket-based targets)
        pub const disconnect = if (@hasDecl(Self, "disconnect")) Self.disconnect else null;
    };
}

/// Compile-time validation that a type implements the Target interface
pub fn validateTargetInterface(comptime T: type) void {
    // Required fields and methods
    _ = T.Config;
    _ = T.init;
    _ = T.sendMessage;
    _ = T.readMessage;
    _ = T.deinit;
}

