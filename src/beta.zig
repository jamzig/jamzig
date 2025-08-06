/// Beta component
/// Contains both recent block history and the BEEFY belt (MMR of accumulation outputs)
const std = @import("std");
const types = @import("types.zig");
const mmr = @import("merkle/mmr.zig");
const Allocator = std.mem.Allocator;

/// The Beta component containing recent history and BEEFY belt
pub const Beta = struct {
    /// β_H: Information on the most recent blocks
    recent_history: RecentHistory,

    /// β_B: The Merkle Mountain Belt for accumulating Accumulation outputs
    beefy_belt: BeefyBelt,

    allocator: Allocator,

    pub fn init(allocator: Allocator, max_blocks: usize) !Beta {
        return Beta{
            .recent_history = try RecentHistory.init(allocator, max_blocks),
            .beefy_belt = try BeefyBelt.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Beta) void {
        self.recent_history.deinit();
        self.beefy_belt.deinit();
        self.* = undefined;
    }

    pub fn deepClone(self: *const Beta, allocator: Allocator) !Beta {
        return Beta{
            .recent_history = try self.recent_history.deepClone(allocator),
            .beefy_belt = try self.beefy_belt.deepClone(allocator),
            .allocator = allocator,
        };
    }

    pub fn format(
        self: *const @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Beta{{ recent_history: {} blocks, beefy_belt: {} peaks }}", .{
            self.recent_history.blocks.items.len,
            self.beefy_belt.countPeaks(),
        });
    }
};

/// Recent history component (β_H)
/// Contains header hashes, state roots, and work package references
pub const RecentHistory = struct {
    allocator: Allocator,
    /// The list of recent blocks (without AccOuts)
    blocks: std.ArrayList(BlockInfo),
    /// The maximum number of blocks to keep
    max_blocks: usize,

    /// Block info without accumulation outputs (v0.6.7)
    pub const BlockInfo = struct {
        /// h: The hash of the block header
        header_hash: types.Hash,
        /// b: The BEEFY commitment root (just the root, not full MMR)
        beefy_root: types.Hash,
        /// s: The root hash of the state trie
        state_root: types.Hash,
        /// p: The hashes of work reports included in this block
        work_reports: []types.ReportedWorkPackage,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            allocator.free(self.work_reports);
            self.* = undefined;
        }

        pub fn deepClone(self: *const @This(), allocator: Allocator) !BlockInfo {
            return BlockInfo{
                .header_hash = self.header_hash,
                .beefy_root = self.beefy_root,
                .state_root = self.state_root,
                .work_reports = try allocator.dupe(types.ReportedWorkPackage, self.work_reports),
            };
        }
    };

    pub fn init(allocator: Allocator, max_blocks: usize) !RecentHistory {
        return RecentHistory{
            .allocator = allocator,
            .blocks = try std.ArrayList(BlockInfo).initCapacity(allocator, max_blocks),
            .max_blocks = max_blocks,
        };
    }

    pub fn deinit(self: *RecentHistory) void {
        for (self.blocks.items) |*block| {
            block.deinit(self.allocator);
        }
        self.blocks.deinit();
        self.* = undefined;
    }

    pub fn deepClone(self: *const RecentHistory, allocator: Allocator) !RecentHistory {
        var clone = try RecentHistory.init(allocator, self.max_blocks);
        errdefer clone.deinit();

        for (self.blocks.items) |*block| {
            try clone.blocks.append(try block.deepClone(allocator));
        }

        return clone;
    }

    /// Add a new block to recent history, removing the oldest if at capacity
    pub fn addBlock(self: *RecentHistory, block: BlockInfo) !void {
        if (self.blocks.items.len >= self.max_blocks) {
            // Remove oldest block
            var oldest = self.blocks.orderedRemove(0);
            oldest.deinit(self.allocator);
        }
        try self.blocks.append(block);
    }
};

/// BEEFY Belt component (β_B)
/// Merkle Mountain Range of accumulation outputs
pub const BeefyBelt = struct {
    /// The MMR peaks - sequence of optional hashes
    peaks: []?types.Hash,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !BeefyBelt {
        // Start with empty MMR
        return BeefyBelt{
            .peaks = try allocator.alloc(?types.Hash, 0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BeefyBelt) void {
        self.allocator.free(self.peaks);
        self.* = undefined;
    }

    pub fn deepClone(self: *const BeefyBelt, allocator: Allocator) !BeefyBelt {
        return BeefyBelt{
            .peaks = try allocator.dupe(?types.Hash, self.peaks),
            .allocator = allocator,
        };
    }

    /// Append a new accumulation output root to the MMR
    pub fn append(self: *BeefyBelt, root: types.Hash) !void {
        const new_peaks = try mmr.append(
            self.allocator,
            self.peaks,
            root,
            std.crypto.hash.sha3.Keccak256,
        );
        self.allocator.free(self.peaks);
        self.peaks = new_peaks;
    }

    /// Get the super-peak (root) of the MMR
    pub fn getSuperPeak(self: *const BeefyBelt) types.Hash {
        return mmr.superPeak(self.peaks, std.crypto.hash.sha3.Keccak256);
    }

    /// Count non-null peaks
    pub fn countPeaks(self: *const BeefyBelt) usize {
        var count: usize = 0;
        for (self.peaks) |peak| {
            if (peak != null) count += 1;
        }
        return count;
    }
};

