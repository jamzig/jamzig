const std = @import("std");

pub const MemoryPage = extern struct {
    address: u32,
    data: [*]u8,
    size: usize,
    is_writable: bool,
};

pub const ExecutionStatus = enum(c_int) {
    Success = 0,
    EngineError = 1,
    ProgramError = 2,
    ModuleError = 3,
    InstantiationError = 4,
    MemoryError = 5,
    Trap = 6,
    OutOfGas = 7,
    Segfault = 8,
    InstanceRunError = 9,
    UnknownError = 10,
};

const RawExecutionResult = extern struct {
    status: ExecutionStatus,
    final_pc: u32,
    pages: [*]MemoryPage,
    page_count: usize,
};

pub const ExecutionResult = struct {
    raw: RawExecutionResult,

    pub fn deinit(self: *const ExecutionResult) void {
        free_execution_result(self.raw);
    }

    pub fn getPages(self: *const ExecutionResult) []const MemoryPage {
        return self.raw.pages[0..self.raw.page_count];
    }
};

extern "c" fn execute_pvm(
    bytecode: [*]const u8,
    bytecode_len: usize,
    initial_pages: [*]const MemoryPage,
    page_count: usize,
    gas_limit: u64,
) RawExecutionResult;

extern "c" fn free_execution_result(result: RawExecutionResult) void;

/// Wrapper for execute_pvm that provides a more Zig-friendly interface
pub fn executePvm(
    bytecode: []const u8,
    pages: []const MemoryPage,
    gas_limit: u64,
) ExecutionResult {
    return .{
        .raw = execute_pvm(
            bytecode.ptr,
            bytecode.len,
            pages.ptr,
            pages.len,
            gas_limit,
        ),
    };
}

test "basic execution" {
    // Add tests here
    const allocator = std.testing.allocator;

    const memory = try allocator.alloc(u8, 0x1000);
    defer allocator.free(memory);

    const page = MemoryPage{
        .address = 0x20000,
        .data = memory.ptr,
        .size = 0x4000,
        .is_writable = true,
    };

    const program = [_]u8{ 0x00, 0x01, 0x02, 0x03 };

    const result = executePvm(
        &program,
        &[_]MemoryPage{page},
        10000,
    );
    defer result.deinit();

    try std.testing.expectEqual(result.raw.status, ExecutionStatus.ProgramError);
}
