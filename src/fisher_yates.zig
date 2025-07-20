//! Fisher-Yates shuffle implementation for JAM
//!
//! This module implements the Fisher-Yates shuffle algorithm as specified in the JAM Graypaper.
//! The shuffle uses Blake2b hashing to derive entropy for selecting elements.
//!
//! Memory management follows style principles:
//! - No hidden allocations
//! - All allocation failures are explicit
//! - Caller controls memory ownership
//!
//! References:
//! - JAM Graypaper Section F.2: Fisher-Yates Shuffle

const std = @import("std");
const Blake2b256 = std.crypto.hash.blake2.Blake2b256;

/// Encodes a u32 into 4 bytes in little-endian format (E_4 from graypaper)
inline fn encodeU32(n: u32) [4]u8 {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, n, .little);
    return bytes;
}

/// Decodes 4 bytes in little-endian format to a u32 (E_4^(-1) from graypaper)
inline fn decodeU32(bytes: []const u8) u32 {
    return std.mem.readInt(u32, bytes[0..4], .little);
}

/// Derives entropy from a hash for the i-th position (Q function from graypaper F.2)
/// 
/// This implements Q(i, h) = E_4^(-1)(H(h ++ E_4(floor(i/8)))[(4i mod 32):(4i mod 32)+4])
pub fn deriveEntropy(i: usize, hash: [32]u8) u32 {
    // Calculate floor(i/8) and encode it
    const idx = i / 8;
    const encoded_idx = encodeU32(@intCast(idx));

    // Hash the concatenated input
    var hasher = Blake2b256.init(.{});
    hasher.update(&hash);
    hasher.update(&encoded_idx);
    var output: [32]u8 = undefined;
    hasher.final(&output);

    // Take 4 bytes starting at (4i mod 32) and decode
    const start = (4 * i) % 32;
    return decodeU32(output[start .. start + 4]);
}

/// Core Fisher-Yates implementation used by all public functions
/// 
/// Preconditions:
/// - sequence.len == result.len == seq_copy.len
/// - hash.len == 32
fn shuffleCore(
    comptime T: type,
    sequence: []T,
    result: []T,
    seq_copy: []T,
    hash: [32]u8,
) void {
    // Copy input to working copy
    @memcpy(seq_copy, sequence);

    var seq_len = sequence.len;

    // Process each element in order (Fisher-Yates algorithm)
    for (0..sequence.len) |i| {
        // Calculate index based on entropy
        const idx = deriveEntropy(i, hash) % seq_len;

        // Take the element at that index for the result
        result[i] = seq_copy[idx];

        // Replace the selected element with the last element in the working set
        // This effectively removes the selected element from consideration
        if (idx < seq_len - 1) {
            seq_copy[idx] = seq_copy[seq_len - 1];
        }

        // Reduce the working set size
        seq_len -= 1;
    }

    // Copy result back to the input sequence
    @memcpy(sequence, result);
}

/// Fisher-Yates shuffle with explicit allocation
/// 
/// Shuffles the sequence in-place using the provided hash as entropy source.
/// Returns error if allocation fails.
/// 
/// Memory: Allocates 2 * sequence.len * @sizeOf(T) bytes
pub fn shuffleWithHashAlloc(
    comptime T: type,
    allocator: std.mem.Allocator,
    sequence: []T,
    hash: [32]u8,
) !void {
    // Handle empty sequence case
    if (sequence.len == 0) return;

    // Allocate a single buffer for both the result and working copy
    const buffer = try allocator.alloc(T, sequence.len * 2);
    defer allocator.free(buffer);

    // Split the buffer into result and working copy sections
    const result = buffer[0..sequence.len];
    const seq_copy = buffer[sequence.len..];

    // Use the common core implementation
    shuffleCore(T, sequence, result, seq_copy, hash);
}

/// Maximum safe stack allocation size in bytes (500KB)
const MAX_SAFE_STACK_BYTES: usize = 500 * 1024;

/// Fisher-Yates shuffle with compile-time bounded stack allocation
/// 
/// Uses stack allocation for sequences up to max_size elements.
/// Panics if sequence.len > max_size.
/// 
/// Memory: Uses 2 * max_size * @sizeOf(T) bytes of stack space
pub fn shuffleWithHash(
    comptime T: type,
    comptime max_size: usize,
    sequence: []T,
    hash: [32]u8,
) void {
    // Calculate total bytes needed for both arrays at compile time
    const total_bytes_needed = 2 * max_size * @sizeOf(T);

    // If the size is too large for stack allocation, panic at compile time
    if (comptime total_bytes_needed > MAX_SAFE_STACK_BYTES) {
        @compileError("Fisher-Yates stack arrays would exceed safe stack size limit. " ++
            "Array size: " ++ std.fmt.comptimePrint("{}", .{total_bytes_needed}) ++ " bytes, " ++
            "limit: " ++ std.fmt.comptimePrint("{}", .{MAX_SAFE_STACK_BYTES}) ++ " bytes. " ++
            "Use shuffleWithHashAlloc for large sequences.");
    }

    // Handle empty sequence case
    if (sequence.len == 0) return;

    // Fixed-size implementation - uses stack memory instead of heap
    var result: [max_size]T = undefined;
    var seq_copy: [max_size]T = undefined;

    // Only use the portion of the arrays we need
    const result_slice = result[0..sequence.len];
    const seq_copy_slice = seq_copy[0..sequence.len];

    // Use the common core implementation
    shuffleCore(T, sequence, result_slice, seq_copy_slice, hash);
}

// New API with cleaner names
pub const shuffleAlloc = shuffleWithHashAlloc;
pub const shuffle = shuffleWithHash;
