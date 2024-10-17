const std = @import("std");
const Allocator = std.mem.Allocator;
const Blake2b256 = std.crypto.hash.blake2.Blake2b(256);
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const merkle = @import("merkle_binary.zig");
const mmr = @import("merkle_mountain_ranges.zig");

pub const Hash = [32]u8;

pub const BlockInfo = struct {
    header_hash: Hash,
    state_root: Hash,
    beefy_mmr: []?Hash,
    work_report_hashes: []Hash,
};

pub const RecentBlock = struct {
    /// Header of the block
    header_hash: Hash,
    /// Parent state root H_r
    parent_state_root: Hash,
    /// Derived from C as defined in section 12
    /// using the basic merklization M_b => the merkle root of results
    accumulate_root: Hash,
    /// The hashes of the work reports
    work_report_hashes: []Hash,
};

pub const RecentHistory = struct {
    const Self = @This();

    allocator: Allocator,
    blocks: std.ArrayList(BlockInfo),
    max_blocks: usize,

    pub fn init(allocator: Allocator, max_blocks: usize) !Self {
        return Self{
            .allocator = allocator,
            .blocks = try std.ArrayList(BlockInfo).initCapacity(allocator, max_blocks),
            .max_blocks = max_blocks,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.blocks.items) |*block| {
            self.allocator.free(block.beefy_mmr);
            self.allocator.free(block.work_report_hashes);
        }
        self.blocks.deinit();
    }

    pub fn import(self: *Self, allocator: Allocator, input: RecentBlock) !void {
        // Create a new BlockStateInformation
        var block_info = BlockInfo{
            .header_hash = input.header_hash,
            .state_root = std.mem.zeroes(Hash), // This will be updated in the next block
            .beefy_mmr = undefined,
            .work_report_hashes = try allocator.dupe(Hash, input.work_report_hashes),
        };

        // Update the parent block's state root if it exists
        if (self.blocks.items.len > 0) {
            self.blocks.items[self.blocks.items.len - 1].state_root = input.parent_state_root;
        }

        // Append the accumlate root Beefy MMR
        const last_beefy_mmr = if (self.blocks.getLastOrNull()) |last_block|
            try allocator.dupe(?Hash, last_block.beefy_mmr)
        else
            &[_]?Hash{};

        var beefy_mmr = mmr.MMR.fromOwnedSlice(allocator, @constCast(last_beefy_mmr));
        // errdefer beefy_mmr.deinit();

        // Append the accumulate root to the Beefy MMR
        try mmr.append(&beefy_mmr, input.accumulate_root, Keccak256);

        // Update the new block's Beefy MMR
        block_info.beefy_mmr = try beefy_mmr.toOwnedSlice();

        // Add the new block to the recent history
        try self.addBlockInfo(block_info);
    }

    pub fn addBlockInfo(self: *Self, new_block: BlockInfo) !void {
        if (self.blocks.items.len == self.max_blocks) {
            const oldest_block = self.blocks.orderedRemove(0);
            self.allocator.free(oldest_block.beefy_mmr);
            self.allocator.free(oldest_block.work_report_hashes);
        }

        try self.blocks.append(new_block);
    }

    pub fn getBlockInfo(self: Self, index: usize) ?BlockInfo {
        if (index < self.blocks.items.len) {
            return self.blocks.items[index];
        }
        return null;
    }
};

const testing = std.testing;

test RecentHistory {
    const allocator = testing.allocator;
    var recent_history = try RecentHistory.init(allocator, 3);
    defer recent_history.deinit();

    // Test initial state
    try testing.expectEqual(@as(usize, 0), recent_history.blocks.items.len);

    // Create some test blocks
    const block1 = BlockInfo{
        .header_hash = [_]u8{1} ** 32,
        .state_root = [_]u8{2} ** 32,
        .beefy_mmr = try allocator.dupe(?Hash, &.{[_]u8{3} ** 32}),
        .work_report_hashes = try allocator.dupe(Hash, &.{[_]u8{4} ** 32}),
    };
    const block2 = BlockInfo{
        .header_hash = [_]u8{5} ** 32,
        .state_root = [_]u8{6} ** 32,
        .beefy_mmr = try allocator.dupe(?Hash, &.{[_]u8{7} ** 32}),
        .work_report_hashes = try allocator.dupe(Hash, &.{[_]u8{8} ** 32}),
    };
    const block3 = BlockInfo{
        .header_hash = [_]u8{9} ** 32,
        .state_root = [_]u8{10} ** 32,
        .beefy_mmr = try allocator.dupe(?Hash, &.{[_]u8{11} ** 32}),
        .work_report_hashes = try allocator.dupe(Hash, &.{[_]u8{12} ** 32}),
    };
    const block4 = BlockInfo{
        .header_hash = [_]u8{13} ** 32,
        .state_root = [_]u8{14} ** 32,
        .beefy_mmr = try allocator.dupe(?Hash, &.{[_]u8{15} ** 32}),
        .work_report_hashes = try allocator.dupe(Hash, &.{[_]u8{16} ** 32}),
    };

    // Test adding blocks
    try recent_history.addBlockInfo(block1);
    try testing.expectEqual(@as(usize, 1), recent_history.blocks.items.len);

    try recent_history.addBlockInfo(block2);
    try testing.expectEqual(@as(usize, 2), recent_history.blocks.items.len);

    try recent_history.addBlockInfo(block3);
    try testing.expectEqual(@as(usize, 3), recent_history.blocks.items.len);

    // Test max_blocks limit
    try recent_history.addBlockInfo(block4);
    try testing.expectEqual(@as(usize, 3), recent_history.blocks.items.len);

    // Test get stateinformation
    const retrieved_block = recent_history.getBlockInfo(1);
    try testing.expect(retrieved_block != null);
    if (retrieved_block) |state_info| {
        try testing.expectEqualSlices(u8, &block3.header_hash, &state_info.header_hash);
    }

    // Test getting non-existent block
    const non_existent_block = recent_history.getBlockInfo(3);
    try testing.expect(non_existent_block == null);
}
