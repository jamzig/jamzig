const std = @import("std");
const Allocator = std.mem.Allocator;

// Types
const Hash = [32]u8;
const Signature = [64]u8;
const PublicKey = [32]u8;

const types = @import("types.zig");

const Judgment = types.Judgement;
const Verdict = types.Verdict;
const Culprit = types.Culprit;
const Fault = types.Fault;
const DisputesExtrinsic = types.DisputesExtrinsic;

const Psi = struct {
    good_set: std.AutoHashMap(Hash, void),
    bad_set: std.AutoHashMap(Hash, void),
    wonky_set: std.AutoHashMap(Hash, void),
    punish_set: std.AutoHashMap(PublicKey, void),

    fn init(allocator: Allocator) Psi {
        return Psi{
            .good_set = std.AutoHashMap(Hash, void).init(allocator),
            .bad_set = std.AutoHashMap(Hash, void).init(allocator),
            .wonky_set = std.AutoHashMap(Hash, void).init(allocator),
            .punish_set = std.AutoHashMap(PublicKey, void).init(allocator),
        };
    }

    fn deinit(self: *Psi) void {
        self.good_set.deinit();
        self.bad_set.deinit();
        self.wonky_set.deinit();
        self.punish_set.deinit();
    }
};

// NOTE: We need to verify the signature of the judgements of the verdict, which
// is a signature of the validator (indicated by the validator index) public key,
// either in the kappa set if the age of the verdict is t/E, otherwise from the
// lambda set. We need to verify this one level up before this processDisputesExtrinsic
// is called. Maybe introduce a type VerifiedDisputesExtrinsic to ensure verification
// has been done using the type system. The signature is build as a concatenation of:
// jam_valid ++ verdict.target if voted true
// jam_invalid ++ verdict.target if voted false
//
// NOTE: The same for Culprit and Fault, where not validator index is given but the
// Edwards25519 public key of the validator. Which shoud be in the set of validators as
// defined above.
//
// NOTE: Ordering needs to be checked. Verdicts on target hash, culprits and faults signatures
// must be ordered by the key. The judgements need to be ordered by validator index
// and there must not be any duplicates.
//
// NOTE: The sizes need to be either two-

// The disputes extrinsic, ED , may contain one or more verdicts v as a
// compilation of judgments coming from exactly two-thirds plus one of either
// the active validator set or the previous epoch’s validator set, i.e. the
// Ed25519 keys of κ or λ.
pub fn processDisputesExtrinsic(state: *Psi, extrinsic: DisputesExtrinsic, validator_count: usize) !void {
    // Process verdicts: V Gp0.4.1 (107) (108)
    for (extrinsic.verdicts) |verdict| {
        const positive_judgments = countPositiveJudgments(verdict);
        if (positive_judgments == validator_count * 2 / 3 + 1) {
            try state.good_set.put(verdict.target, {});
        } else if (positive_judgments == 0) {
            try state.bad_set.put(verdict.target, {});
        } else if (positive_judgments == validator_count / 3) {
            try state.wonky_set.put(verdict.target, {});
        }
    }

    // Process culprits
    for (extrinsic.culprits) |culprit| {
        if (state.bad_set.contains(culprit.target)) {
            try state.punish_set.put(culprit.key, {});
        }
    }

    // Process faults
    for (extrinsic.faults) |fault| {
        const in_good_set = state.good_set.contains(fault.target);
        const in_bad_set = state.bad_set.contains(fault.target);
        if ((fault.vote and in_bad_set) or
            (!fault.vote and in_good_set))
        {
            try state.punish_set.put(fault.key, {});
        }
    }
}

fn countPositiveJudgments(verdict: Verdict) usize {
    var count: usize = 0;
    for (verdict.votes) |judgment| {
        if (judgment.vote) {
            count += 1;
        }
    }
    return count;
}

const testing = std.testing;

test "processDisputesExtrinsic - good set" {
    const allocator = std.testing.allocator;
    var state = Psi.init(allocator);
    defer state.deinit();

    const validator_count: usize = 3; // Simplified for testing
    const target_hash: Hash = [_]u8{1} ** 32;

    const extrinsic = types.DisputesExtrinsic{
        .verdicts = &[_]types.Verdict{.{
            .age = 0,
            .target = target_hash,
            .votes = &[_]types.Judgement{
                .{ .index = 0, .vote = true, .signature = [_]u8{0} ** 64 },
                .{ .index = 1, .vote = true, .signature = [_]u8{0} ** 64 },
                .{ .index = 2, .vote = true, .signature = [_]u8{0} ** 64 },
            },
        }},
        .culprits = &[_]types.Culprit{},
        .faults = &[_]types.Fault{},
    };

    try processDisputesExtrinsic(&state, extrinsic, validator_count);

    try testing.expect(state.good_set.contains(target_hash));
    try testing.expect(!state.bad_set.contains(target_hash));
    try testing.expect(!state.wonky_set.contains(target_hash));
}

test "processDisputesExtrinsic - bad set" {
    const allocator = std.testing.allocator;
    var state = Psi.init(allocator);
    defer state.deinit();

    const validator_count: usize = 3; // Simplified for testing
    const target_hash: Hash = [_]u8{2} ** 32;

    const extrinsic = types.DisputesExtrinsic{
        .verdicts = &[_]types.Verdict{.{
            .age = 0,
            .target = target_hash,
            .votes = &[_]types.Judgement{
                .{ .index = 0, .vote = false, .signature = [_]u8{0} ** 64 },
                .{ .index = 1, .vote = false, .signature = [_]u8{0} ** 64 },
                .{ .index = 2, .vote = false, .signature = [_]u8{0} ** 64 },
            },
        }},
        .culprits = &[_]types.Culprit{},
        .faults = &[_]types.Fault{},
    };

    try processDisputesExtrinsic(&state, extrinsic, validator_count);

    try testing.expect(!state.good_set.contains(target_hash));
    try testing.expect(state.bad_set.contains(target_hash));
    try testing.expect(!state.wonky_set.contains(target_hash));
}

test "processDisputesExtrinsic - wonky set" {
    const allocator = std.testing.allocator;
    var state = Psi.init(allocator);
    defer state.deinit();

    const validator_count: usize = 3; // Simplified for testing
    const target_hash: Hash = [_]u8{3} ** 32;

    const extrinsic = types.DisputesExtrinsic{
        .verdicts = &[_]types.Verdict{.{
            .age = 0,
            .target = target_hash,
            .votes = &[_]types.Judgement{
                .{ .index = 0, .vote = true, .signature = [_]u8{0} ** 64 },
                .{ .index = 1, .vote = false, .signature = [_]u8{0} ** 64 },
                .{ .index = 2, .vote = false, .signature = [_]u8{0} ** 64 },
            },
        }},
        .culprits = &[_]types.Culprit{},
        .faults = &[_]types.Fault{},
    };

    try processDisputesExtrinsic(&state, extrinsic, validator_count);

    try testing.expect(!state.good_set.contains(target_hash));
    try testing.expect(!state.bad_set.contains(target_hash));
    try testing.expect(state.wonky_set.contains(target_hash));
}
