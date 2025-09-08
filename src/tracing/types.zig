const std = @import("std");

pub const LogLevel = enum {
    trace, debug, info, warn, err,
    
    pub fn symbol(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "•",
            .debug => "○", 
            .info => "→",
            .warn => "⚠",
            .err => "✖",
        };
    }
    
    pub fn fromString(str: []const u8) !LogLevel {
        inline for (@typeInfo(LogLevel).@"enum".fields) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return error.InvalidLogLevel;
    }
};