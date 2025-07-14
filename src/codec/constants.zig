/// Shared constants for the codec subsystem

/// Maximum value that can be encoded in a single byte (eq. 272)
pub const SINGLE_BYTE_MAX = 0x80;

/// Marker byte indicating 8-byte fixed-length integer follows (eq. 272)
pub const EIGHT_BYTE_MARKER = 0xff;

/// Maximum length value (l) for variable-length encoding
pub const MAX_L_VALUE = 7;

/// Bit shift base for variable-length encoding calculations
pub const ENCODING_BIT_SHIFT = 7;

/// Byte shift for fixed-length integer encoding
pub const BYTE_SHIFT = 8;