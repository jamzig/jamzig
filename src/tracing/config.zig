const std = @import("std");
const build_options = @import("build_options");

pub const LogLevel = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,

    pub fn color(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "\x1b[90m", // Gray
            .debug => "\x1b[36m", // Cyan
            .info => "\x1b[32m", // Green
            .warn => "\x1b[33m", // Yellow
            .err => "\x1b[31m", // Red
        };
    }

    pub fn name(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

pub const Scope = []const u8;

pub const Config = struct {
    allocator: std.mem.Allocator,
    scopes: std.StringHashMap(LogLevel),
    default_level: LogLevel,

    pub fn init(allocator: std.mem.Allocator) Config {
        const scopes_str = if (@hasDecl(build_options, "enable_tracing_scopes"))
            build_options.enable_tracing_scopes
        else
            &[_][]const u8{};

        const level_str = if (@hasDecl(build_options, "enable_tracing_level") and build_options.enable_tracing_level.len > 0)
            build_options.enable_tracing_level
        else
            "info";

        var config = Config{
            .allocator = allocator,
            .scopes = std.StringHashMap(LogLevel).init(allocator),
            .default_level = parseLogLevel(level_str),
        };

        // Parse scope configurations from build options
        for (scopes_str) |scope_config| {
            config.parseAndSetScope(scope_config) catch |err| {
                std.debug.print("Warning: Failed to parse scope config '{s}': {}\n", .{ scope_config, err });
            };
        }

        return config;
    }

    pub fn deinit(self: *Config) void {
        self.scopes.deinit();
    }

    fn parseAndSetScope(self: *Config, scope_config: []const u8) !void {
        if (std.mem.indexOf(u8, scope_config, "=")) |eq_pos| {
            // Format: "scope=level"
            const scope_name = scope_config[0..eq_pos];
            const level_name = scope_config[eq_pos + 1 ..];

            const level = parseLogLevel(level_name);
            try self.scopes.put(scope_name, level);
        } else {
            // Format: just "scope" - enable at debug level
            try self.scopes.put(scope_config, .debug);
        }
    }

    fn parseLogLevel(level_str: []const u8) LogLevel {
        if (std.mem.eql(u8, level_str, "trace")) return .trace;
        if (std.mem.eql(u8, level_str, "debug")) return .debug;
        if (std.mem.eql(u8, level_str, "info")) return .info;
        if (std.mem.eql(u8, level_str, "warn")) return .warn;
        if (std.mem.eql(u8, level_str, "err")) return .err;
        return .info; // Default fallback
    }

    pub fn getLevel(self: *const Config, scope: Scope) LogLevel {
        return self.scopes.get(scope) orelse self.default_level;
    }

    pub fn setScope(self: *Config, scope: Scope, level: LogLevel) !void {
        try self.scopes.put(scope, level);
    }

    pub fn setDefaultLevel(self: *Config, level: LogLevel) void {
        self.default_level = level;
    }

    pub fn reset(self: *Config) void {
        self.scopes.clearRetainingCapacity();
        self.default_level = .info;
    }

    pub fn disableScope(self: *Config, scope: Scope) void {
        _ = self.scopes.remove(scope);
    }

    pub fn findScope(self: *const Config, scope: Scope) ?LogLevel {
        return self.scopes.get(scope);
    }

    pub fn isActive(self: *const Config, scope: Scope, level: LogLevel) bool {
        const scope_level = self.getLevel(scope);
        return @intFromEnum(level) >= @intFromEnum(scope_level);
    }

    pub fn fromBuildOptions(options: []const u8) Config {
        // This method is for compatibility but not used in current implementation
        // The actual parsing is done in init() using build_options directly
        _ = options;
        @panic("fromBuildOptions deprecated - use init() instead");
    }
};
