const std = @import("std");
const testing = std.testing;
const net = @import("../server.zig"); // Assuming server.zig contains ServerThreadBuilder, ServerThread, Server
const network = @import("network");

test "server creation and listen" {
    const allocator = std.testing.allocator;

    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic([_]u8{0} ** 32);
    const genesis_hash = "test_genesis_hash";

    // -- Create server using builder
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

    // -- Start the server thread
    var thread_handle = server_thread.startThread() catch |err| {
        std.log.err("Failed to start server thread: {s}", .{@errorName(err)});
        return err;
    };
    defer thread_handle.join(); // Ensure thread is joined on exit

    // -- Create the Server API handle
    var server = try net.Server.init(allocator, server_thread);
    defer server.shutdown() catch |err| { // Ensure server shutdown is called
        std.log.warn("Error shutting down server: {s}", .{@errorName(err)});
    };

    // -- Start listening on a port
    const listen_address = "::1"; // Use IPv6 loopback
    const listen_port: u16 = 0; // Use port 0 to get an ephemeral port assigned by the OS

    server.listen(listen_address, listen_port) catch |err| {
        std.log.err("Failed to start listening: {s}", .{@errorName(err)});
        return err;
    };

    // 4. Wait for an event with a timeout after listening starts
    // Note: This test currently waits for *any* event. A more robust test
    // would require simulating a client connection and specifically waiting
    // for the '.client_connected' event.
    const timeout_ms: u64 = 1000; // 1 second timeout
    const maybe_event = server.timedWaitEvent(timeout_ms);

    if (maybe_event) |event| {
        // TODO: Add more specific event checking if needed, e.g., wait for .client_connected
        std.log.info("Received server event: {any}", .{event});
        // For this simple test, receiving any event within the timeout might be sufficient
        // depending on expected server behavior immediately after listening.
        // If '.client_connected' is the target, this test needs an external client trigger.
    } else {
        std.log.err("Test timed out waiting for event after {d}ms.", .{timeout_ms});
        try testing.expect(false); // Fail the test explicitly on timeout
    }

    std.log.info("Server connect test (waiting part) completed successfully.", .{});
}
