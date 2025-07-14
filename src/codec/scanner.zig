const std = @import("std");
const errors = @import("errors.zig");

/// Scanner provides sequential reading from a byte buffer
/// Used for parsing encoded data without allocation
pub const Scanner = struct {
    /// The underlying data buffer
    buffer: []const u8,
    /// Current read position in the buffer
    cursor: usize,

    /// Creates a new scanner for the given buffer
    pub fn init(buffer: []const u8) Scanner {
        return Scanner{ .buffer = buffer, .cursor = 0 };
    }

    /// Returns the unread portion of the buffer
    pub fn remainingBuffer(self: *const Scanner) []const u8 {
        return self.buffer[self.cursor..];
    }

    /// Advances the cursor by n bytes
    /// Returns error if attempting to advance beyond buffer bounds
    pub fn advanceCursor(self: *Scanner, n: usize) !void {
        if (n > self.buffer.len - self.cursor) {
            return errors.ScannerError.BufferOverrun;
        }

        self.cursor += n;
    }

    /// Reads exactly n bytes from the buffer
    /// Returns error if not enough bytes available
    pub fn readBytes(self: *Scanner, comptime n: usize) ![]const u8 {
        if (n > self.buffer.len - self.cursor) {
            return errors.ScannerError.BufferOverrun;
        }

        const bytes = self.buffer[self.cursor .. self.cursor + n];
        self.cursor += n;
        return bytes;
    }

    /// Reads a single byte from the buffer
    /// Returns error if at end of buffer
    pub fn readByte(self: *Scanner) !u8 {
        if (self.cursor >= self.buffer.len) {
            return errors.ScannerError.BufferOverrun;
        }

        const byte = self.buffer[self.cursor];
        self.cursor += 1;
        return byte;
    }
};
