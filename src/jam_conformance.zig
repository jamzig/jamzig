const std = @import("std");
const testing = std.testing;

const jam_params = @import("jam_params.zig");
const trace_runner = @import("trace_runner/runner.zig");
const parsers = @import("trace_runner/parsers.zig");
const messages = @import("fuzz_protocol/messages.zig");
const version = @import("version.zig");

// Use FUZZ_PARAMS for consistency with fuzz protocol testing
const FUZZ_PARAMS = jam_params.TINY_PARAMS;
const RunConfig = trace_runner.RunConfig;

test "jam-conformance:jamzig" {
    const allocator = testing.allocator;
    const jamzig_path = "src/jam-conformance/fuzz-reports/jamzig";

    try runReportsInDirectory(allocator, jamzig_path, "JamZig");
}

test "jam-conformance:archive" {
    const allocator = testing.allocator;

    // Check for environment variable
    const archive_timestamp = std.process.getEnvVarOwned(allocator, "JAM_CONFORMANCE_ARCHIVE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            std.debug.print("Skipping archive test. Set JAM_CONFORMANCE_ARCHIVE=<timestamp> to run a specific archive\n", .{});
            return;
        },
        else => return err,
    };
    defer allocator.free(archive_timestamp);

    // Build path to specific archive directory
    const archive_base = try buildArchivePath(allocator);
    defer allocator.free(archive_base);

    const specific_archive_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ archive_base, archive_timestamp });
    defer allocator.free(specific_archive_path);

    // Check if directory exists
    var dir = std.fs.cwd().openDir(specific_archive_path, .{}) catch |err| {
        std.debug.print("Error: Archive directory not found: {s}\n", .{specific_archive_path});
        return err;
    };
    dir.close();

    std.debug.print("Running archive test for: {s}\n", .{archive_timestamp});

    // Run test for the specific directory only
    const w3f_loader = parsers.w3f.Loader(FUZZ_PARAMS){};
    const loader = w3f_loader.loader();

    try trace_runner.runTracesInDir(
        FUZZ_PARAMS,
        loader,
        allocator,
        specific_archive_path,
        RunConfig{ .mode = .CONTINOUS_MODE, .quiet = false },
    );
}

test "jam-conformance:summary" {
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

    std.debug.print("Running {s} conformance tests from: {s}\n", .{ name, base_path });
    std.debug.print("Found {d} report directories\n", .{directories.items.len});

    if (directories.items.len == 0) {
        std.debug.print("No report directories found in {s}\n", .{base_path});
        return;
    }

    // Create W3F loader for the traces
    const w3f_loader = parsers.w3f.Loader(FUZZ_PARAMS){};
    const loader = w3f_loader.loader();

    // Run traces in each directory
    for (directories.items, 1..) |dir, idx| {
        std.debug.print("[{d}/{d}] Running traces in: {s}\n", .{ idx, directories.items.len, dir });

        try trace_runner.runTracesInDir(
            FUZZ_PARAMS,
            loader,
            allocator,
            dir,
            RunConfig{ .mode = .CONTINOUS_MODE, .quiet = false },
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

    std.debug.print("\n=== Conformance Summary: {s} ===\n", .{base_path});
    std.debug.print("Found {d} report directories\n", .{directories.items.len});

    if (directories.items.len == 0) {
        std.debug.print("No report directories found in {s}\n", .{base_path});
        return;
    }

    // Create W3F loader for the traces
    const w3f_loader = parsers.w3f.Loader(FUZZ_PARAMS){};
    const loader = w3f_loader.loader();

    var passed: usize = 0;
    var failed: usize = 0;

    // Track failures for summary
    var failures = std.ArrayList(struct {
        id: []u8,
        err: anyerror,
    }).init(allocator);
    defer {
        for (failures.items) |failure| {
            allocator.free(failure.id);
        }
        failures.deinit();
    }

    // Run traces in each directory and track results
    for (directories.items, 1..) |dir, idx| {
        // Extract just the report ID from the path
        const last_slash = std.mem.lastIndexOf(u8, dir, "/") orelse 0;
        const report_id = if (last_slash > 0) dir[last_slash + 1 ..] else dir;

        // Try to run traces, catch and record any errors
        trace_runner.runTracesInDir(
            FUZZ_PARAMS,
            loader,
            allocator,
            dir,
            RunConfig{ .mode = .CONTINOUS_MODE, .quiet = true },
        ) catch |err| {
            std.debug.print("[{d:3}/{d:3}] {s}: ❌ {s}\n", .{ idx, directories.items.len, report_id, @errorName(err) });
            failed += 1;
            const id_copy = try allocator.dupe(u8, report_id);
            try failures.append(.{ .id = id_copy, .err = err });
            continue;
        };

        std.debug.print("[{d:3}/{d:3}] {s}: ✅ PASS\n", .{ idx, directories.items.len, report_id });
        passed += 1;
    }

    // Print summary
    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("Total: {d} | Passed: {d} | Failed: {d} | Pass rate: {d:.1}%\n", .{
        directories.items.len,
        passed,
        failed,
        @as(f64, @floatFromInt(passed)) * 100.0 / @as(f64, @floatFromInt(directories.items.len)),
    });

    // List failed cases
    if (failures.items.len > 0) {
        std.debug.print("\nFailed cases:\n", .{});
        for (failures.items) |failure| {
            std.debug.print("  - {s}: {s}\n", .{ failure.id, @errorName(failure.err) });
        }
    }
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
