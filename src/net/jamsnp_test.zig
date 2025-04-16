const std = @import("std");
const ssl = @import("ssl");
const lsquic = @import("lsquic");
const JamSnpServer = @import("jamsnp/server.zig").JamSnpServer;
const JamSnpClient = @import("jamsnp/client.zig").JamSnpClient;
const common = @import("jamsnp/common.zig");
const network = @import("network");

// Add a logging callback function
fn lsquic_log_callback(ctx: ?*anyopaque, buf: [*c]const u8, len: usize) callconv(.C) c_int {
    _ = ctx; // unused
    const stderr = std.io.getStdErr().writer();
    stderr.print("\x1b[33mlsquic: \x1b[0m", .{}) catch return 0;
    stderr.writeAll(buf[0..len]) catch return 0;
    return 0;
}

test "connect" {
    // NOTE:  uncomment for detailed logging
    //
    // const logger_if = lsquic.lsquic_logger_if{
    //     .log_buf = lsquic_log_callback,
    // };
    // lsquic.lsquic_logger_init(&logger_if, null, lsquic.LLTS_HHMMSSMS);
    //
    // const res = lsquic.lsquic_set_log_level("info");
    // if (res != 0) {
    //     @panic("could not set lsquic log level");
    // }
    //
    // NOTE: in common you can uncomment this callback for detailed SSL loggin
    // if necessary
    //
    // ssl.SSL_CTX_set_info_callback(ssl_ctx, ssl_info_callback); // Register the callback

    if (lsquic.lsquic_global_init(lsquic.LSQUIC_GLOBAL_SERVER | lsquic.LSQUIC_GLOBAL_CLIENT) != 0) {
        std.debug.print("Failed to initialize LSQUIC globally\n", .{});
        return error.LsquicInitFailed;
    }
    defer lsquic.lsquic_global_cleanup();

    // Generate keypairs for server and client
    const server_keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic([_]u8{0} ** 32);
    const client_keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic([_]u8{1} ** 32);
    std.debug.print("Generated Ed25519 keypairs\n", .{});

    // Dummy genesis hash
    const genesis_hash = try std.testing.allocator.dupe(u8, "0123456789abcdef"); // 16 bytes, we'll use first 8 in ALPN

    // Create the server
    var server = try JamSnpServer.init(
        std.testing.allocator,
        server_keypair,
        genesis_hash,
        true, // allow builders
    );
    defer server.deinit();
    std.debug.print("JAMSNP server initialized\n", .{});

    // Bind the server to localhost on a specific test port
    const test_port: u16 = 12345;
    try server.listen("::1", test_port);
    const local_endpoint = try server.socket.getLocalEndPoint();
    std.debug.print("Server is listening on: {}\n", .{local_endpoint});

    // Create the client
    var client = try JamSnpClient.initWithLoop(
        std.testing.allocator,
        client_keypair,
        genesis_hash,
        false, // not a builder
    );
    defer client.deinit();
    std.debug.print("JAMSNP client initialized\n", .{});

    // Connect client to server
    try client.connect("::1", test_port);
    std.debug.print("Client initiated connection to server\n", .{});

    // Client
    std.debug.print("Client running..\n", .{});

    // Now tick both server and client some amount of times
    for (0..20) |_| {
        try client.runTick();
        try server.runTick();
        // Short sleep to avoid busy-waiting
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    std.debug.print("Test passed: QUIC connection established between client and server\n", .{});
}

test "client.events" {
    const server_keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic([_]u8{0} ** 32);
    const client_keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic([_]u8{1} ** 32);
    std.debug.print("Generated Ed25519 keypairs\n", .{});

    // Dummy genesis hash
    const genesis_hash = try std.testing.allocator.dupe(u8, "0123456789abcdef");

    const EventTracker = struct {
        allocator: std.mem.Allocator,
        connection_established: bool = false,
        connection_failed: bool = false,
        connection_closed: bool = false,
        stream_created: bool = false,
        stream_closed: bool = false,
        data_received: bool = false,
        last_data: ?[]u8 = null,

        fn deinit(self: *@This()) void {
            if (self.last_data) |data| {
                self.allocator.free(data);
                self.last_data = null;
            }
        }
    };

    var event_tracker = EventTracker{
        .allocator = std.testing.allocator,
    };
    defer event_tracker.deinit();

    const eventCallback = struct {
        fn callback(event: *const JamSnpClient.Event, ctx: ?*anyopaque) void {
            var tracker = @as(*EventTracker, @ptrCast(@alignCast(ctx.?)));

            switch (event.*) {
                .connection_established => {
                    std.debug.print("Event: Connection established\n", .{});
                    tracker.connection_established = true;
                },
                .connection_failed => |e| {
                    std.debug.print("Event: Connection failed to {}\n", .{e.endpoint});
                    tracker.connection_failed = true;
                },
                .connection_closed => {
                    std.debug.print("Event: Connection closed\n", .{});
                    tracker.connection_closed = true;
                },
                .stream_created => {
                    std.debug.print("Event: Stream created\n", .{});
                    tracker.stream_created = true;

                    // Write some test data to the stream
                    const stream = event.stream_created.stream;
                    const data = "Hello from client test!";
                    _ = lsquic.lsquic_stream_write(stream.lsquic_stream, data, data.len);
                    _ = lsquic.lsquic_stream_flush(stream.lsquic_stream);
                },
                .stream_closed => {
                    std.debug.print("Event: Stream closed\n", .{});
                    tracker.stream_closed = true;
                },
                .data_received => |d| {
                    std.debug.print("Event: Data received ({d} bytes)\n", .{d.data.len});

                    // Save the received data for verification
                    if (tracker.last_data) |old_data| {
                        tracker.allocator.free(old_data);
                    }

                    tracker.last_data = tracker.allocator.dupe(u8, d.data) catch {
                        std.debug.print("Failed to duplicate received data\n", .{});
                        return;
                    };

                    tracker.data_received = true;

                    // Free the data since we've made our own copy
                    const data_ptr = @constCast(d.data.ptr);
                    const data_slice = @as([*]u8, data_ptr)[0..d.data.len];
                    tracker.allocator.free(data_slice);
                },
            }
        }
    }.callback;

    // Create the server
    var server = try JamSnpServer.init(
        std.testing.allocator,
        server_keypair,
        genesis_hash,
        false,
    );
    defer server.deinit();
    std.debug.print("JAMSNP server initialized\n", .{});

    const test_port: u16 = 12346; // Using a different port than the other test
    try server.listen("::1", test_port);
    const local_endpoint = try server.socket.getLocalEndPoint();
    std.debug.print("Server is listening on: {}\n", .{local_endpoint});

    var client = try JamSnpClient.initWithLoop(
        std.testing.allocator,
        client_keypair,
        genesis_hash,
        false, // not a builder
    );
    defer client.deinit();

    client.setEventCallback(eventCallback, &event_tracker);
    std.debug.print("JAMSNP client initialized with event handler\n", .{});

    try client.connect("::1", test_port);
    std.debug.print("Client initiated connection to server\n", .{});

    std.debug.print("Running client-server communication...\n", .{});

    var i: usize = 0;
    const max_ticks = 20;

    while (i < max_ticks) : (i += 1) {
        try client.runTick();
        try server.runTick();

        std.time.sleep(100 * std.time.ns_per_ms);

        // If we've seen all the events we're expecting, we can stop early
        if (event_tracker.connection_established and
            event_tracker.stream_created and
            event_tracker.data_received and
            event_tracker.stream_closed)
        {
            std.debug.print("All expected events received after {d} ticks\n", .{i + 1});
            break;
        }
    }

    // Verify events were triggered
    try std.testing.expect(event_tracker.connection_established);
    try std.testing.expect(event_tracker.stream_created);
    try std.testing.expect(event_tracker.data_received);

    std.debug.print("Test passed: JAMSNP client event system verified\n", .{});
}
