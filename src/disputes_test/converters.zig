const std = @import("std");
const tvector = @import("../tests/vectors/libs/disputes.zig");
const state = @import("../state.zig");
const types = @import("../types.zig");

const disputes = @import("../disputes.zig");

pub fn convertPsi(allocator: std.mem.Allocator, test_psi: tvector.DisputesRecords) !state.Psi {
    var good_set = std.AutoHashMap(disputes.Hash, void).init(allocator);
    for (test_psi.psi_g) |hash| {
        try good_set.put(hash.bytes, {});
    }

    var bad_set = std.AutoHashMap(disputes.Hash, void).init(allocator);
    for (test_psi.psi_b) |hash| {
        try bad_set.put(hash.bytes, {});
    }

    var wonky_set = std.AutoHashMap(disputes.Hash, void).init(allocator);
    for (test_psi.psi_w) |hash| {
        try wonky_set.put(hash.bytes, {});
    }

    var punish_set = std.AutoHashMap(disputes.PublicKey, void).init(allocator);
    for (test_psi.psi_o) |key| {
        try punish_set.put(key.bytes, {});
    }

    return state.Psi{
        .good_set = good_set,
        .bad_set = bad_set,
        .wonky_set = wonky_set,
        .punish_set = punish_set,
    };
}

pub fn convertDisputesExtrinsic(allocator: std.mem.Allocator, test_disputes: tvector.DisputesXt) !types.DisputesExtrinsic {
    var verdicts = try allocator.alloc(types.Verdict, test_disputes.verdicts.len);
    errdefer allocator.free(verdicts);

    for (test_disputes.verdicts, 0..) |test_verdict, i| {
        var votes = try allocator.alloc(types.Judgement, test_verdict.votes.len);
        errdefer allocator.free(votes);

        for (test_verdict.votes, 0..) |test_vote, j| {
            votes[j] = .{
                .vote = test_vote.vote,
                .index = test_vote.index,
                .signature = test_vote.signature.bytes,
            };
        }

        verdicts[i] = .{
            .target = test_verdict.target.bytes,
            .age = test_verdict.age,
            .votes = votes,
        };
    }

    var culprits = try allocator.alloc(types.Culprit, test_disputes.culprits.len);
    errdefer allocator.free(culprits);

    for (test_disputes.culprits, 0..) |test_culprit, i| {
        culprits[i] = .{
            .target = test_culprit.target.bytes,
            .key = test_culprit.key.bytes,
            .signature = test_culprit.signature.bytes,
        };
    }

    var faults = try allocator.alloc(types.Fault, test_disputes.faults.len);
    errdefer allocator.free(faults);

    for (test_disputes.faults, 0..) |test_fault, i| {
        faults[i] = .{
            .target = test_fault.target.bytes,
            .vote = test_fault.vote,
            .key = test_fault.key.bytes,
            .signature = test_fault.signature.bytes,
        };
    }

    return types.DisputesExtrinsic{
        .verdicts = verdicts,
        .culprits = culprits,
        .faults = faults,
    };
}
