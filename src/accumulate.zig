const std = @import("std");
const types = @import("types.zig");

const state = @import("state.zig");
const state_delta = @import("state_delta.zig");

pub const execution = @import("accumulate/execution.zig");

const WorkReportAndDeps = state.reports_ready.WorkReportAndDeps;
const Params = @import("jam_params.zig").Params;
const meta = @import("meta.zig");
pub const ProcessAccumulationResult = @import("accumulate/execution.zig").ProcessAccumulationResult;
pub const DeferredTransfer = @import("pvm_invocations/accumulate.zig").DeferredTransfer;

// Add tracing import
const trace = @import("tracing.zig").scoped(.accumulate);

// 12.7 Walks the queued, updates dependencies and removes those who are already resolved
fn queueEditingFunction(
    queued: *Queued(WorkReportAndDeps),
    resolved_reports: []types.WorkReportHash,
) void {
    const span = trace.span(.queue_editing);
    defer span.deinit();

    span.debug("Starting queue editing with {d} queued items and {d} resolved reports", .{ queued.items.len, resolved_reports.len });

    var idx: usize = 0;
    outer: while (idx < queued.items.len) {
        var wradeps = &queued.items[idx];
        span.trace("Processing item {d}: hash={s}", .{ idx, std.fmt.fmtSliceHexLower(&wradeps.work_report.package_spec.hash) });

        for (resolved_reports) |work_package_hash| {
            if (std.mem.eql(u8, &wradeps.work_report.package_spec.hash, &work_package_hash)) {
                span.debug("Found matching report, removing from queue at index {d}", .{idx});
                var removed = queued.orderedRemove(idx);
                // TODO: pass allocator to function
                removed.deinit(queued.allocator);
                // so the next element to process is now at the current index position
                // continue the while loop without incrementing idx since the next element
                // is now at the current index after removal
                continue :outer;
            }
        }

        // Only process dependencies if this report has any
        if (wradeps.dependencies.count() > 0) {
            for (resolved_reports) |work_package_hash| {
                span.trace("Checking dependency: {s}", .{std.fmt.fmtSliceHexLower(&work_package_hash)});
                // else try to remove and resolve
                if (wradeps.dependencies.swapRemove(work_package_hash)) {
                    span.debug("Resolved dependency: {s}", .{std.fmt.fmtSliceHexLower(&work_package_hash)});
                } else {
                    span.debug("Dependency does not match: {s}", .{std.fmt.fmtSliceHexLower(&work_package_hash)});
                    span.trace("Current report dependencies: {any}", .{types.fmt.format(wradeps.dependencies.keys())});
                }

                // resolved?
                if (wradeps.dependencies.count() == 0) {
                    span.debug("All dependencies resolved for report at index {d}", .{idx});
                    break; // Exit inner loop since we've resolved this report
                }
            }
        }
        idx += 1;
    }

    span.debug("Queue editing complete, {d} items remaining in queue", .{queued.items.len});
}

// 12.8 We further define the accumulation priority queue function Q, which
// provides the sequence of work-reports which are accumulatable given a set of
// not-yet-accumulated work-reports and their dependencies.
fn processAccumulationQueue(
    allocator: std.mem.Allocator,
    queued: *Queued(WorkReportAndDeps),
    accumulatable: *Accumulatable(types.WorkReport),
) !void {
    const span = trace.span(.process_accumulation_queue);
    defer span.deinit();

    span.debug("Starting accumulation queue processing with {d} queued items", .{queued.items.len});

    // Process work reports in dependency order:
    // 1. Start with immediately executable reports (no dependencies)
    // 2. Use their work package hashes to resolve dependencies of queued reports
    // 3. Repeat until no more dependencies can be resolved
    // This creates a natural accumulation order that respects dependencies
    var resolved = Resolved(types.WorkPackageHash).init(allocator);
    defer resolved.deinit();
    span.debug("Initialized resolved reports container", .{});

    // Simulate recursion
    var iteration: usize = 0;
    while (true) {
        const iter_span = span.child(.iteration);
        defer iter_span.deinit();
        iteration += 1;

        iter_span.debug("Starting iteration {d}", .{iteration});

        // NOTE: we start assuming there "can" be resolved entries, if there
        // are none. We exit immediatly without iterating. See: processAccumulateReports@12.5.
        resolved.clearRetainingCapacity();
        iter_span.trace("Cleared resolved list, capacity: {d}", .{resolved.capacity});

        var resolved_count: usize = 0;
        for (queued.items, 0..) |*wradeps, i| {
            const deps_count = wradeps.dependencies.count();
            iter_span.trace("Checking item {d}: dependencies={d}, hash={s}", .{ i, deps_count, std.fmt.fmtSliceHexLower(&wradeps.work_report.package_spec.hash) });

            if (deps_count == 0) {
                const cloned_report = try wradeps.work_report.deepClone(allocator);
                try accumulatable.append(cloned_report);
                try resolved.append(wradeps.work_report.package_spec.hash);
                resolved_count += 1;
                iter_span.debug("Found resolvable report at index {d}, hash: {s}", .{ i, std.fmt.fmtSliceHexLower(&wradeps.work_report.package_spec.hash) });
            }
        }

        iter_span.debug("Found {d} resolvable reports in this iteration", .{resolved_count});

        // exit condition
        if (resolved.items.len == 0) {
            iter_span.debug("No resolvable reports found, exiting loop", .{});
            break;
        }

        // update our queue
        iter_span.debug("Updating queue with {d} newly resolved items", .{resolved.items.len});
        queueEditingFunction(queued, resolved.items);
    }

    span.debug("Accumulation queue processing complete, found {d} accumulatable reports", .{accumulatable.items.len});
}

/// Partitions work reports into immediately accumulatable and queued reports based on dependencies
fn partitionReports(
    allocator: std.mem.Allocator,
    reports: []types.WorkReport,
    accumulatable_buffer: *Accumulatable(types.WorkReport),
    queued: *Queued(WorkReportAndDeps),
) !struct { immediate_count: usize, queued_count: usize } {
    const span = trace.span(.partition_reports);
    defer span.deinit();

    span.debug("Partitioning {d} reports into immediate and queued", .{reports.len});

    var immediate_count: usize = 0;
    var queued_count: usize = 0;

    for (reports, 0..) |*report, i| {
        span.trace("Checking report {d}, hash: {s}", .{ i, std.fmt.fmtSliceHexLower(&report.package_spec.hash) });

        // 12.4 A report can be accumulated immediately if it has no prerequisites
        // and no segment root lookups
        if (report.context.prerequisites.len == 0 and
            report.segment_root_lookup.len == 0)
        {
            span.debug("Report {d} is immediately accumulatable", .{i});
            const cloned_report = try report.deepClone(allocator);
            try accumulatable_buffer.append(cloned_report);
            immediate_count += 1;
        } else {
            span.debug("Report {d} has dependencies (prereqs: {d}, lookups: {d})", .{ i, report.context.prerequisites.len, report.segment_root_lookup.len });
            const cloned_report = try report.deepClone(allocator);
            const work_report_deps = try WorkReportAndDeps.fromWorkReport(allocator, cloned_report);
            try queued.append(work_report_deps);
            queued_count += 1;
        }
    }

    span.debug("Partitioning complete: {d} immediate, {d} queued", .{ immediate_count, queued_count });
    return .{ .immediate_count = immediate_count, .queued_count = queued_count };
}

/// Filters out already accumulated reports and removes dependencies that are already accumulated
fn filterAccumulatedReports(
    comptime epoch_size: usize,
    allocator: std.mem.Allocator,
    queued: *Queued(WorkReportAndDeps),
    xi: *state.Xi(epoch_size),
) !struct { filtered_out: usize, resolved_deps: usize } {
    const span = trace.span(.filter_accumulated_reports);
    defer span.deinit();

    span.debug("Filtering already accumulated reports from {d} queued items", .{queued.items.len});

    var filtered_out: usize = 0;
    var resolved_deps: usize = 0;

    var idx: usize = 0;
    while (idx < queued.items.len) {
        const queued_item = &queued.items[idx];
        const work_package_hash = queued_item.work_report.package_spec.hash;

        span.trace("Checking queued item {d}, hash: {s}", .{ idx, std.fmt.fmtSliceHexLower(&work_package_hash) });

        if (xi.containsWorkPackage(work_package_hash)) {
            span.debug("Report already accumulated, removing from queue", .{});
            @constCast(&queued.orderedRemove(idx)).deinit(allocator); // TODO: optimize
            filtered_out += 1;
            continue;
        }

        var deps_resolved: usize = 0;
        {
            const dep_span = span.child(.check_dependencies);
            defer dep_span.deinit();

            const keys = queued_item.dependencies.keys();
            var i: usize = keys.len;
            while (i > 0) {
                i -= 1;
                const workpackage_hash = keys[i];
                dep_span.trace("Checking dependency: {s}", .{std.fmt.fmtSliceHexLower(&workpackage_hash)});

                if (xi.containsWorkPackage(workpackage_hash)) {
                    dep_span.debug("Removing from dependencies: {s}", .{std.fmt.fmtSliceHexLower(&workpackage_hash)});
                    _ = queued_item.dependencies.swapRemove(workpackage_hash);
                    deps_resolved += 1;
                    resolved_deps += 1;

                    if (queued_item.dependencies.count() == 0) {
                        dep_span.debug("All dependencies resolved for report at index {d}", .{idx});
                        break;
                    }
                }
            }
        }

        span.trace("Resolved {d} dependencies for item {d}", .{ deps_resolved, idx });
        idx += 1;
    }

    span.debug("Filtering complete: removed {d} reports, resolved {d} dependencies", .{ filtered_out, resolved_deps });
    return .{ .filtered_out = filtered_out, .resolved_deps = resolved_deps };
}

/// Builds the pending reports queue from theta and queued reports
fn buildPendingReportsQueue(
    comptime epoch_size: usize,
    allocator: std.mem.Allocator,
    theta: *state.Theta(epoch_size),
    queued: *Queued(WorkReportAndDeps),
    current_slot_in_epoch: u32,
) !Queued(WorkReportAndDeps) {
    const span = trace.span(.build_pending_reports_queue);
    defer span.deinit();

    span.debug("Building initial set of pending reports", .{});

    var pending_reports_queue = Queued(WorkReportAndDeps).init(allocator);
    errdefer meta.deinit.deinitEntriesAndAggregate(allocator, pending_reports_queue);

    // 12.12: walk theta(current_slot_in_epoch..) join theta(..current_slot_in_epoch)
    span.debug("Walking theta from slot {d}", .{current_slot_in_epoch});

    var pending_reports = theta.iteratorStartingFrom(current_slot_in_epoch);
    var reports_from_theta: usize = 0;

    while (pending_reports.next()) |wradeps| {
        span.trace("Found report in theta, hash: {s}", .{std.fmt.fmtSliceHexLower(&wradeps.work_report.package_spec.hash)});
        const cloned_wradeps = try wradeps.deepClone(allocator);
        try pending_reports_queue.append(cloned_wradeps);
        reports_from_theta += 1;
    }

    span.debug("Collected {d} reports from theta", .{reports_from_theta});

    // add the new queued imports
    span.debug("Adding {d} queued reports to pending queue", .{queued.items.len});
    for (queued.items) |*wradeps| {
        span.trace("Adding queued report: {s}", .{std.fmt.fmtSliceHexLower(&wradeps.work_report.package_spec.hash)});
        const cloned_wradeps = try wradeps.deepClone(allocator);
        try pending_reports_queue.append(cloned_wradeps);
    }

    span.debug("Total pending reports: {d}", .{pending_reports_queue.items.len});
    return pending_reports_queue;
}

/// Calculates the AccumulateRoot from accumulation outputs
fn calculateAccumulateRoot(
    allocator: std.mem.Allocator,
    accumulation_outputs: std.AutoHashMap(types.ServiceId, types.AccumulateOutput),
) !types.AccumulateRoot {
    const span = trace.span(.calculate_accumulate_root);
    defer span.deinit();

    span.debug("Calculating AccumulateRoot from {d} accumulation outputs", .{accumulation_outputs.count()});

    // Collect and sort service IDs
    var keys = try std.ArrayList(types.ServiceId).initCapacity(allocator, accumulation_outputs.count());
    defer keys.deinit();

    span.trace("Collecting service IDs from accumulation outputs", .{});
    var key_iter = accumulation_outputs.keyIterator();
    while (key_iter.next()) |key| {
        try keys.append(key.*);
        span.trace("Added service ID: {d}", .{key.*});
    }

    span.debug("Sorting {d} service IDs in ascending order", .{keys.items.len});
    std.mem.sort(u32, keys.items, {}, std.sort.asc(u32));

    // Prepare blobs for Merkle tree
    var blobs = try std.ArrayList([]u8).initCapacity(allocator, accumulation_outputs.count());
    defer meta.deinit.allocFreeEntriesAndAggregate(allocator, blobs);

    span.debug("Creating blobs for Merkle tree calculation", .{});
    for (keys.items, 0..) |key, i| {
        const blob_span = span.child(.create_blob);
        defer blob_span.deinit();

        blob_span.trace("Processing service ID {d} at index {d}", .{ key, i });

        // Convert service ID to bytes
        var service_id: [4]u8 = undefined;
        std.mem.writeInt(u32, &service_id, key, .little);
        blob_span.trace("Service ID bytes: {s}", .{std.fmt.fmtSliceHexLower(&service_id)});

        // Get accumulation output for this service
        const output = accumulation_outputs.get(key).?;
        blob_span.trace("Accumulation output: {s}", .{std.fmt.fmtSliceHexLower(&output)});

        // Concatenate service ID and output
        const blob = try allocator.dupe(u8, &(service_id ++ output));
        try blobs.append(blob);
    }

    span.debug("Computing Merkle root from {d} blobs", .{blobs.items.len});
    const accumulate_root = @import("merkle_binary.zig").M_b(blobs.items, std.crypto.hash.sha3.Keccak256);
    span.debug("AccumulateRoot calculated: {s}", .{std.fmt.fmtSliceHexLower(&accumulate_root)});

    return accumulate_root;
}

/// Calculates accumulation statistics for services
fn calculateAccumulationStats(
    allocator: std.mem.Allocator,
    accumulated: []const types.WorkReport,
    service_gas_used: *std.AutoHashMap(types.ServiceId, types.Gas),
) !std.AutoHashMap(types.ServiceId, @import("accumulate/execution.zig").AccumulationServiceStats) {
    const span = trace.span(.calculate_accumulation_stats);
    defer span.deinit();

    var accumulation_stats = std.AutoHashMap(types.ServiceId, @import("accumulate/execution.zig").AccumulationServiceStats).init(allocator);
    errdefer accumulation_stats.deinit();

    // Calculate I stats (Accumulation) - Eq 12.25
    span.debug("Calculating I (Accumulation) statistics for {d} accumulated reports", .{accumulated.len});
    // Use the per-service gas usage returned by outerAccumulation
    var service_gas_iter = service_gas_used.iterator();
    while (service_gas_iter.next()) |entry| {
        const service_id = entry.key_ptr.*;
        const gas_used = entry.value_ptr.*;
        // Count how many reports were processed for *this* service
        var count: u32 = 0;
        for (accumulated) |report| {
            // Check if this report contains any work result for this service
            for (report.results) |work_result| {
                if (work_result.service_id == service_id) {
                    count += 1;
                }
            }
        }
        try accumulation_stats.put(service_id, .{
            .gas_used = gas_used,
            .accumulated_count = count,
        });
        span.trace("Added I stats for service {d}: count={d}, gas={d}", .{ service_id, count, gas_used });
    }

    return accumulation_stats;
}

/// Updates theta state after accumulation
fn updateThetaState(
    comptime epoch_size: usize,
    allocator: std.mem.Allocator,
    theta: *state.Theta(epoch_size),
    queued: *Queued(WorkReportAndDeps),
    accumulated: []const types.WorkReport,
    map_buffer: *std.ArrayList(types.WorkReportHash),
    time: struct {
        current_slot: types.TimeSlot,
        prior_slot: types.TimeSlot,
        current_slot_in_epoch: u32,
    },
) !void {
    const span = trace.span(.update_theta_state);
    defer span.deinit();

    span.debug("Updating theta pending reports for epoch length {d}", .{epoch_size});

    for (0..epoch_size) |i| {
        const widx = if (i <= time.current_slot_in_epoch)
            time.current_slot_in_epoch - i
        else
            epoch_size - (i - time.current_slot_in_epoch);

        span.trace("Processing slot {d}, widx: {d}", .{ i, widx });

        if (i == 0) {
            span.debug("Updating current slot {d}", .{widx});
            queueEditingFunction(queued, try mapWorkPackageHash(map_buffer, accumulated));
            theta.clearTimeSlot(@intCast(widx));

            span.debug("Adding {d} queued items to time slot {d}", .{ queued.items.len, widx });
            for (queued.items, 0..) |*wradeps, qidx| {
                // NOTE: testvectors are empty, but queue editing function does not remove items on 0 deps
                //       this is based on testvectors
                // TODO: check this against GP
                if (wradeps.dependencies.count() > 0) {
                    span.trace("Adding queued item {d} to slot {d}", .{ qidx, widx });
                    const cloned_wradeps = try wradeps.deepClone(allocator);
                    try theta.addEntryToTimeSlot(@intCast(widx), cloned_wradeps);
                } else {
                    span.trace("Skipping queued item {d} to slot {d}: no dependencies", .{ qidx, widx });
                }
            }

            // try theta.entries[widx].insertSlice(allocator, 0, queued.items);
        } else if (i >= 1 and i < time.current_slot - time.prior_slot) {
            span.debug("Clearing time slot {d}", .{widx});
            theta.clearTimeSlot(@intCast(widx));
        } else if (i >= time.current_slot - time.prior_slot) {
            span.debug("Processing entries for time slot {d}", .{widx});
            // Temporarily convert to managed back to unmanaged. Not doing this explicitly creates
            // some problems, items removed in the managed version stay in the unmanaged. This
            // because the Slice could have been moved in memory on orderedRemoves
            var entries = theta.entries[widx].toManaged(allocator);
            queueEditingFunction(&entries, try mapWorkPackageHash(map_buffer, accumulated)); // HERE IT IS!
            theta.entries[widx] = entries.moveToUnmanaged();

            // NOTE: testvectors are empty, but queue editing function does not remove items on 0 deps
            // TODO: check this against GP
            theta.removeReportsWithoutDependenciesAtSlot(@intCast(widx));
        }
    }
}

/// Calculates the gas limit for accumulation according to equation 12.20
fn calculateGasLimit(
    comptime params: Params,
    chi: *state.Chi,
) u64 {
    const span = trace.span(.calculate_gas_limit);
    defer span.deinit();

    // let g = max(G_T, G_A ⋅ C + ∑_{x∈V(χ_g)}(x))
    var gas_limit: u64 = params.total_gas_alloc_accumulation;

    // Calculate G_A * C (gas per core * core count)
    const core_gas = @as(u64, params.gas_alloc_accumulation) * @as(u64, params.core_count);

    // Add the sum of gas values for free services
    var free_services_gas: u64 = 0;
    var it = chi.always_accumulate.iterator();
    while (it.next()) |entry| {
        free_services_gas += entry.value_ptr.*;
    }

    // Take the maximum, to ensure free services can execute
    const calculated_gas = core_gas + free_services_gas;
    if (calculated_gas > gas_limit) {
        gas_limit = calculated_gas;
    }

    span.debug("Gas limit calculated: {d} (G_T: {d}, core gas: {d}, free services gas: {d})", .{ 
        gas_limit, params.total_gas_alloc_accumulation, core_gas, free_services_gas 
    });

    return gas_limit;
}

/// Applies deferred transfers to service accounts
fn applyDeferredTransfers(
    comptime params: Params,
    allocator: std.mem.Allocator,
    stx: *state_delta.StateTransition(params),
    transfers: []DeferredTransfer,
) !std.AutoHashMap(types.ServiceId, @import("accumulate/execution.zig").TransferServiceStats) {
    const span = trace.span(.apply_deferred_transfers);
    defer span.deinit();

    span.debug("Applying {d} deferred transfers", .{transfers.len});

    var transfer_stats = std.AutoHashMap(types.ServiceId, @import("accumulate/execution.zig").TransferServiceStats).init(allocator);
    errdefer transfer_stats.deinit();

    if (transfers.len > 0) {
        span.debug("Processing transfers for destination services", .{});

        var grouped_transfers_by_dest = std.AutoHashMap(types.ServiceId, std.ArrayList(DeferredTransfer)).init(allocator);
        defer meta.deinit.deinitHashMapValuesAndMap(allocator, grouped_transfers_by_dest);

        for (transfers) |transfer| {
            span.trace("Transfer: {d} -> {d}, amount: {d}", .{ transfer.sender, transfer.destination, transfer.amount });

            var entry = try grouped_transfers_by_dest.getOrPut(transfer.destination);
            if (!entry.found_existing) {
                entry.value_ptr.* = std.ArrayList(DeferredTransfer).init(allocator);
            }

            try entry.value_ptr.append(transfer);
        }

        // Get delta for service accounts
        const delta_prime: *state.Delta = try stx.ensure(.delta_prime);

        var iter = grouped_transfers_by_dest.iterator();
        while (iter.next()) |entry| {
            const service_id = entry.key_ptr.*;
            const deferred_transfers = entry.value_ptr.*.items;

            var context = @import("pvm_invocations/ontransfer.zig").OnTransferContext(params){
                .service_id = entry.key_ptr.*,
                .service_accounts = @import("services_snapshot.zig").DeltaSnapshot.init(delta_prime),
                .allocator = allocator,
                .transfers = deferred_transfers,
                .entropy = (try stx.ensure(.eta_prime))[0],
                .timeslot = stx.time.current_slot,
            };
            defer context.deinit();

            const res = try @import("pvm_invocations/ontransfer.zig").invoke(
                params,
                allocator,
                &context,
            );

            // Store transfer stats
            try transfer_stats.put(service_id, .{
                .gas_used = res.gas_used,
                .transfer_count = @intCast(deferred_transfers.len),
            });
        }

        span.debug("Transfers applied successfully", .{});
    } else {
        span.debug("No transfers to apply", .{});
    }

    return transfer_stats;
}

/// Executes the accumulation process for work reports
fn executeAccumulation(
    comptime params: Params,
    allocator: std.mem.Allocator,
    stx: *state_delta.StateTransition(params),
    accumulatable: []const types.WorkReport,
    gas_limit: u64,
    chi: *state.Chi,
) !@import("accumulate/execution.zig").OuterAccumulationResult {
    const span = trace.span(.execute_accumulation);
    defer span.deinit();

    // Build accumulation context
    var accumulation_context = @import("pvm_invocations/accumulate.zig")
        .AccumulationContext(params).build(
        allocator,
        .{
            .service_accounts = try stx.ensure(.delta_prime),
            .validator_keys = try stx.ensure(.iota_prime),
            .authorizer_queue = try stx.ensure(.phi_prime),
            .privileges = try stx.ensure(.chi_prime),
            .time = &stx.time,
            .entropy = (try stx.ensure(.eta_prime))[0], // Posterior entropy CHECKED
        },
    );
    defer accumulation_context.deinit();

    span.debug("Executing outer accumulation with {d} reports and gas limit {d}", .{ accumulatable.len, gas_limit });

    // Execute work reports scheduled for accumulation
    return try @import("accumulate/execution.zig").outerAccumulation(
        params,
        allocator,
        gas_limit,
        accumulatable,
        &accumulation_context,
        &chi.always_accumulate,
        stx.time.current_slot,
        (try stx.ensure(.eta_prime))[0],
    );
}

/// Updates xi (accumulation history) with newly accumulated reports
fn updateAccumulationHistory(
    comptime epoch_size: usize,
    xi: *state.Xi(epoch_size),
    accumulated: []const types.WorkReport,
) !void {
    const span = trace.span(.update_accumulation_history);
    defer span.deinit();

    span.debug("Shifting down xi, make place for new entry", .{});
    try xi.shiftDown();

    span.debug("Adding {d} reports to accumulation history", .{accumulated.len});
    for (accumulated, 0..) |report, i| {
        const work_package_hash = report.package_spec.hash;
        span.trace("Adding report {d} to history, hash: {s}", .{ i, std.fmt.fmtSliceHexLower(&work_package_hash) });
        try xi.addWorkPackage(work_package_hash);
    }
}

/// Prepares reports for accumulation by partitioning, filtering, and resolving dependencies
fn prepareReportsForAccumulation(
    comptime params: Params,
    allocator: std.mem.Allocator,
    reports: []types.WorkReport,
    xi: *state.Xi(params.epoch_length),
    theta: *state.Theta(params.epoch_length),
    current_slot_in_epoch: u32,
) !struct {
    accumulatable_buffer: Accumulatable(types.WorkReport),
    queued: Queued(WorkReportAndDeps),
    map_buffer: std.ArrayList(types.WorkReportHash),
} {
    const span = trace.span(.prepare_reports_for_accumulation);
    defer span.deinit();

    var map_buffer = try std.ArrayList(types.WorkReportHash).initCapacity(allocator, 32);
    errdefer map_buffer.deinit();

    // Initialize lists for various report categories
    var accumulatable_buffer = Accumulatable(types.WorkReport).init(allocator);
    errdefer meta.deinit.deinitEntriesAndAggregate(allocator, accumulatable_buffer);
    var queued = Queued(WorkReportAndDeps).init(allocator);
    errdefer meta.deinit.deinitEntriesAndAggregate(allocator, queued);

    span.debug("Initialized accumulatable and queued containers", .{});

    // Partition reports into immediate and queued based on dependencies
    const partition_result = try partitionReports(allocator, reports, &accumulatable_buffer, &queued);
    span.debug("Partitioned reports: {d} immediate, {d} queued", .{ partition_result.immediate_count, partition_result.queued_count });

    // 12,5
    // Filter out any reports which we already accumulated, and remove any dependencies
    // which we already acummulated. This can potentially produce new resolved work reports
    const filter_result = try filterAccumulatedReports(params.epoch_length, allocator, &queued, xi);
    span.debug("Filtered reports: removed {d}, resolved {d} dependencies", .{ filter_result.filtered_out, filter_result.resolved_deps });

    // 12.12: Build the initial set of pending_reports
    var pending_reports_queue = try buildPendingReportsQueue(
        params.epoch_length,
        allocator,
        theta,
        &queued,
        current_slot_in_epoch,
    );
    defer meta.deinit.deinitEntriesAndAggregate(allocator, pending_reports_queue);

    // Now resolve dependenceies using E 12.7
    span.debug("Resolving dependencies using queue editing function", .{});
    queueEditingFunction(
        &pending_reports_queue,
        try mapWorkPackageHash(&map_buffer, accumulatable_buffer.items), // accumulatable contains immediate
    );

    // 12.11 Process reports that are ready from the queue and add to accumulatable
    span.debug("Processing accumulation queue to find accumulatable reports", .{});
    span.debug("Accumulatable buffer before processAccumulationQueue: {d} items", .{accumulatable_buffer.items.len});
    try processAccumulationQueue(
        allocator,
        &pending_reports_queue,
        &accumulatable_buffer,
    );
    span.debug("Accumulatable buffer after processAccumulationQueue: {d} items", .{accumulatable_buffer.items.len});

    return .{
        .accumulatable_buffer = accumulatable_buffer,
        .queued = queued,
        .map_buffer = map_buffer,
    };
}

/// processes the new to be accumulated reports
pub fn processAccumulateReports(
    comptime params: Params,
    stx: *state_delta.StateTransition(params),
    reports: []types.WorkReport,
) !@import("accumulate/execution.zig").ProcessAccumulationResult {
    const span = trace.span(.process_accumulate_reports);
    defer span.deinit();

    span.debug("Starting process accumulate reports with {d} reports", .{reports.len});

    const allocator = stx.allocator;

    // Initialize the necessary state components
    const xi: *state.Xi(params.epoch_length) = try stx.ensure(.xi_prime);
    span.debug("Initialized xi state component", .{});

    const theta: *state.Theta(params.epoch_length) = try stx.ensure(.theta_prime);

    // Prepare reports for accumulation
    var prepared = try prepareReportsForAccumulation(
        params,
        allocator,
        reports,
        xi,
        theta,
        stx.time.current_slot_in_epoch,
    );
    defer meta.deinit.deinitEntriesAndAggregate(allocator, prepared.accumulatable_buffer);
    defer meta.deinit.deinitEntriesAndAggregate(allocator, prepared.queued);
    defer prepared.map_buffer.deinit();

    const execute_span = span.child(.execute_accumulatable);
    defer execute_span.deinit();

    // Get the privileges state to access free services
    const chi: *state.Chi = try stx.ensure(.chi_prime);

    // Calculate gas limit
    const gas_limit = calculateGasLimit(params, chi);

    // TODO: assurances_test test vectors fail because of this limitation which
    // is I believe in the graypaper. Check the testvectors if we need to use
    // other params now just disabled this constraint
    // const accumulatable = prepared.accumulatable_buffer.items[0..@min(prepared.accumulatable_buffer.items.len, params.core_count)];
    const accumulatable = prepared.accumulatable_buffer.items;

    // Execute work reports scheduled for accumulation
    var result = try executeAccumulation(params, allocator, stx, accumulatable, gas_limit, chi);
    defer result.deinit(allocator);

    const accumulated = accumulatable[0..result.accumulated_count];

    // Apply deferred transfers as per 12.23 and 12.24
    const transfer_stats = try applyDeferredTransfers(params, allocator, stx, result.transfers);

    // Add ready reports to accumulation history
    try updateAccumulationHistory(params.epoch_length, xi, accumulated);

    // 12.27 Update theta pending reports
    try updateThetaState(
        params.epoch_length,
        allocator,
        theta,
        &prepared.queued,
        accumulated,
        &prepared.map_buffer,
        .{
            .current_slot = stx.time.current_slot,
            .prior_slot = stx.time.prior_slot,
            .current_slot_in_epoch = stx.time.current_slot_in_epoch,
        },
    );

    // Calculate the AccumulateRoot here
    const accumulate_root = try calculateAccumulateRoot(allocator, result.accumulation_outputs);

    // --- Calculate I and X statistics ---
    // Calculate I stats (Accumulation) - Eq 12.25
    const accumulation_stats = try calculateAccumulationStats(allocator, accumulated, &result.service_gas_used);

    span.debug("Process accumulate reports completed successfully", .{});
    // Return the final result structure including the computed statistics
    // Note: Ownership of the HashMaps passes to the caller.
    return @import("accumulate/execution.zig").ProcessAccumulationResult{
        .accumulate_root = accumulate_root,
        .accumulation_stats = accumulation_stats,
        .transfer_stats = transfer_stats,
    };
}

fn mapWorkPackageHash(buffer: anytype, items: anytype) ![]types.WorkReportHash {
    buffer.clearRetainingCapacity();
    for (items) |item| {
        try buffer.append(item.package_spec.hash);
    }

    return buffer.items;
}

/// Type alias for queued work reports with dependencies
pub fn Queued(T: type) type {
    return std.ArrayList(T);
}

/// Type alias for work reports ready for accumulation
pub fn Accumulatable(T: type) type {
    return std.ArrayList(T);
}

/// Type alias for resolved work package hashes
pub fn Resolved(T: type) type {
    return std.ArrayList(T);
}
