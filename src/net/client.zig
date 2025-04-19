//! Implementation of the ClientThread and Client. The design is
//! straightforward: the ClientThread is equipped with a mailbox capable of
//! receiving commands asynchronously. Upon execution of a command by the
//! JamSnpClient, an event is generated that associates the invocation with its
//! corresponding result.

const std = @import("std");
const xev = @import("xev");

const jamsnp_client = @import("jamsnp/client.zig");

const ConnectionId = jamsnp_client.ConnectionId;
const StreamId = jamsnp_client.StreamId;
const JamSnpClient = jamsnp_client.JamSnpClient;

const Mailbox = @import("../datastruct/blocking_queue.zig").BlockingQueue;

/// Callback type for command completion
pub fn CommandCallback(T: type) type {
    return *const fn (result: T, context: ?*anyopaque) void;
}

pub fn CommandMetadata(T: type) type {
    return struct {
        callback: ?CommandCallback(T) = null,
        context: ?*anyopaque = null,

        pub fn callWithResult(self: *const CommandMetadata(T), result: T) void {
            if (self.callback) |callback| {
                callback(result, self.context);
            }
        }
    };
}

pub const ClientThread = struct {
    alloc: std.mem.Allocator,
    client: *JamSnpClient,
    loop: xev.Loop,

    wakeup: xev.Async,
    wakeup_c: xev.Completion = .{},

    stop: xev.Async,
    stop_c: xev.Completion = .{},

    mailbox: *Mailbox(Command, 64),
    event_queue: *Mailbox(Client.Event, 64),

    pub const Command = union(enum) {
        pub const ConnectPayload = struct {
            const Data = struct {
                address: []const u8,
                port: u16,
            };

            data: Data,
            metadata: CommandMetadata(anyerror!ConnectionId),
        };

        pub const DisconnectPayload = struct {
            const Data = struct {
                connection_id: ConnectionId,
            };

            data: Data,
            metadata: CommandMetadata(void),
        };

        pub const CreateStreamPayload = struct {
            const Data = struct {
                connection_id: ConnectionId,
            };

            data: Data,
            metadata: CommandMetadata(void),
        };

        pub const DestroyStreamPayload = struct {
            const Data = struct {
                connection_id: ConnectionId,
                stream_id: StreamId,
            };

            data: Data,
            metadata: CommandMetadata(void),
        };

        pub const SendDataPayload = struct {
            const Data = struct {
                connection_id: ConnectionId,
                stream_id: StreamId,
                data: []const u8,
            };

            data: Data,
            metadata: CommandMetadata(void),
        };

        pub const StreamWantReadPayload = struct {
            const Data = struct {
                connection_id: ConnectionId,
                stream_id: StreamId,
                want: bool,
            };

            data: Data,
            metadata: CommandMetadata(void),
        };

        pub const StreamWantWritePayload = struct {
            const Data = struct {
                connection_id: ConnectionId,
                stream_id: StreamId,
                want: bool,
            };

            data: Data,
            metadata: CommandMetadata(void),
        };

        pub const StreamFlushPayload = struct {
            const Data = struct {
                connection_id: ConnectionId,
                stream_id: StreamId,
            };

            data: Data,
            metadata: CommandMetadata(void),
        };

        pub const StreamShutdownPayload = struct {
            const Data = struct {
                connection_id: ConnectionId,
                stream_id: StreamId,
                how: c_int,
            };

            data: Data,
            metadata: CommandMetadata(void),
        };

        pub const ShutdownPayload = struct {
            metadata: CommandMetadata(void),
        };

        connect: ConnectPayload,
        disconnect: DisconnectPayload,
        create_stream: CreateStreamPayload,
        destroy_stream: DestroyStreamPayload,
        send_data: SendDataPayload,
        stream_want_read: StreamWantReadPayload,
        stream_want_write: StreamWantWritePayload,
        stream_flush: StreamFlushPayload,
        stream_shutdown: StreamShutdownPayload,
        shutdown: ShutdownPayload,
    };

    pub fn initThread(alloc: std.mem.Allocator, client: *JamSnpClient) !*ClientThread {
        var thread = try alloc.create(ClientThread);
        errdefer alloc.destroy(thread);

        thread.loop = try xev.Loop.init(.{});
        errdefer thread.loop.deinit();

        thread.wakeup = try xev.Async.init();
        errdefer thread.wakeup.deinit();

        thread.stop = try xev.Async.init();
        errdefer thread.stop.deinit();

        thread.mailbox = try Mailbox(Command, 64).create(alloc);
        errdefer thread.mailbox.destroy(alloc);

        thread.event_queue = try Mailbox(Client.Event, 64).create(alloc);
        errdefer thread.event_queue.destroy(alloc);

        thread.alloc = alloc;

        if (client.loop) |_| {
            return error.ClientLoopAlreadyInitialized;
        }

        client.attachToLoop(&thread.loop);
        thread.client = client;

        return thread;
    }

    pub fn deinitThread(self: *ClientThread) void {
        self.event_queue.destroy(self.alloc);
        self.mailbox.destroy(self.alloc);
        self.stop.deinit();
        self.wakeup.deinit();
        self.loop.deinit();
        self.client.deinit();
        self.alloc.destroy(self);
    }

    pub fn threadMain(self: *ClientThread) void {
        // Handle errors gracefully
        self.threadMain_() catch |err| {
            std.log.warn("error in thread err={}", .{err});
        };
    }

    fn threadMain_(self: *ClientThread) !void {
        try self.threadSetup();
        defer self.threadCleanup();

        self.wakeup.wait(&self.loop, &self.wakeup_c, ClientThread, self, wakeupCallback);
        self.stop.wait(&self.loop, &self.stop_c, ClientThread, self, stopCallback);

        try self.wakeup.notify();
        _ = try self.loop.run(.until_done);
    }

    fn threadSetup(_: *ClientThread) !void {
        // Perform any thread-specific setup
    }

    fn threadCleanup(_: *ClientThread) void {
        // Perform any thread-specific cleanup
    }

    fn wakeupCallback(
        self_: ?*ClientThread,
        _: *xev.Loop,
        _: *xev.Completion,
        r: xev.Async.WaitError!void,
    ) xev.CallbackAction {
        _ = r catch |err| {
            std.log.err("error in wakeup err={}", .{err});
            return .rearm;
        };

        const thread = self_.?;

        thread.drainMailbox() catch |err| {
            std.log.err("error processing mailbox err={}", .{err});
        };

        return .rearm;
    }

    fn stopCallback(
        self_: ?*ClientThread,
        _: *xev.Loop,
        _: *xev.Completion,
        r: xev.Async.WaitError!void,
    ) xev.CallbackAction {
        _ = r catch unreachable;
        self_.?.loop.stop();
        return .disarm;
    }

    fn drainMailbox(self: *ClientThread) !void {
        while (self.mailbox.pop()) |command| {
            switch (command) {
                .shutdown => |cmd| {
                    // Notify callback before stopping
                    if (cmd.metadata.callback) |callback| {
                        callback({}, cmd.metadata.context);
                    }
                    try self.stop.notify();
                },
                else => {
                    try self.processCommand(command);
                },
            }
        }
    }

    fn processCommand(self: *ClientThread, command: Command) !void {
        switch (command) {
            .connect => |cmd| {
                _ = self.client.connect(cmd.data.address, cmd.data.port) catch |err| {
                    // Call the callback with error
                    cmd.metadata.callWithResult(err);
                    // FIXME: add the connection failed event
                };
            },
            .disconnect => |_| {
                // FIXME: add te disconnect call
            },
            .create_stream => |_| {
                // Find the connection by ID
                // For now, assuming we have a connection map
                // TODO: Implement actual connection lookup

                // Create the stream using JamSnpClient
                // TODO: Replace with actual implementation

            },
            .destroy_stream => |_| {
                // Find the stream by ID
                // TODO: Implement actual stream lookup

                // Close the stream
                // TODO: Implement actual stream closing
            },
            .send_data => |_| {
                // Find the stream by ID
                // TODO: Implement actual stream lookup

                // Write data to the stream
                // TODO: Implement actual data writing

            },
            .stream_want_read => |_| {
                // Find the stream by ID
                // TODO: Implement actual stream lookup

                // Set want-read on the stream
                // TODO: Implement actual want-read setting

            },
            .stream_want_write => |_| {
                // Find the stream by ID
                // TODO: Implement actual stream lookup

                // Set want-write on the stream
                // TODO: Implement actual want-write setting
            },
            .stream_flush => |_| {
                // Find the stream by ID
                // TODO: Implement actual stream lookup

                // Flush the stream
                // TODO: Implement actual stream flushing

            },
            .stream_shutdown => |_| {
                // Find the stream by ID
                // TODO: Implement actual stream lookup

                // Shutdown the stream
                // TODO: Implement actual stream shutdown

            },
            .shutdown => |_| {},
        }
    }

    pub fn wakeupThread(thread: *ClientThread) !void {
        _ = thread.mailbox.push(.{ .work_item = .{} }, .{ .instant = {} });
        try thread.wakeup.notify();
    }

    pub fn startThread(thread: *ClientThread) !std.Thread {
        return try std.Thread.spawn(.{}, ClientThread.threadMain, .{thread});
    }
};

// On each action here, a command will be pushed to the mailbox of the thread, and it will always result
pub const Client = struct {
    thread: *ClientThread,
    event_handler: ?EventHandler = null,

    const EventHandler = struct {
        callback: *const fn (*Event) void,
        context: ?*anyopaque,
    };

    pub const EventType = enum {
        connected,
        connection_failed,
        disconnected,
        stream_created,
        stream_destroyed,
        stream_readable,
        stream_writable,
        data_received,
        @"error",
    };

    pub const Event = struct {
        type: EventType,
        connection_id: ?ConnectionId = null,
        stream_id: ?StreamId = null,
        data: ?[]const u8 = null,
        error_code: ?u32 = null,
    };

    pub fn init(thread: *ClientThread) Client {
        return .{
            .thread = thread,
        };
    }

    // Connect to a remote endpoint
    pub fn connect(self: *Client, address: []const u8, port: u16) !void {
        return self.connectWithCallback(address, port, null, null);
    }

    // Connect with callback for completion notification
    pub fn connectWithCallback(
        self: *Client,
        address: []const u8,
        port: u16,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .connect = .{
            .data = .{
                .address = address,
                .port = port,
            },
            .metadata = .{
                .callback = callback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn disconnect(self: *Client, connection_id: ConnectionId) !void {
        return self.disconnectWithCallback(connection_id, null, null);
    }

    pub fn disconnectWithCallback(
        self: *Client,
        connection_id: ConnectionId,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .disconnect = .{
            .data = .{
                .connection_id = connection_id,
            },
            .metadata = .{
                .callback = callback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn createStream(self: *Client, stream: StreamHandle) !void {
        return self.destroyStreamWithCallback(stream, null, null);
    }

    pub fn createStreamWithCallback(
        self: *Client,
        connection_id: ConnectionId,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .create_stream = .{
            .data = .{
                .connection_id = connection_id,
            },
            .metadata = .{
                .callback = callback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn destroyStream(self: *Client, stream: StreamHandle) !void {
        return self.destroyStreamWithCallback(stream, null, null);
    }

    pub fn destroyStreamWithCallback(
        self: *Client,
        stream: StreamHandle,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .destroy_stream = .{
            .data = .{
                .connection_id = stream.connection_id,
                .stream_id = stream.stream_id,
            },
            .metadata = .{
                .callback = callback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn shutdown(self: *const Client) !void {
        return self.shutdownWithCallback(null, null);
    }

    pub fn shutdownWithCallback(
        self: *const Client,
        callback: ?CommandCallback(void),
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .shutdown = .{
            .metadata = .{
                .callback = callback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn events(_: *Client) ?Event {
        // TODO: Retrieve events from queue
        return null;
    }

    pub fn setOnNewEventsCallback(self: *Client, callback: *const fn (*Event) void, context: ?*anyopaque) void {
        self.event_handler = .{
            .callback = callback,
            .context = context,
        };
    }
};

//
pub const StreamHandle = struct {
    thread: *ClientThread,
    stream_id: StreamId,
    connection_id: ConnectionId,
    is_readable: bool = false,
    is_writable: bool = false,

    pub fn sendData(self: *StreamHandle, data: []u8) !void {
        return self.sendDataWithCallback(data, null, null);
    }

    pub fn sendDataWithCallback(
        self: *StreamHandle,
        data: []u8,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .send_data = .{
            .data = .{
                .connection_id = self.connection_id,
                .stream_id = self.stream_id,
                .data = data,
            },
            .metadata = .{
                .callback = callback orelse Client.defaultCallback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn wantRead(self: *StreamHandle, want: bool) !void {
        return self.wantReadWithCallback(want, null, null);
    }

    pub fn wantReadWithCallback(
        self: *StreamHandle,
        want: bool,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .stream_want_read = .{
            .data = .{
                .connection_id = self.connection_id,
                .stream_id = self.stream_id,
                .want = want,
            },
            .metadata = .{
                .callback = callback orelse Client.defaultCallback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn wantWrite(self: *StreamHandle, want: bool) !void {
        return self.wantWriteWithCallback(want, null, null);
    }

    pub fn wantWriteWithCallback(
        self: *StreamHandle,
        want: bool,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .stream_want_write = .{
            .data = .{
                .connection_id = self.connection_id,
                .stream_id = self.stream_id,
                .want = want,
            },
            .metadata = .{
                .callback = callback orelse Client.defaultCallback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn flush(self: *StreamHandle) !void {
        return self.flushWithCallback(null, null);
    }

    pub fn flushWithCallback(
        self: *StreamHandle,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .stream_flush = .{
            .data = .{
                .connection_id = self.connection_id,
                .stream_id = self.stream_id,
            },
            .metadata = .{
                .callback = callback orelse Client.defaultCallback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn shutdown(self: *StreamHandle, how: c_int) !void {
        return self.shutdownWithCallback(how, null, null);
    }

    pub fn shutdownWithCallback(
        self: *StreamHandle,
        how: c_int,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .stream_shutdown = .{
            .data = .{
                .connection_id = self.connection_id,
                .stream_id = self.stream_id,
                .how = how,
            },
            .metadata = .{
                .callback = callback orelse Client.defaultCallback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn close(self: *StreamHandle) !void {
        return self.closeWithCallback(null, null);
    }

    pub fn closeWithCallback(
        self: *StreamHandle,
        callback: ?CommandCallback,
        context: ?*anyopaque,
    ) !void {
        const command = ClientThread.Command{ .destroy_stream = .{
            .data = .{
                .connection_id = self.connection_id,
                .stream_id = self.stream_id,
            },
            .metadata = .{
                .callback = callback orelse Client.defaultCallback,
                .context = context,
            },
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }
};
