const std = @import("std");
const testing = std.testing;
const net = @import("../server.zig"); // Assuming server.zig contains ServerThreadBuilder, ServerThread, Server
const network = @import("network");

test "server creation and listen" {
    const allocator = std.testing.allocator;

    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic([_]u8{0} ** 32);
    const genesis_hash = "test_genesis_hash";

    // 1. Create server using builder
    var server_thread_builder = net.ServerThreadBuilder.init();
    var server_thread = server_thread_builder
        .allocator(allocator)
        .keypair(keypair)
        .genesisHash(genesis_hash)
        .allowBuilders(false)
        .build() catch |err| {
        std.log.err("Failed to build server thread: {s}", .{@errorName(err)});
        return err;
    };
    defer server_thread.deinit();

    // 2. Start the server thread
    var thread_handle = server_thread.startThread() catch |err| {
        std.log.err("Failed to start server thread: {s}", .{@errorName(err)});
        return err;
    };
    defer thread_handle.join(); // Ensure thread is joined on exit

    // Create the Server API handle
    var server = try net.Server.init(allocator, server_thread);
    defer server.shutdown() catch |err| { // Ensure server shutdown is called
        std.log.warn("Error shutting down server: {s}", .{@errorName(err)});
    };

    // 3. Start listening on a port
    const listen_address = "::1"; // Use IPv6 loopback
    const listen_port: u16 = 0; // Use port 0 to get an ephemeral port assigned by the OS

    server.listen(listen_address, listen_port) catch |err| {
        std.log.err("Failed to start listening: {s}", .{@errorName(err)});
        return err;
    };

    // 4. Check if events work correctly (Placeholder)

    std.log.info("Server test completed successfully.", .{});
}
