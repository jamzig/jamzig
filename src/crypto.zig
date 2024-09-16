const std = @import("std");
const types = @import("types.zig");

// Extern declarations for Rust functions
extern fn generate_ring_signature(
    public_keys: [*c]const u8,
    public_keys_len: usize,
    vrf_input_data: [*c]const u8,
    vrf_input_len: usize,
    aux_data: [*c]const u8,
    aux_data_len: usize,
    prover_key_index: usize,
    output: [*c]u8,
    output_len: *usize,
) callconv(.C) bool;

extern fn verify_ring_signature(
    public_keys: [*c]const u8,
    public_keys_len: usize,
    vrf_input_data: [*c]const u8,
    vrf_input_len: usize,
    aux_data: [*c]const u8,
    aux_data_len: usize,
    signature: [*c]const u8,
    signature_len: usize,
    vrf_output: [*c]u8,
) callconv(.C) bool;

// Extern declarations for Rust functions
pub extern fn create_key_pair_from_seed(
    seed: [*c]const u8,
    seed_len: usize,
    output: [*c]u8,
    output_len: *usize,
) callconv(.C) bool;

pub extern fn get_padding_point(
    output: [*c]u8,
    output_len: *usize,
) callconv(.C) bool;

// Zig wrapper functions
pub fn generateRingSignature(
    public_keys: []types.BandersnatchKey,
    vrf_input: []const u8,
    aux_data: []const u8,
    prover_key_index: usize,
) !types.BandersnatchRingSignature {
    var output: types.BandersnatchRingSignature = undefined;
    var output_len: usize = output.len;
    const result = generate_ring_signature(
        public_keys.ptr,
        public_keys.len,
        vrf_input.ptr,
        vrf_input.len,
        aux_data.ptr,
        aux_data.len,
        prover_key_index,
        &output,
        &output_len,
    );

    if (!result) {
        return error.SignatureGenerationFailed;
    }

    return output;
}

pub fn verifyRingSignature(
    public_keys: []types.BandersnatchKey,
    vrf_input: []const u8,
    aux_data: []const u8,
    signature: []const u8,
    vrf_output: *types.BandersnatchVrfOutput,
) bool {
    return verify_ring_signature(
        public_keys.ptr,
        public_keys.len,
        vrf_input.ptr,
        vrf_input.len,
        aux_data.ptr,
        aux_data.len,
        signature.ptr,
        signature.len,
        vrf_output,
    );
}

// Helper functions
pub fn createKeyPairFromSeed(seed: []const u8) !types.BandersnatchKeyPair {
    var output: [64]u8 = undefined;
    var output_len: usize = output.len;
    const result = create_key_pair_from_seed(
        seed.ptr,
        seed.len,
        &output,
        &output_len,
    );

    if (!result) {
        return error.KeyPairGenerationFailed;
    }

    // Split the output into private and public keys
    var key_pair: types.BandersnatchKeyPair = undefined;
    @memcpy(&key_pair.private_key, output[0..32]);
    @memcpy(&key_pair.public_key, output[32..64]);

    return key_pair;
}

pub fn getPaddingPoint() !types.BandersnatchKey {
    var output: types.BandersnatchKey = undefined;
    var output_len: usize = @sizeOf(types.BandersnatchKey);
    const result = get_padding_point(
        &output,
        &output_len,
    );

    if (!result) {
        return error.PaddingPointGenerationFailed;
    }

    return output;
}

test "crypto: createKeyPairFromSeed" {
    const seed = "test seed for key pair generation";
    const key_pair = try createKeyPairFromSeed(seed);

    // Verify that the key pair is not empty
    try std.testing.expect(key_pair.private_key.len == 32);
    try std.testing.expect(key_pair.public_key.len == 32);

    // Verify that the private and public keys are different
    try std.testing.expect(!std.mem.eql(u8, &key_pair.private_key, &key_pair.public_key));

    // Verify that generating a key pair with the same seed produces the same result
    const key_pair2 = try createKeyPairFromSeed(seed);
    try std.testing.expect(std.mem.eql(u8, &key_pair.private_key, &key_pair2.private_key));
    try std.testing.expect(std.mem.eql(u8, &key_pair.public_key, &key_pair2.public_key));

    // Print the key_pair
    std.debug.print("Private key: ", .{});
    for (key_pair.private_key) |byte| {
        std.debug.print("{x:0>2}", .{byte});
    }
    std.debug.print("\n", .{});

    std.debug.print("Public key: ", .{});
    for (key_pair.public_key) |byte| {
        std.debug.print("{x:0>2}", .{byte});
    }
    std.debug.print("\n", .{});
}
