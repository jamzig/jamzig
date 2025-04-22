const std = @import("std");
const testing = std.testing;
const net_server = @import("../server.zig");
const net_client = @import("../client.zig");
const network = @import("network");

pub const TestServer = struct {
    thread: *net_server.ServerThread,
    server: net_server.Server,
    thread_handle: std.Thread,

    pub fn join(self: *TestServer) void {
        self.server.shutdown() catch {};
        self.thread_handle.join();
    }

    pub fn deinit(self: *TestServer) void {
        self.thread.deinit();
    }

    pub fn joinAndDeinit(self: *TestServer) void {
        self.join();
        self.deinit();
    }
};

/// Helper function to create and initialize the server
fn createTestServer(allocator: std.mem.Allocator) !TestServer {
    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic([_]u8{0} ** 32);
    const genesis_hash = "test_genesis_hash";

    // -- Create server using builder
    var server_thread_builder = net_server.ServerThreadBuilder.init();
    var server_thread = server_thread_builder
        .allocator(allocator)
        .keypair(keypair)
        .genesisHash(genesis_hash)
        .allowBuilders(false)
        .build() catch |err| {
        std.log.err("Failed to build server thread: {s}", .{@errorName(err)});
        return err;
    };

    // -- Start the server thread
    const thread_handle = server_thread.startThread() catch |err| {
        std.log.err("Failed to start server thread: {s}", .{@errorName(err)});
        server_thread.deinit();
        return err;
    };

    // -- Create the Server API handle
    const server = try net_server.Server.init(allocator, server_thread);

    return .{
        .thread = server_thread,
        .server = server,
        .thread_handle = thread_handle,
    };
}

pub const TestClient = struct {
    thread: *net_client.ClientThread,
    client: net_client.Client,
    thread_handle: std.Thread,

    pub fn join(self: *TestClient) void {
        self.client.shutdown() catch {};
        self.thread_handle.join();
    }

    pub fn deinit(self: *TestClient) void {
        self.thread.deinit();
    }

    pub fn joinAndDeinit(self: *TestClient) void {
        self.join();
        self.deinit();
    }
};

/// Helper function to create and initialize the client
fn createTestClient(allocator: std.mem.Allocator) !TestClient {
    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic([_]u8{1} ** 32);
    const genesis_hash = "test_genesis_hash"; // Same as server for test communication

    // -- Create client using builder
    var client_thread_builder = net_client.ClientThreadBuilder.init();
    var client_thread = client_thread_builder
        .allocator(allocator)
        .keypair(keypair)
        .genesisHash(genesis_hash)
        .isBuilder(false)
        .build() catch |err| {
        std.log.err("Failed to build client thread: {s}", .{@errorName(err)});
        return err;
    };

    // -- Start the client thread
    const thread_handle = client_thread.startThread() catch |err| {
        std.log.err("Failed to start client thread: {s}", .{@errorName(err)});
        client_thread.deinit();
        return err;
    };

    // -- Create the Client API handle
    const client = net_client.Client.init(client_thread);

    return .{
        .thread = client_thread,
        .client = client,
        .thread_handle = thread_handle,
    };
}

test "server creation and listen" {
    const allocator = std.testing.allocator;
    const timeout_ms: u64 = 5000; // 1 second timeout

    // Create and start server
    var test_server = try createTestServer(allocator);
    defer test_server.joinAndDeinit();

    // Start listening on a port
    const listen_address = "::1"; // Use IPv6 loopback
    const listen_port: u16 = 0; // Use port 0 to get an ephemeral port assigned by the OS
    try test_server.server.listen(listen_address, listen_port);

    // Expect listening event
    const listening_event = expectEvent(&test_server.server, timeout_ms, .listening) catch |err| {
        std.log.err("Failed to receive listen event: {s}", .{@errorName(err)});
        return err;
    };

    // Get the server's bound endpoint from the listening event
    const server_endpoint = listening_event.listening.local_endpoint;
    std.debug.print("Server is listening on {}", .{server_endpoint});

    // Create and start client
    var test_client = try createTestClient(allocator);
    defer test_client.joinAndDeinit();

    // Connect client to server
    try test_client.client.connect(server_endpoint);

    // Wait for connection event on client
    const connected_event = expectClientEvent(&test_client.client, timeout_ms, .connected) catch |err| {
        std.log.err("Failed to receive connected event: {s}", .{@errorName(err)});
        return err;
    };
    std.log.info("Client connected with connection ID: {}", .{connected_event.connected.connection_id});

    // TODO: wait for server event as well
    // TODO: threads are not closing properly

    std.log.info("Server connect test completed successfully.", .{});
}

pub fn expectEvent(
    server: *net_server.Server,
    timeout_ms: u64,
    event_type: std.meta.FieldEnum(net_server.Server.Event),
) !net_server.Server.Event {
    const maybe_event = server.timedWaitEvent(timeout_ms);
    if (maybe_event) |event| {
        if (@as(std.meta.FieldEnum(net_server.Server.Event), event) != event_type) {
            std.debug.print("Expected event type {}, but got {}\n", .{ event_type, event });
            return error.InvalidEventType;
        }
        std.debug.print("Received expected event: {}\n", .{event});
        return event;
    } else {
        return error.Timeout;
    }
}

pub fn expectClientEvent(
    client: *net_client.Client,
    timeout_ms: u64,
    event_type: std.meta.FieldEnum(net_client.Client.Event),
) !net_client.Client.Event {
    const maybe_event = client.timedWaitEvent(timeout_ms);
    if (maybe_event) |event| {
        if (@as(std.meta.FieldEnum(net_client.Client.Event), event) != event_type) {
            std.debug.print("Expected client event type {}, but got {}\n", .{ event_type, event });
            return error.InvalidEventType;
        }
        std.debug.print("Received expected client event: {}\n", .{event});
        return event;
    } else {
        return error.Timeout;
    }
}
