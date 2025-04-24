const std = @import("std");
const uuid = @import("uuid");
const network = @import("network");

const trace = @import("../../tracing.zig").scoped(.network);

pub const ConnectionId = uuid.Uuid;
pub const StreamId = uuid.Uuid;

/// Stream kinds defined in the JAM Simple Networking Protocol (JAMSNP-S)
/// UP streams are Unique Persistent, CE streams are Common Ephemeral.
/// UP stream kinds start from 0, CE stream kinds start from 128.
pub const StreamKind = enum(u8) {
    /// UP 0: Block announcement
    /// Opened between validator neighbors or if one node is not a validator
    /// Initiator sends Handshake, both exchange Announcements
    block_announcement = 0,

    // --- Common Ephemeral (CE) Streams start from 128 ---

    /// CE 128: Block request.
    /// Request a sequence of blocks, ascending or descending.
    block_request = 128,

    /// CE 129: State request.
    /// Request a range of a block's posterior state trie.
    state_request = 129,

    // CE 130 is skipped/unassigned in the provided document.

    /// CE 131: Safrole ticket distribution (Validator to Proxy).
    /// First step in ticket distribution.
    safrole_ticket_distribution_to_proxy = 131,

    /// CE 132: Safrole ticket distribution (Proxy to All).
    /// Second step in ticket distribution.
    safrole_ticket_distribution_from_proxy = 132,

    /// CE 133: Work-package submission.
    /// Builder submits work-package to Guarantor.
    work_package_submission = 133,

    /// CE 134: Work-package sharing.
    /// Guarantor shares work-package with other assigned Guarantors.
    work_package_sharing = 134,

    /// CE 135: Work-report distribution.
    /// Guarantor distributes guaranteed work-report to Validators.
    work_report_distribution = 135,

    /// CE 136: Work-report request.
    /// Node requests a work-report by hash.
    work_report_request = 136,

    /// CE 137: Shard distribution.
    /// Assurer requests EC shards from Guarantor.
    shard_distribution = 137,

    /// CE 138: Audit shard request.
    /// Auditor requests work-package bundle shard from Assurer.
    audit_shard_request = 138,

    /// CE 139: Segment shard request (no justification).
    /// Guarantor requests import segment shards from Assurer.
    segment_shard_request_no_justification = 139,

    /// CE 140: Segment shard request (with justification).
    /// Guarantor requests import segment shards with justification from Assurer.
    segment_shard_request_with_justification = 140,

    /// CE 141: Assurance distribution.
    /// Assurer distributes availability assurance to potential block authors.
    assurance_distribution = 141,

    /// CE 142: Preimage announcement.
    /// Non-validator node announces possession of a requested preimage.
    preimage_announcement = 142,

    /// CE 143: Preimage request.
    /// Node requests a preimage by hash.
    preimage_request = 143,

    /// CE 144: Audit announcement.
    /// Auditor announces intent to audit specific work-reports.
    audit_announcement = 144,

    /// CE 145: Judgment publication.
    /// Auditor announces judgment (valid/invalid) for a work-report.
    judgment_publication = 145,

    // Add any future stream kinds here...

    /// Helper function to determine if a stream kind is Unique Persistent (UP).
    pub fn isUniquePersistent(self: StreamKind) bool {
        return @intFromEnum(self) < 128;
    }

    /// Helper function to determine if a stream kind is Common Ephemeral (CE).
    pub fn isCommonEphemeral(self: StreamKind) bool {
        return @intFromEnum(self) >= 128;
    }

    /// Tries to convert a raw u8 value to a StreamKind. Returns error.invalid if the value is not defined.
    pub fn fromRaw(raw_value: u8) !StreamKind {
        return std.meta.intToEnum(StreamKind, raw_value);
    }
};

// -- Client Callback Types
pub const EventType = enum {
    ClientConnected,
    ConnectionEstablished,
    ConnectionFailed,
    ConnectionClosed,
    StreamCreated,
    ServerStreamCreated,
    StreamClosed,
    DataReceived,
    DataEndOfStream,
    DataReadError,
    DataWouldBlock,
    DataWriteProgress,
    DataWriteCompleted,
    DataWriteError,
};

pub const ClientConnectedCallbackFn = *const fn (connection: ConnectionId, endpoint: network.EndPoint, context: ?*anyopaque) void;
pub const ConnectionEstablishedCallbackFn = *const fn (connection: ConnectionId, endpoint: network.EndPoint, context: ?*anyopaque) void;
pub const ConnectionFailedCallbackFn = *const fn (connection: ConnectionId, endpoint: network.EndPoint, err: anyerror, context: ?*anyopaque) void;
pub const ConnectionClosedCallbackFn = *const fn (connection: ConnectionId, context: ?*anyopaque) void;
pub const StreamCreatedCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, context: ?*anyopaque) void;
pub const ServerStreamCreatedCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, kind: StreamKind, context: ?*anyopaque) void;
pub const StreamClosedCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, context: ?*anyopaque) void;
pub const DataReceivedCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, data: []const u8, context: ?*anyopaque) void;
pub const DataEndOfStreamCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, data_read: []const u8, context: ?*anyopaque) void;
pub const DataErrorCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, error_code: i32, context: ?*anyopaque) void;
pub const DataWouldBlockCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, context: ?*anyopaque) void;
pub const DataWriteProgressCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, bytes_written: usize, total_size: usize, context: ?*anyopaque) void;
pub const DataWriteCompletedCallbackFn = *const fn (connection: ConnectionId, stream: StreamId, total_bytes_written: usize, context: ?*anyopaque) void;

// -- Common Callback Handler
pub const CallbackHandler = struct {
    callback: ?*const anyopaque,
    context: ?*anyopaque,
};

// -- Callback Invocation

pub const CallbackHandlers = [@typeInfo(EventType).@"enum".fields.len]CallbackHandler;
pub const CALLBACK_HANDLERS_EMPTY = [_]CallbackHandler{.{ .callback = null, .context = null }} ** @typeInfo(EventType).@"enum".fields.len;

// Argument Union for invokeCallback (using shared types)
const EventArgs = union(EventType) {
    ClientConnected: struct { connection: ConnectionId, endpoint: network.EndPoint },
    ConnectionEstablished: struct { connection: ConnectionId, endpoint: network.EndPoint },
    ConnectionFailed: struct { endpoint: network.EndPoint, err: anyerror },
    ConnectionClosed: struct { connection: ConnectionId },
    StreamCreated: struct { connection: ConnectionId, stream: StreamId },
    ServerStreamCreated: struct { connection: ConnectionId, stream: StreamId, kind: StreamKind },
    StreamClosed: struct { connection: ConnectionId, stream: StreamId },
    DataReceived: struct { connection: ConnectionId, stream: StreamId, data: []const u8 },
    DataEndOfStream: struct { connection: ConnectionId, stream: StreamId, data_read: []const u8 },
    DataReadError: struct { connection: ConnectionId, stream: StreamId, error_code: i32 },
    DataWouldBlock: struct { connection: ConnectionId, stream: StreamId },
    DataWriteProgress: struct { connection: ConnectionId, stream: StreamId, bytes_written: usize, total_size: usize },
    DataWriteCompleted: struct { connection: ConnectionId, stream: StreamId, total_bytes_written: usize },
    DataWriteError: struct { connection: ConnectionId, stream: StreamId, error_code: i32 },
};

pub fn invokeCallback(callback_handlers: *const CallbackHandlers, event_tag: EventType, args: EventArgs) void {
    const span = trace.span(.invoke_callback);
    defer span.deinit();
    std.debug.assert(event_tag == @as(EventType, @enumFromInt(@intFromEnum(args))));

    const handler = &callback_handlers[@intFromEnum(event_tag)];
    if (handler.callback) |callback_ptr| {
        span.debug("Invoking callback for event {s}", .{@tagName(event_tag)});
        switch (args) {
            .ClientConnected => |ev_args| {
                const callback: ClientConnectedCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.endpoint, handler.context);
            },
            .ConnectionEstablished => |ev_args| {
                const callback: ClientConnectedCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.endpoint, handler.context);
            },
            .ConnectionClosed => |ev_args| {
                const callback: ConnectionClosedCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, handler.context);
            },
            .StreamCreated => |ev_args| {
                const callback: StreamCreatedCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, handler.context);
            },
            .ServerStreamCreated => |ev_args| {
                const callback: ServerStreamCreatedCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, ev_args.kind, handler.context);
            },
            .StreamClosed => |ev_args| {
                const callback: StreamClosedCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, handler.context);
            },
            .DataReceived => |ev_args| {
                const callback: DataReceivedCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, ev_args.data, handler.context);
            },
            .DataWriteCompleted => |ev_args| {
                const callback: DataWriteCompletedCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, ev_args.total_bytes_written, handler.context);
            },
            .DataReadError => |ev_args| {
                const callback: DataErrorCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, ev_args.error_code, handler.context);
            },
            .DataWriteError => |ev_args| {
                const callback: DataErrorCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, ev_args.error_code, handler.context);
            },
            .DataWouldBlock => |ev_args| {
                const callback: DataWouldBlockCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, handler.context);
            },
            .DataWriteProgress => |ev_args| {
                const callback: DataWriteProgressCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, ev_args.bytes_written, ev_args.total_size, handler.context);
            },
            .DataEndOfStream => |ev_args| {
                const callback: DataEndOfStreamCallbackFn = @ptrCast(@alignCast(callback_ptr));
                callback(ev_args.connection, ev_args.stream, ev_args.data_read, handler.context);
            },
            .ConnectionFailed => |ev_args| {
                // This seems to be server-specific, not used in client callbacks
                span.warn("Unhandled ConnectionFailed event for endpoint: {}", .{ev_args.endpoint});
            },
        }
    } else {
        span.trace("No server callback registered for event type {s}", .{@tagName(event_tag)});
    }
}
