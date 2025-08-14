const std = @import("std");
const testing = std.testing;

const jam_params = @import("jam_params.zig");
const trace_runner = @import("trace_runner/runner.zig");
const parsers = @import("trace_runner/parsers.zig");
const messages = @import("fuzz_protocol/messages.zig");
const version = @import("version.zig");

// Use FUZZ_PARAMS for consistency with fuzz protocol testing
const FUZZ_PARAMS = messages.FUZZ_PARAMS;

// ============================================================================
// Tests
// ============================================================================

test "jam-conformance:jamzig" {
    const allocator = testing.allocator;
    const jamzig_path = "src/jam-conformance/fuzz-reports/jamzig";

    try runReportsInDirectory(allocator, jamzig_path, "JamZig");
}

test "jam-conformance:archive" {
    const allocator = testing.allocator;
    const archive_path = try buildArchivePath(allocator);
    defer allocator.free(archive_path);

    try runReportsInDirectory(allocator, archive_path, "Archive");
}

test "jam-conformance:archive-summary" {
    const allocator = testing.allocator;
    const archive_path = try buildArchivePath(allocator);
    defer allocator.free(archive_path);

    try runArchiveSummary(allocator, archive_path);
}

// -- Helper Functions --

fn buildArchivePath(allocator: std.mem.Allocator) ![]u8 {
    const graypaper = version.GRAYPAPER_VERSION;
    const version_str = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ graypaper.major, graypaper.minor, graypaper.patch });
    defer allocator.free(version_str);

    return try std.fmt.allocPrint(allocator, "src/jam-conformance/fuzz-reports/archive/{s}", .{version_str});
}

fn runReportsInDirectory(allocator: std.mem.Allocator, base_path: []const u8, name: []const u8) !void {
    const directories = try discoverReportDirectories(allocator, base_path);
    defer {
        for (directories.items) |dir| {
            allocator.free(dir);
        }
        directories.deinit();
    }

    std.log.info("Running {s} conformance tests from: {s}", .{ name, base_path });
    std.log.info("Found {d} report directories", .{directories.items.len});

    if (directories.items.len == 0) {
        std.log.warn("No report directories found in {s}", .{base_path});
        return;
    }

    // Create W3F loader for the traces
    const w3f_loader = parsers.w3f.Loader(FUZZ_PARAMS){};
    const loader = w3f_loader.loader();

    // Run traces in each directory
    for (directories.items, 1..) |dir, idx| {
        std.log.info("[{d}/{d}] Running traces in: {s}", .{ idx, directories.items.len, dir });

        try trace_runner.runTracesInDir(
            FUZZ_PARAMS,
            loader,
            allocator,
            dir,
            .CONTINOUS_MODE,
        );
    }
}

fn runArchiveSummary(allocator: std.mem.Allocator, base_path: []const u8) !void {
    const directories = try discoverReportDirectories(allocator, base_path);
    defer {
        for (directories.items) |dir| {
            allocator.free(dir);
        }
        directories.deinit();
    }

    std.log.info("\n=== Archive Conformance Summary ===", .{});
    std.log.info("Testing archive reports from: {s}", .{base_path});
    std.log.info("Found {d} report directories\n", .{directories.items.len});

    if (directories.items.len == 0) {
        std.log.warn("No report directories found in {s}", .{base_path});
        return;
    }

    // Create W3F loader for the traces
    const w3f_loader = parsers.w3f.Loader(FUZZ_PARAMS){};
    const loader = w3f_loader.loader();

    var passed: usize = 0;
    var failed: usize = 0;

    // Track failures for summary
    var failures = std.ArrayList(struct {
        dir: []const u8,
        err: anyerror,
    }).init(allocator);
    defer failures.deinit();

    // Run traces in each directory and track results
    for (directories.items, 1..) |dir, idx| {
        std.log.info("[{d}/{d}] Testing: {s}", .{ idx, directories.items.len, dir });

        // Try to run traces, catch and record any errors
        trace_runner.runTracesInDir(
            FUZZ_PARAMS,
            loader,
            allocator,
            dir,
            .CONTINOUS_MODE,
        ) catch |err| {
            std.log.err("  ❌ FAILED: {s}", .{@errorName(err)});
            failed += 1;
            try failures.append(.{ .dir = dir, .err = err });
            continue;
        };

        std.log.info("  ✅ PASSED", .{});
        passed += 1;
    }

    // Print summary
    std.log.info("\n=== Results Summary ===", .{});
    std.log.info("Total reports: {d}", .{directories.items.len});
    std.log.info("Passed: {d} ({d:.1}%)", .{ passed, @as(f64, @floatFromInt(passed)) * 100.0 / @as(f64, @floatFromInt(directories.items.len)) });
    std.log.info("Failed: {d} ({d:.1}%)", .{ failed, @as(f64, @floatFromInt(failed)) * 100.0 / @as(f64, @floatFromInt(directories.items.len)) });

    if (failures.items.len > 0) {
        std.log.info("\n=== Failed Reports ===", .{});
        for (failures.items) |failure| {
            // Extract just the report ID from the path
            const last_slash = std.mem.lastIndexOf(u8, failure.dir, "/") orelse 0;
            const report_id = if (last_slash > 0) failure.dir[last_slash + 1 ..] else failure.dir;
            std.log.info("  {s}: {s}", .{ report_id, @errorName(failure.err) });
        }
    }

    std.log.info("\n=== End Summary ===\n", .{});
}

fn discoverReportDirectories(allocator: std.mem.Allocator, base_path: []const u8) !std.ArrayList([]const u8) {
    var directories = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (directories.items) |dir| {
            allocator.free(dir);
        }
        directories.deinit();
    }

    var base_dir = try std.fs.cwd().openDir(base_path, .{ .iterate = true });
    defer base_dir.close();

    var it = base_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .directory) {
            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_path, entry.name });
            try directories.append(full_path);
        }
    }

    return directories;
}
