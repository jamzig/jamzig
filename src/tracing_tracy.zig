/// Tracy tracing backend - zones and messages integrated with Tracy profiler
const std = @import("std");
const tracy = @import("tracy");
const config_mod = @import("tracing/config.zig");

pub const LogLevel = config_mod.LogLevel;

// Global config instance for Tracy mode
var config: config_mod.BuildConfig = undefined;

pub const TracingScope = struct {
    name: []const u8,

    const Self = @This();

    pub fn init(comptime scope: @Type(.enum_literal)) Self {
        return comptime Self{
            .name = @tagName(scope),
        };
    }

    pub fn span(comptime self: *const Self, operation: @Type(.enum_literal)) Span {
        _ = operation; // Ignore operation name for now
        return Span.init(self.name);
    }
};

pub const Span = struct {
    name: []const u8,
    tracy_zone: tracy.ZoneCtx,
    min_level: LogLevel,
    active: bool,

    pub fn init(name: []const u8) Span {
        const min_level = config.getLevel(name);
        return Span{
            .name = name,
            .tracy_zone = tracy.ZoneN(@src(), name.ptr),
            .min_level = min_level,
            .active = true,
        };
    }

    pub fn child(self: *const Span, operation: @Type(.enum_literal)) Span {
        _ = operation; // Ignore operation name for now  
        return Span.init(self.name);
    }

    pub fn deinit(self: *const Span) void {
        @constCast(&self.tracy_zone).End();
    }

    pub inline fn trace(self: *const Span, comptime fmt: []const u8, args: anytype) void {
        self.log(.trace, fmt, args);
    }

    pub inline fn debug(self: *const Span, comptime fmt: []const u8, args: anytype) void {
        self.log(.debug, fmt, args);
    }

    pub inline fn info(self: *const Span, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }

    pub inline fn warn(self: *const Span, comptime fmt: []const u8, args: anytype) void {
        self.log(.warn, fmt, args);
    }

    pub inline fn err(self: *const Span, comptime fmt: []const u8, args: anytype) void {
        self.log(.err, fmt, args);
    }

    inline fn log(self: *const Span, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        if (!self.active or @intFromEnum(level) < @intFromEnum(self.min_level)) return;
        
        var message_buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&message_buf, fmt, args) catch "formatting error";
        tracy.Message(message);
    }
};

// Module initialization
pub fn init(allocator: std.mem.Allocator) void {
    config = config_mod.BuildConfig.init(allocator);
}

pub fn deinit() void {
    config.deinit();
}

// Configuration API (delegate to config)
pub fn setScope(name: []const u8, level: LogLevel) !void {
    try config.setScope(name, level);
}

pub fn disableScope(name: []const u8) !void {
    config.disableScope(name);
}

pub fn setDefaultLevel(level: LogLevel) void {
    config.setDefaultLevel(level);
}

pub fn reset() void {
    config.reset();
}

pub fn findScope(name: []const u8) ?LogLevel {
    return config.findScope(name);
}

pub fn scoped(comptime scope: @Type(.enum_literal)) TracingScope {
    return comptime TracingScope.init(scope);
}