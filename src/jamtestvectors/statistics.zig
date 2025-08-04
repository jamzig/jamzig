const std = @import("std");
const types = @import("../types.zig");
const validator_stats = @import("../validator_stats.zig");
const jam_params = @import("../jam_params.zig");

const BASE_PATH = "src/jamtestvectors/data/stf/statistics/";

/// ValidatorsStatistics for test vectors
pub const ValidatorsStatistics = struct {
    stats: []validator_stats.ValidatorStats,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.stats);
        self.* = undefined;
    }
};

pub const State = struct {
    // [π_V] Current validators statistics
    vals_curr_stats: ValidatorsStatistics,
    // [π_L] Last validators statistics
    vals_last_stats: ValidatorsStatistics,
    // [τ] Prior timeslot
    slot: types.TimeSlot,
    // [κ'] Posterior active validators
    curr_validators: types.ValidatorSet,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.vals_curr_stats.deinit(allocator);
        self.vals_last_stats.deinit(allocator);
        self.curr_validators.deinit(allocator);
        self.* = undefined;
    }
};

pub const Input = struct {
    // [H_t] Block timeslot
    slot: types.TimeSlot,
    // [H_i] Block author
    author_index: types.ValidatorIndex,
    // [E] Extrinsic
    extrinsic: types.Extrinsic,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.extrinsic.deinit(allocator);
        self.* = undefined;
    }
};

pub const Output = struct {
    pub fn deinit(self: *@This(), _: std.mem.Allocator) void {
        self.* = undefined;
    }
};

pub const TestCase = struct {
    input: Input,
    pre_state: State,
    output: Output,
    post_state: State,

    pub fn buildFrom(
        comptime params: jam_params.Params,
        allocator: std.mem.Allocator,
        bin_file_path: []const u8,
    ) !@This() {
        return try @import("./loader.zig").loadAndDeserializeTestVector(
            TestCase,
            params,
            allocator,
            bin_file_path,
        );
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.input.deinit(allocator);
        self.pre_state.deinit(allocator);
        self.post_state.deinit(allocator);
        self.* = undefined;
    }
};

test "statistics_vector:tiny" {
    const allocator = std.testing.allocator;

    const dir = @import("dir.zig");
    var test_vectors = try dir.scan(
        TestCase,
        jam_params.TINY_PARAMS,
        allocator,
        BASE_PATH ++ "tiny/",
    );
    defer test_vectors.deinit();
}

test "statistics_vector:full" {
    const allocator = std.testing.allocator;

    const dir = @import("dir.zig");
    var test_vectors = try dir.scan(
        TestCase,
        jam_params.FULL_PARAMS,
        allocator,
        BASE_PATH ++ "full/",
    );
    defer test_vectors.deinit();
}