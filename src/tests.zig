comptime {
    _ = @import("safrole_test.zig");
}

const std = @import("std");
const tv_types = @import("tests/vectors/libs/types.zig");
const tv_lib_safrole = @import("tests/vectors/libs/safrole.zig");

const lib_safrole = @import("safrole/types.zig");

const Error = error{ FromError, OutOfMemory };
const Allocator = std.mem.Allocator;

/// Maps the type from the testVector to a safrole implementation type
pub fn stateFromTestVector(allocator: Allocator, from: *const tv_lib_safrole.State) Error!*lib_safrole.State {
    var to = try allocator.create(lib_safrole.State);
    to.tau = from.tau;
    convertEta(&from.eta, &to.eta);
    to.lambda = try convertValidatorDataSlice(allocator, from.lambda);
    to.kappa = try convertValidatorDataSlice(allocator, from.kappa);
    to.gamma_k = try convertValidatorDataSlice(allocator, from.gamma_k);
    to.iota = try convertValidatorDataSlice(allocator, from.iota);
    to.gamma_a = try convertTicketBodySlice(allocator, from.gamma_a);
    to.gamma_s = try convertGammaS(allocator, from.gamma_s);
    convertGammaZ(&from.gamma_z, &to.gamma_z);

    return to;
}

pub fn inputFromTestVector(allocator: Allocator, from: *const tv_lib_safrole.Input) Error!*lib_safrole.Input {
    var to = try allocator.create(lib_safrole.Input);

    convertOpaqueHash(from.entropy, &to.entropy);

    to.extrinsic = try allocator.alloc(lib_safrole.TicketEnvelope, from.extrinsic.len);
    for (from.extrinsic, to.extrinsic) |from_envelope, *to_envelope| {
        to_envelope.attempt = from_envelope.attempt;
        convertHexBytesToArray(784, from_envelope.signature, &to_envelope.signature);
    }

    return to;
}

fn convertEta(from: *const [4]tv_lib_safrole.OpaqueHash, to: *[4]lib_safrole.OpaqueHash) void {
    for (from, to) |from_hash, *to_hash| {
        convertOpaqueHash(from_hash, to_hash);
    }
}

fn convertOpaqueHash(from: tv_lib_safrole.OpaqueHash, to: *lib_safrole.OpaqueHash) void {
    convertHexBytesFixedToArray(32, from, to);
}

fn convertHexBytesFixedToArray(comptime size: u32, from: tv_types.hex.HexBytesFixed(size), to: *[size]u8) void {
    for (from.bytes, 0..) |from_byte, i| {
        to[i] = from_byte;
    }
}

fn convertHexBytesToArray(comptime size: u32, from: tv_types.hex.HexBytes, to: *[size]u8) void {
    std.debug.assert(from.bytes.len == size);

    for (from.bytes, 0..) |from_byte, i| {
        to[i] = from_byte;
    }
}

fn convertValidatorDataSlice(allocator: Allocator, from: []tv_lib_safrole.ValidatorData) Error![]lib_safrole.ValidatorData {
    const to = try allocator.alloc(lib_safrole.ValidatorData, from.len);
    for (from, to) |*from_validator, *to_validator| {
        convertValidatorData(from_validator, to_validator);
    }
    return to;
}

fn convertValidatorData(from: *tv_lib_safrole.ValidatorData, to: *lib_safrole.ValidatorData) void {
    convertHexBytesToArray(32, from.bandersnatch, &to.bandersnatch);
    convertHexBytesToArray(32, from.ed25519, &to.ed25519);
    convertHexBytesToArray(144, from.bls, &to.bls);
    convertHexBytesToArray(128, from.metadata, &to.metadata);
}

fn convertTicketBodySlice(allocator: Allocator, from: []tv_lib_safrole.TicketBody) Error![]lib_safrole.TicketBody {
    const to = try allocator.alloc(lib_safrole.TicketBody, from.len);
    for (from, to) |*from_ticket, *to_ticket| {
        convertTicketBody(from_ticket, to_ticket);
    }
    return to;
}

fn convertTicketBody(from: *const tv_lib_safrole.TicketBody, to: *lib_safrole.TicketBody) void {
    convertOpaqueHash(from.id, &to.id);
    to.attempt = from.attempt;
}

fn convertGammaS(allocator: Allocator, from: tv_lib_safrole.GammaS) Error!lib_safrole.GammaS {
    switch (from) {
        .tickets => {
            return lib_safrole.GammaS{ .tickets = try convertTicketBodySlice(allocator, from.tickets) };
        },
        .keys => {
            return lib_safrole.GammaS{ .keys = try convertBandersnatchKeysSlice(allocator, from.keys) };
        },
    }
}

fn convertBandersnatchKeysSlice(allocator: Allocator, from: []tv_lib_safrole.BandersnatchKey) Error![]lib_safrole.BandersnatchKey {
    const to = try allocator.alloc(lib_safrole.BandersnatchKey, from.len);
    for (from, to) |from_key, *to_key| {
        convertHexBytesFixedToArray(32, from_key, to_key);
    }
    return to;
}

fn convertGammaZ(from: *const tv_lib_safrole.GammaZ, to: *lib_safrole.GammaZ) void {
    convertHexBytesFixedToArray(144, from.*, to);
}
