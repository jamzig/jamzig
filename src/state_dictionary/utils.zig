const std = @import("std");

fn ManagedPtr(comptime T: type) type {
    const has_deinit = if (@hasDecl(T, "deinit"))
        @TypeOf(@field(T, "deinit")) == fn (*T) void or
            @TypeOf(@field(T, "deinit")) == fn (*T, std.mem.Allocator) void
    else
        false;

    const needs_allocator_deinit = if (has_deinit)
        @TypeOf(@field(T, "deinit")) == fn (*T, std.mem.Allocator) void
    else
        false;

    return struct {
        ptr: *const T,
        needs_free: bool,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.needs_free) {
                const ptr = @constCast(self.ptr);
                if (comptime has_deinit) {
                    if (comptime needs_allocator_deinit) {
                        ptr.deinit(allocator);
                    } else {
                        ptr.deinit();
                    }
                }
                allocator.destroy(self.ptr);
            }
        }
    };
}

pub fn getOrInitManaged(
    allocator: std.mem.Allocator,
    maybe_value: anytype,
    comptime init_args: anytype,
) !ManagedPtr(std.meta.Child(std.meta.Child(@TypeOf(maybe_value)))) {
    const T = std.meta.Child(std.meta.Child(@TypeOf(maybe_value)));
    comptime {
        if (@typeInfo(@TypeOf(maybe_value)) != .pointer or
            @typeInfo(std.meta.Child(@TypeOf(maybe_value))) != .optional)
        {
            @compileError("maybe_value must be a pointer to optional type");
        }
        if (@typeInfo(@TypeOf(init_args)) != .@"struct" or
            !@typeInfo(@TypeOf(init_args)).@"struct".is_tuple)
        {
            @compileError("init_args must be a tuple");
        }
    }
    if (maybe_value.*) |value| {
        return .{ .ptr = &value, .needs_free = false };
    } else {

        // Get the type of T.init
        const init_fn = @TypeOf(T.init);
        if (@typeInfo(init_fn) != .@"fn") {
            @compileError("T.init must be a function");
        }

        // Get the return type of T.init
        const ReturnType = @typeInfo(init_fn).@"fn".return_type.?;

        // Check if it returns an error union
        if (@typeInfo(ReturnType) != .error_union) {
            @compileError("T.init must return an error union: T = " ++ @typeName(T));
        }

        // Get the success type from the error union
        const SuccessType = @typeInfo(ReturnType).error_union.payload;
        if (SuccessType != T) {
            @compileError("T.init must return error union of T: T = " ++ @typeName(T));
        }

        const instance = try allocator.create(T);
        errdefer allocator.destroy(instance);

        // Create the value on the heap
        instance.* = try @call(.auto, T.init, init_args);
        return .{ .ptr = instance, .needs_free = true };
    }
}
