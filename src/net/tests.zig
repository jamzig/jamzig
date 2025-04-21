comptime {
    _ = @import("tests/simple_connect_test.zig");
    _ = @import("tests/server_test.zig");
    _ = @import("tests/client_test.zig");

    // -- JAMSNPSERVER TESTS
    _ = @import("tests/jamsnp_simple_connect_test.zig");
}
