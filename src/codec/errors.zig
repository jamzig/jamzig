/// Unified error set for the codec subsystem
/// Errors that can occur during encoding operations
pub const EncodingError = error{
    /// Buffer is too small for the encoded data
    BufferTooSmall,
    /// Value is too large to encode
    ValueTooLarge,
    /// Invalid parameters provided
    InvalidParameters,
};

/// Errors that can occur during decoding operations
pub const DecodingError = error{
    /// Input buffer is empty
    EmptyBuffer,
    /// Not enough data available to complete decoding
    InsufficientData,
    /// Invalid encoding format detected
    InvalidFormat,
    /// Value decoded is out of valid range
    ValueOutOfRange,
};

/// Errors specific to scanner operations
pub const ScannerError = error{
    /// Attempted to read beyond buffer bounds
    BufferOverrun,
    /// Invalid cursor position
    InvalidCursor,
};

/// Errors specific to blob dictionary operations
pub const BlobDictError = error{
    /// Dictionary keys are not in sorted order
    KeysNotSorted,
    /// Duplicate key detected
    DuplicateKey,
    /// Key not found in dictionary
    KeyNotFound,
};

/// Combined error set for all codec operations
pub const CodecError = EncodingError || DecodingError || ScannerError || BlobDictError;
