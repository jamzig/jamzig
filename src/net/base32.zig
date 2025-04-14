const base32 = @import("base32");
pub const Encoding = base32.Encoding.initWithPadding("abcdefghijklmnopqrstuvwxyz234567", null);
