//! Cryptographic primitives for JAM implementation.
//! Provides unified access to various elliptic curve operations and signature schemes.

const std = @import("std");
const types = @import("types.zig");

// External crypto modules
pub const bandersnatch = @import("crypto/bandersnatch.zig");
pub const bls12_381 = @import("crypto/bls12_381.zig");
