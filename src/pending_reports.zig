/// Rho (ρ) State Implementation
///
/// This file implements the rho (ρ) state for the Jam protocol. Rho is a critical
/// component of the reporting and availability system in Jam.
///
/// Purpose:
/// - Rho tracks work-reports that have been reported but are not yet known to be
///   available to a super-majority of validators.
/// - It maintains a mapping of cores to their currently assigned work-reports and
///   the time at which each report was made.
///
/// Key characteristics:
/// - There are C (341) cores, each capable of having one assigned work-report.
/// - Only one report may be assigned to a core at any given time.
/// - Each entry in rho contains a work-report and its reporting timeslot.
/// - Rho is used in the block production process to manage the lifecycle of
///   work-reports from reporting to availability confirmation.
///
/// This implementation provides functionality to:
/// - Initialize the rho state
/// - Set a work-report for a specific core
/// - Retrieve a work-report for a specific core
/// - Clear a work-report from a specific core
const std = @import("std");

const types = @import("types.zig");
const WorkReport = types.WorkReport;
const TimeSlot = types.TimeSlot;
const OpaqueHash = types.OpaqueHash;
const WorkReportHash = types.WorkReportHash;
const RefineContext = types.RefineContext;
const WorkPackageSpec = types.WorkPackageSpec;
const CoreIndex = types.CoreIndex;

pub const RhoEntry = struct {
    assignment: types.AvailabilityAssignment,
    cached_hash: ?WorkReportHash,

    pub fn init(assignment: types.AvailabilityAssignment) @This() {
        return .{
            .assignment = assignment,
            .cached_hash = null,
        };
    }

    pub fn hash(self: *@This(), allocator: std.mem.Allocator) !WorkReportHash {
        if (self.cached_hash == null) {
            self.cached_hash = try self.assignment.report.hash(allocator);
        }
        return self.cached_hash.?;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.assignment.report.deinit(allocator);
    }
};

// Rho state
pub fn Rho(comptime core_count: u16) type {
    return struct {
        reports: [core_count]?RhoEntry,
        allocator: std.mem.Allocator,

        pub fn format(
            self: *const @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try @import("state_format/rho.zig").format(core_count, self, fmt, options, writer);
        }

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .reports = [_]?RhoEntry{null} ** core_count,
                .allocator = allocator,
            };
        }

        pub fn setReport(self: *@This(), core: usize, assignment: types.AvailabilityAssignment) void {
            if (core >= core_count) {
                @panic("Core index out of bounds");
            }
            self.reports[core] = RhoEntry.init(assignment);
        }

        pub fn getReport(self: *const @This(), core: usize) ?types.AvailabilityAssignment {
            if (core >= core_count) {
                @panic("Core index out of bounds");
            }
            return if (self.reports[core]) |entry| entry.assignment else null;
        }

        pub fn clearReport(self: *@This(), core: usize) void {
            if (core >= core_count) {
                @panic("Core index out of bounds");
            }
            self.reports[core] = null;
        }

        pub fn clearFromCore(self: *@This(), work_report_hash: WorkReportHash) !bool {
            for (&self.reports) |*report| {
                if (report.*) |*entry| {
                    const hash = try entry.hash(self.allocator);
                    if (std.mem.eql(u8, &hash, &work_report_hash)) {
                        entry.deinit(self.allocator);
                        report.* = null;
                        return true;
                    }
                }
            }
            return false;
        }

        pub fn deinit(self: *@This()) void {
            for (&self.reports) |*report| {
                if (report.*) |*entry| {
                    entry.deinit(self.allocator);
                }
            }
        }
    };
}

//  _____         _
// |_   _|__  ___| |_ ___
//   | |/ _ \/ __| __/ __|
//   | |  __/\__ \ |_\__ \
//   |_|\___||___/\__|___/
//

const testing = std.testing;

const createEmptyWorkReport = @import("tests/fixtures.zig").createEmptyWorkReport;

const TEST_C: u16 = 341; // Standard number of cores for testing
const TEST_HASH = [_]u8{ 'T', 'E', 'S', 'T' } ++ [_]u8{0} ** 28;

test "Rho - Initialization" {
    var rho = Rho(TEST_C).init();
    defer rho.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, TEST_C), rho.reports.len);
    for (rho.reports) |report| {
        try testing.expectEqual(@as(?RhoEntry, null), report);
    }
}

test "Rho - Set and Get Report" {
    var rho = Rho(TEST_C).init();
    defer rho.deinit(testing.allocator);

    const work_report = createEmptyWorkReport(TEST_HASH);
    const timeslot = 100;

    // Test setting a report
    const assignment = types.AvailabilityAssignment{
        .report = work_report,
        .timeout = timeslot,
    };
    rho.setReport(0, assignment);
    const report = rho.getReport(0);
    try testing.expect(report != null);
    if (report) |r| {
        try testing.expectEqual(r.report.package_spec.hash, TEST_HASH);
        try testing.expectEqual(r.timeout, 100);
    }

    // Test getting a non-existent report
    const empty_report = rho.getReport(1);
    try testing.expectEqual(@as(?types.AvailabilityAssignment, null), empty_report);
}

test "Rho - Clear Report" {
    var rho = Rho(TEST_C).init();
    defer rho.deinit(testing.allocator);

    const work_report = createEmptyWorkReport(TEST_HASH);
    const timeslot = 100;

    // Set a report
    const assignment = types.AvailabilityAssignment{
        .report = work_report,
        .timeout = timeslot,
    };
    rho.setReport(0, assignment);
    try testing.expect(rho.getReport(0) != null);

    // Clear the report
    rho.clearReport(0);
    try testing.expectEqual(@as(?types.AvailabilityAssignment, null), rho.getReport(0));
}

test "Rho - Clear From Core" {
    var rho = Rho(TEST_C).init();
    defer rho.deinit(testing.allocator);

    const work_report1 = createEmptyWorkReport(TEST_HASH);
    const test_hash2 = [_]u8{ 'T', 'E', 'S', 'T', '2' } ++ [_]u8{0} ** 27;
    const work_report2 = createEmptyWorkReport(test_hash2);
    const timeslot = 100;

    // Set reports
    const assignment1 = types.AvailabilityAssignment{
        .report = work_report1,
        .timeout = timeslot,
    };
    const assignment2 = types.AvailabilityAssignment{
        .report = work_report2,
        .timeout = timeslot,
    };
    rho.setReport(0, assignment1);
    rho.setReport(1, assignment2);
    try testing.expect(rho.getReport(0) != null);
    try testing.expect(rho.getReport(1) != null);

    // Clear report with TEST_HASH
    const cleared = try rho.clearFromCore(testing.allocator, TEST_HASH);
    try testing.expect(cleared);

    // Check that the first report is cleared and the second is still present
    try testing.expectEqual(@as(?types.AvailabilityAssignment, null), rho.getReport(0));
    try testing.expect(rho.getReport(1) != null);
    if (rho.getReport(1)) |report| {
        const hash = try report.hash(testing.allocator);
        try testing.expectEqualSlices(u8, &hash, &test_hash2);
    }
}

test "RhoEntry - Lazy Hash Calculation" {
    const work_report = createEmptyWorkReport(TEST_HASH);
    const timeslot = 100;
    const assignment = types.AvailabilityAssignment{
        .report = work_report,
        .timeout = timeslot,
    };

    var entry = RhoEntry.init(assignment);
    defer entry.deinit(testing.allocator);

    // Initially the hash should be null
    try testing.expect(entry.cached_hash == null);

    // Calculate hash
    const hash1 = try entry.hash(testing.allocator);
    try testing.expectEqualSlices(u8, &hash1, &TEST_HASH);

    // Hash should now be cached
    try testing.expect(entry.cached_hash != null);

    // Second calculation should use cached value
    const hash2 = try entry.hash(testing.allocator);
    try testing.expectEqualSlices(u8, &hash1, &hash2);
}
