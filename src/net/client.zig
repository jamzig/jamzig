const std = @import("std");
const xev = @import("xev");

const JamSnpClient = @import("jamsnp/client.zig").JamSnpClient;
const types = @import("types.zig");
const ConnectionId = types.ConnectionId;
const StreamId = types.StreamId;

const Mailbox = @import("../datastruct/blocking_queue.zig").BlockingQueue;

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
        const Connect = struct {
            address: []const u8,
            port: u16,
        };

        const Disconnect = struct {
            connection_id: ConnectionId,
        };

        const CreateStream = struct {
            connection_id: ConnectionId,
        };

        const DestroyStream = struct {
            connection_id: ConnectionId,
            stream_id: StreamId,
        };

        const SendData = struct {
            connection_id: ConnectionId,
            stream_id: StreamId,
            data: []const u8,
        };

        connect: Connect,
        disconnect: Disconnect,
        create_stream: CreateStream,
        destroy_stream: DestroyStream,
        send_data: SendData,
        shutdown: void,
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
                .shutdown => try self.stop.notify(),
                .connect, .disconnect, .create_stream, .destroy_stream, .send_data => {
                    try self.processCommand(command);
                },
            }
        }
    }

    fn processCommand(self: *ClientThread, command: Command) !void {
        switch (command) {
            .connect => |connect_data| {
                try self.client.connect(connect_data.address, connect_data.port);

                // TODO: Get actual connection ID from JamSnpClient
                _ = self.event_queue.push(.{
                    .type = .connected,
                }, .{ .instant = {} });
            },
            .disconnect => |disconnect_data| {
                // TODO: Implement using JamSnpClient
                _ = self.event_queue.push(.{
                    .type = .disconnected,
                    .connection_id = disconnect_data.connection_id,
                }, .{ .instant = {} });
            },
            .create_stream => |create_stream_data| {
                // TODO: Implement using JamSnpClient
                const stream_id: StreamId = StreamId.fromRaw(1); // Placeholder

                _ = self.event_queue.push(.{
                    .type = .stream_created,
                    .connection_id = create_stream_data.connection_id,
                    .stream_id = stream_id,
                }, .{ .instant = {} });
            },
            .destroy_stream => |destroy_stream_data| {
                // TODO: Implement using JamSnpClient
                _ = self.event_queue.push(.{
                    .type = .stream_destroyed,
                    .connection_id = destroy_stream_data.connection_id,
                    .stream_id = destroy_stream_data.stream_id,
                }, .{ .instant = {} });
            },
            .send_data => |_| {
                // TODO: Implement using JamSnpClient
            },
            .shutdown => {},
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
        const command = ClientThread.Command{ .connect = .{
            .address = address,
            .port = port,
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn disconnect(self: *Client, connection_id: ConnectionId) !void {
        const command = ClientThread.Command{ .disconnect = .{
            .connection_id = connection_id,
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn createStream(self: *Client, connection_id: ConnectionId) !StreamHandle {
        const command = ClientThread.Command{ .create_stream = .{
            .connection_id = connection_id,
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();

        // TODO: Wait for response with actual stream ID
        return StreamHandle{
            .thread = self.thread,
            .stream_id = 0,
            .connection_id = connection_id,
        };
    }

    pub fn destroyStream(self: *Client, stream: StreamHandle) !void {
        const command = ClientThread.Command{ .destroy_stream = .{
            .connection_id = stream.connection_id,
            .stream_id = stream.stream_id,
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn shutdown(self: *const Client) !void {
        const command = ClientThread.Command{ .shutdown = {} };

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

// This is a handle to a stream which can be used to send data to an enpoint and it can
pub const StreamHandle = struct {
    thread: *ClientThread,
    stream_id: StreamId,
    connection_id: ConnectionId,

    pub fn sendData(self: *StreamHandle, data: []u8) !void {
        const command = ClientThread.Command{ .send_data = .{
            .connection_id = self.connection_id,
            .stream_id = self.stream_id,
            .data = data,
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }

    pub fn close(self: *StreamHandle) !void {
        const command = ClientThread.Command{ .destroy_stream = .{
            .connection_id = self.connection_id,
            .stream_id = self.stream_id,
        } };

        _ = self.thread.mailbox.push(command, .{ .instant = {} });
        try self.thread.wakeup.notify();
    }
};
