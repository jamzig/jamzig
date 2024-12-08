/// A hierarchical tracing and logging system that provides scoped operations with colored output.
/// This module enables structured logging with support for nested operations, configurable scopes,
/// and different log levels.
///
const std = @import("std");
const build_options = @import("build_options");

// Get enabled scopes from build options
pub const boption_enabled_scopes = if (@hasDecl(build_options, "enable_tracing_scopes"))
    build_options.enable_tracing_scopes
else
    @as([]const []const u8, &[_][]const u8{});

pub const boption_enabled_level = if (@hasDecl(build_options, "enable_tracing_level"))
    LogLevel.fromString(build_options.enable_tracing_level) catch @panic("Invalid tracing_level value")
else
    LogLevel.info;

// Allowed log levels

pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,

    pub fn fromString(str: []const u8) !LogLevel {
        inline for (@typeInfo(LogLevel).@"enum".fields) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return error.InvalidLogLevel;
    }

    pub fn format(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "\x1b[90m•", // bright black/gray bullet
            .debug => "\x1b[36m•", // cyan bullet
            .info => "\x1b[32m•", // green bullet
            .warn => "\x1b[33m⚠", // yellow warning
            .err => "\x1b[31m✖", // red x
        };
    }
};

threadlocal var indent_level: usize = 0;

pub const TracingScope = struct {
    name: []const u8,

    const Self = @This();

    pub fn init(comptime scope: @Type(.enum_literal)) Self {
        return comptime Self{
            .name = @tagName(scope),
        };
    }

    pub fn span(comptime self: *const Self, operation: @Type(.enum_literal)) SpanUnion {
        const is_enabled = comptime if (boption_enabled_scopes.len == 0) true else blk: {
            for (boption_enabled_scopes) |enabled_scope| {
                if (std.mem.eql(u8, enabled_scope, self.name)) break :blk true;
            }
            break :blk false;
        };
        return if (is_enabled)
            SpanUnion{ .Enabled = Span.init(self, operation, null, true, boption_enabled_level) }
        else
            SpanUnion{ .Disabled = DisabledSpan{} };
    }
};

pub const Span = struct {
    scope: *const TracingScope,
    operation: []const u8,
    parent: ?*const Span,
    start_indent: usize,
    enabled: bool,
    min_level: LogLevel,

    const Self = @This();

    pub fn init(
        scope: *const TracingScope,
        operation: @Type(.enum_literal),
        parent: ?*const Span,
        enabled: bool,
        min_level: LogLevel,
    ) Self {
        const span = Self{
            .scope = scope,
            .operation = @tagName(operation),
            .parent = parent,
            .start_indent = indent_level,
            .enabled = enabled,
            .min_level = min_level,
        };

        // Print enter marker with arrow
        if (parent == null) {
            span.debug("\x1b[1m{s} →\x1b[22m\n", .{span.operation});
        }

        indent_level += 1;
        return span;
    }

    pub fn child(self: *const Self, operation: @Type(.enum_literal)) Span {
        return Span.init(self.scope, operation, self, self.enabled, self.min_level);
    }

    pub fn deinit(self: *const Self) void {
        indent_level = self.start_indent;
        // Only print exit marker for top-level spans
        if (self.parent == null) {
            self.debug("← {s}\n", .{self.operation});
        }
    }

    pub inline fn trace(self: *const Self, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(LogLevel.trace) >= @intFromEnum(self.min_level)) {
            self.log(.trace, fmt, args);
        }
    }

    pub inline fn debug(self: *const Self, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(LogLevel.debug) >= @intFromEnum(self.min_level)) {
            self.log(.debug, fmt, args);
        }
    }

    pub inline fn info(self: *const Self, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(LogLevel.info) >= @intFromEnum(self.min_level)) {
            self.log(.info, fmt, args);
        }
    }

    pub inline fn warn(self: *const Self, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(LogLevel.warn) >= @intFromEnum(self.min_level)) {
            self.log(.warn, fmt, args);
        }
    }

    pub inline fn err(self: *const Self, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(LogLevel.err) >= @intFromEnum(self.min_level)) {
            self.log(.err, fmt, args);
        }
    }

    fn printIndent(_: *const Self) void {
        var i: usize = 0;
        while (i < indent_level * 4) : (i += 1) {
            std.debug.print(" ", .{});
        }
    }

    inline fn log(self: *const Self, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled or @intFromEnum(level) < @intFromEnum(self.min_level)) return;

        self.printIndent();

        std.debug.print("{s} ", .{level.format()});
        std.debug.print(fmt ++ "\x1b[0m\n", args);
    }
};

pub const SpanUnion = union(enum) {
    Enabled: Span,
    Disabled: DisabledSpan,

    pub fn deinit(self: *const SpanUnion) void {
        switch (self.*) {
            .Enabled => |span| span.deinit(),
            .Disabled => {},
        }
    }

    pub fn child(self: *const SpanUnion, operation: @Type(.enum_literal)) SpanUnion {
        return switch (self.*) {
            .Enabled => |span| SpanUnion{ .Enabled = span.child(operation) },
            .Disabled => SpanUnion{ .Disabled = DisabledSpan{} },
        };
    }

    pub inline fn trace(self: *const SpanUnion, comptime fmt: []const u8, args: anytype) void {
        switch (self.*) {
            .Enabled => |span| span.trace(fmt, args),
            .Disabled => {},
        }
    }

    pub inline fn debug(self: *const SpanUnion, comptime fmt: []const u8, args: anytype) void {
        switch (self.*) {
            .Enabled => |span| span.debug(fmt, args),
            .Disabled => {},
        }
    }

    pub inline fn info(self: *const SpanUnion, comptime fmt: []const u8, args: anytype) void {
        switch (self.*) {
            .Enabled => |span| span.info(fmt, args),
            .Disabled => {},
        }
    }

    pub inline fn warn(self: *const SpanUnion, comptime fmt: []const u8, args: anytype) void {
        switch (self.*) {
            .Enabled => |span| span.warn(fmt, args),
            .Disabled => {},
        }
    }

    pub inline fn err(self: *const SpanUnion, comptime fmt: []const u8, args: anytype) void {
        switch (self.*) {
            .Enabled => |span| span.err(fmt, args),
            .Disabled => {},
        }
    }
};

pub const DisabledSpan = struct {
    // Empty struct since we don't need to store any state

    pub inline fn trace(_: *const DisabledSpan, comptime _: []const u8, _: anytype) void {}
    pub inline fn debug(_: *const DisabledSpan, comptime _: []const u8, _: anytype) void {}
    pub inline fn info(_: *const DisabledSpan, comptime _: []const u8, _: anytype) void {}
    pub inline fn warn(_: *const DisabledSpan, comptime _: []const u8, _: anytype) void {}
    pub inline fn err(_: *const DisabledSpan, comptime _: []const u8, _: anytype) void {}
};

pub fn scoped(comptime scope: @Type(.enum_literal)) TracingScope {
    return comptime TracingScope.init(scope);
}

test "TracingScope initialization" {
    const testing = std.testing;
    const scope = scoped(.test_scope);
    try testing.expectEqualStrings("test_scope", scope.name);
}

test "Span path construction" {
    const testing = std.testing;
    const scope = scoped(.networking);

    var path_buf: [1024]u8 = undefined;

    // Test single span
    {
        const span = scope.span(.connect);
        defer span.deinit();
        const path = span.getFullPath(&path_buf);
        try testing.expectEqualStrings("networking.connect", path);
    }

    // Test nested spans
    {
        const parent_span = scope.span(.connect);
        defer parent_span.deinit();

        const child_span = parent_span.child(.authenticate);
        defer child_span.deinit();

        const path = child_span.getFullPath(&path_buf);
        try testing.expectEqualStrings("networking.connect.authenticate", path);
    }
}

test "Span parent relationships" {
    const testing = std.testing;
    const scope = scoped(.test_scope);

    const parent = scope.span(.parent);
    defer parent.deinit();
    try testing.expect(parent.parent == null);

    const child = parent.child(.child);
    defer child.deinit();
    try testing.expect(child.parent != null);
    try testing.expectEqual(parent.operation, child.parent.?.operation);
}
