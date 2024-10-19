// The Pi component for tracking validator statistics across epochs, following
// the specification from the graypaper. The Pi component is responsible for
// maintaining six key metrics for each validator:
//
//   1. Blocks Produced (b): The number of blocks produced by the validator.
//   2. Tickets Introduced (t): The number of validator tickets introduced.
//   3. Preimages Introduced (p): The number of preimages introduced by the validator.
//   4. Octets Across Preimages (d): The total number of octets across all preimages introduced.
//   5. Reports Guaranteed (g): The number of reports guaranteed by the validator.
//   6. Availability Assurances (a): The number of assurances made by the validator about data availability.
//
const std = @import("std");

const ValidatorIndex = @import("types.zig").ValidatorIndex; // Identifier for each validator

// ValidatorStats tracks the six key metrics as described in the graypaper
const ValidatorStats = struct {
    blocks_produced: u32, // b: Number of blocks produced
    tickets_introduced: u32, // t: Number of validator tickets introduced
    preimages_introduced: u32, // p: Number of preimages introduced
    octets_across_preimages: u32, // d: Total number of octets across preimages
    reports_guaranteed: u32, // g: Number of reports guaranteed
    availability_assurances: u32, // a: Number of availability assurances

    /// Initialize a new ValidatorStats with all metrics set to zero
    pub fn init() ValidatorStats {
        return ValidatorStats{
            .blocks_produced = 0,
            .tickets_introduced = 0,
            .preimages_introduced = 0,
            .octets_across_preimages = 0,
            .reports_guaranteed = 0,
            .availability_assurances = 0,
        };
    }

    /// Increment blocks produced count
    pub fn update_blocks_produced(self: *ValidatorStats, count: u32) void {
        self.blocks_produced += count;
    }

    /// Increment tickets introduced count
    pub fn update_tickets_introduced(self: *ValidatorStats, count: u32) void {
        self.tickets_introduced += count;
    }

    /// Increment preimages introduced count
    pub fn update_preimages_introduced(self: *ValidatorStats, count: u32) void {
        self.preimages_introduced += count;
    }

    /// Increment octets across preimages count
    pub fn update_octets_across_preimages(self: *ValidatorStats, count: u32) void {
        self.octets_across_preimages += count;
    }

    /// Increment reports guaranteed count
    pub fn update_reports_guaranteed(self: *ValidatorStats, count: u32) void {
        self.reports_guaranteed += count;
    }

    /// Increment availability assurances count
    pub fn update_availability_assurances(self: *ValidatorStats, count: u32) void {
        self.availability_assurances += count;
    }
};

// PiComponent holds the stats for all validators across two epochs
const Pi = struct {
    currentEpochStats: std.ArrayHashMap(ValidatorIndex, ValidatorStats), // Stats for the current epoch
    previousEpochStats: std.ArrayHashMap(ValidatorIndex, ValidatorStats), // Stats for the previous epoch
    allocator: *std.mem.Allocator,

    /// Initialize a new Pi component with empty stats for current and previous epochs
    pub fn init(allocator: *std.mem.Allocator) Pi {
        return Pi{
            .currentEpochStats = std.ArrayHashMap(ValidatorIndex, ValidatorStats).init(allocator),
            .previousEpochStats = std.ArrayHashMap(ValidatorIndex, ValidatorStats).init(allocator),
            .allocator = allocator,
        };
    }

    /// Get or create ValidatorStats for a given validator ID
    pub fn ensureValidator(self: *Pi, id: ValidatorIndex) !*ValidatorStats {
        const result = try self.currentEpochStats.getOrPut(id);
        if (!result.found_existing) {
            result.value_ptr.* = ValidatorStats.init();
        }
        return result.value_ptr;
    }

    /// Move current epoch stats to previous epoch and reset current stats
    pub fn transitionToNextEpoch(self: *Pi) !void {
        self.previousEpochStats = self.currentEpochStats;
        self.currentEpochStats = std.ArrayHashMap(ValidatorIndex, ValidatorStats).init(self.allocator);
    }

    /// Clean up allocated resources
    pub fn deinit(self: *Pi) void {
        self.currentEpochStats.deinit();
        self.previousEpochStats.deinit();
    }
};
