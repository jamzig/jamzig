//! Entropy accumulation for the JAM protocol.
//!
//! This module implements the entropy update function (η) as specified in the JAM graypaper.
//! The entropy is a 32-byte value that is updated each block by hashing the previous entropy
//! concatenated with the header hash.

const std = @import("std");
const types = @import("types.zig");

// External imports
const Blake2b_256 = std.crypto.hash.blake2.Blake2b(256);

// Type aliases
const Allocator = std.mem.Allocator;

// Constants
pub const HASH_SIZE = 32;
pub const CONCATENATED_SIZE = 64;

// Type definitions
pub const Hash = types.OpaqueHash;
pub const Entropy = types.OpaqueHash;
pub const ConcatenatedEntropy = [CONCATENATED_SIZE]u8;

// Compile-time assertions
comptime {
    std.debug.assert(@sizeOf(Hash) == HASH_SIZE);
    std.debug.assert(@sizeOf(Entropy) == HASH_SIZE);
    std.debug.assert(@sizeOf(ConcatenatedEntropy) == CONCATENATED_SIZE);
    std.debug.assert(CONCATENATED_SIZE == HASH_SIZE * 2);
}

/// Computes Blake2b hash of input data.
/// Returns a 32-byte hash.
pub fn hash(input: []const u8) Hash {
    var hasher = Blake2b_256.init(.{});
    hasher.update(input);
    var output: Hash = undefined;
    hasher.final(&output);

    return output;
}

/// Concatenates two 32-byte arrays into a 64-byte array.
/// Used to prepare entropy and header hash for hashing.
pub fn concatenate(a: Hash, b: Hash) ConcatenatedEntropy {
    var result: ConcatenatedEntropy = undefined;
    @memcpy(result[0..HASH_SIZE], &a);
    @memcpy(result[HASH_SIZE..], &b);

    return result;
}

/// Updates the entropy value according to the JAM protocol.
///
/// Implements equation (66) from the graypaper:
/// η′₀ ≡ H(η₀ ⌢ Y(Hᵥ))
///
/// Where:
/// - η₀ is the current entropy
/// - Hᵥ is the header hash (already Y-encoded)
/// - H is the Blake2b hash function
/// - ⌢ is concatenation
pub fn update(eta_0: Entropy, h_v: Hash) Entropy {
    // Concatenate η₀ and Y(Hᵥ)
    const concatenated = concatenate(eta_0, h_v);

    // Hash the concatenated result to produce the new entropy η'₀
    const new_eta_0 = hash(&concatenated);

    return new_eta_0;
}
