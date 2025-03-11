const std = @import("std");
const pvmlib = @import("pvm.zig");

const polkavm_env = @import("pvm_fuzz_test/polkavm.zig");
const pvm_env = @import("pvm_fuzz_test/pvm.zig");

// Reference tests
comptime {
    _ = @import("pvm_fuzz_test/polkavm.zig");
    _ = @import("pvm_fuzz_test/pvm.zig");
    _ = @import("pvm_fuzz_test/crosscheck.zig");
}
