/// Tracy tracing backend - zones and messages integrated with Tracy profiler
const std = @import("std");
const tracy = @import("tracy");
const config_mod = @import("tracing/config.zig");

pub const LogLevel = config_mod.LogLevel;
pub const Config = config_mod.Config;

// Static buffer for tracing configuration
var config_buffer: [4096]u8 align(@alignOf(std.StringHashMap(LogLevel).KV)) = undefined;
var config_fba = std.heap.FixedBufferAllocator.init(&config_buffer);

// Global config instance - initialized on first use
var config: ?Config = null;

// Get config, initializing if necessary
fn getConfig() *Config {
    if (config == null) {
        config = Config.init(config_fba.allocator());
    }
    return &config.?;
}

pub const TracingScope = struct {
    name: []const u8,

    const Self = @This();

    pub fn init(comptime scope: @Type(.enum_literal)) Self {
        return comptime Self{
            .name = @tagName(scope),
        };
    }

    pub fn span(comptime self: *const Self, operation: @Type(.enum_literal)) Span {
        return Span.init(self.name, @tagName(operation));
    }
};

pub const Span = struct {
    scope: []const u8,
    operation: []const u8,
    tracy_zone: tracy.ZoneCtx,

    pub fn init(scope: []const u8, operation: [:0]const u8) Span {
        return Span{
            .scope = scope,
            .operation = operation,
            .tracy_zone = tracy.ZoneN(@src(), operation),
        };
    }

    pub fn child(self: *const Span, operation: @Type(.enum_literal)) Span {
        return Span.init(self.scope, @tagName(operation));
    }

    pub fn deinit(self: *const Span) void {
        self.tracy_zone.End();
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
        const cfg = getConfig();
        const scope_level = cfg.findScope(self.scope) orelse cfg.default_level;

        if (@intFromEnum(level) < @intFromEnum(scope_level)) {
            return;
        }

        var message_buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&message_buf, fmt, args) catch "formatting error";
        tracy.Message(message);
    }
};

// Module initialization (no-ops for Tracy mode - config initialized on first use)
pub fn init(_: std.mem.Allocator) void {}
pub fn deinit() void {}

// Configuration API
pub fn setScope(name: []const u8, level: LogLevel) !void {
    try getConfig().setScope(name, level);
}

pub fn setDefaultLevel(level: LogLevel) void {
    getConfig().setDefaultLevel(level);
}

pub fn reset() void {
    getConfig().reset();
}

pub fn disableScope(name: []const u8) void {
    getConfig().disableScope(name);
}

pub fn findScope(name: []const u8) ?LogLevel {
    return getConfig().findScope(name);
}

pub fn scoped(comptime scope: @Type(.enum_literal)) TracingScope {
    return comptime TracingScope.init(scope);
}
