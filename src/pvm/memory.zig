const std = @import("std");
const Allocator = std.mem.Allocator;

const trace = @import("../tracing.zig").scoped(.pvm);

pub const Memory = struct {
    // Memory layout constants moved into Memory struct
    pub const Z_Z: u32 = 0x10000; // 2^16 = 65,536 - Major zone size
    pub const Z_P: u32 = 0x1000; // 2^12 = 4,096 - Page size
    pub const Z_I: u32 = 0x1000000; // 2^24 - Standard input data size

    pub const PageMap = struct {
        address: u32,
        length: u32,
        state: AccessState,
        data: []u8,
    };

    // AccessSate
    pub const AccessState = enum {
        /// Memory region is readable only
        ReadOnly,
        /// Memory region is readable and writable
        ReadWrite,
        /// Memory region cannot be accessed
        Inaccessible,
    };

    // Encapsulated memory section configuration
    pub const Section = struct {
        address: u32,
        size: usize,
        state: AccessState,

        pub fn init(address: u32, size: usize, state: AccessState) Section {
            return .{
                .address = address,
                .size = size,
                .state = state,
            };
        }
    };

    // Standard memory layout configuration
    pub const Layout = struct {
        code: Section,
        heap: Section,
        input: Section,
        stack: Section,

        /// Create a standard memory layout with owned slices
        /// Takes ownership of the provided code and input slices and places them in the layout.
        /// The memory pages for these sections will only be allocated when they are accessed.
        ///
        /// Parameters:
        ///   code: Code section slice that will be owned by the layout
        ///   input: Optional input data slice that will be owned by the layout
        pub fn standard(code_len: usize, input_len: usize) Layout {
            return .{
                .code = Section.init(Z_Z, code_len, .ReadOnly),
                .heap = Section.init(2 * Z_Z + @as(u32, @intCast(code_len)), Z_Z, .ReadWrite),
                .input = Section.init(0xFFFFFFFF - Z_Z - Z_I, input_len, .ReadOnly),
                .stack = Section.init(0xFFFFFFFF - Z_Z, Z_Z, .ReadWrite),
            };
        }
    };

    layout: Layout,
    page_maps: []PageMap,
    allocator: Allocator,

    pub fn init(allocator: Allocator, layout: Layout) !Memory {
        var page_maps = std.ArrayList(PageMap).init(allocator);
        errdefer {
            for (page_maps.items) |page| {
                allocator.free(page.data);
            }
            page_maps.deinit();
        }

        // Add sections in order, but only allocate for sections with data
        inline for (.{ layout.code, layout.heap, layout.input, layout.stack }) |section| {
            try page_maps.append(.{
                .address = section.address,
                .length = @intCast(section.size),
                .state = section.state,
                .data = &[_]u8{},
            });
        }

        return Memory{
            .page_maps = try page_maps.toOwnedSlice(),
            .layout = layout,
            .allocator = allocator,
        };
    }

    pub fn write(self: *Memory, address: u32, data: []const u8) !void {
        for (self.page_maps) |*page| {
            if (address >= page.address and address < page.address + page.length) {
                if (page.state != .ReadWrite) return error.WriteProtected;

                // Lazy allocation on first write
                // TODO: figure out how to actually do this

                const offset = address - page.address;
                if (offset + data.len > page.length) return error.OutOfBounds;
                return;
            }
        }
        return error.PageFault;
    }

    pub fn read(self: *const Memory, address: u32, size: usize) ![]const u8 {
        for (self.page_maps) |page| {
            if (address >= page.address and address < page.address + page.length) {
                if (page.state == .Inaccessible) return error.AccessViolation;

                const offset = address - page.address;
                if (offset + size > page.length) return error.OutOfBounds;

                // For unallocated pages, return zeros
                if (page.data.len < offset + size) {
                    return error.NonAllocatedMemoryAccess; // TODO: handle this
                }

                return page.data[offset .. offset + size];
            }
        }
        return error.PageFault;
    }

    pub fn deinit(self: *Memory) void {
        for (self.page_maps) |page| {
            self.allocator.free(page.data);
        }
        self.allocator.free(self.page_maps);
        self.* = undefined;
    }

    pub fn initSection(self: *Memory, address: u32, data: []const u8) !void {
        for (self.page_maps) |*page| {
            if (page.address == address) {
                if (data.len > page.length) return error.OutOfBounds;
                std.debug.assert(page.data.len == 0); // Assert section is empty
                page.data = try self.allocator.dupe(u8, data);
                return;
            }
        }
        return error.SectionNotFound;
    }

    pub fn initSectionByName(self: *Memory, section: enum {
        code,
        heap,
        input,
        stack,
    }, data: []const u8) !void {
        const address = switch (section) {
            .code => self.layout.code.address,
            .heap => self.layout.heap.address,
            .input => self.layout.input.address,
            .stack => self.layout.stack.address,
        };
        try self.initSection(address, data);
    }
};
