const std = @import("std");
const lsquic = @import("lsquic");
const ssl = @import("ssl");
const common = @import("common.zig");
const certificate_verifier = @import("certificate_verifier.zig");
const constants = @import("constants.zig");
const UdpSocket = @import("../udp_socket.zig").UdpSocket;
const xev = @import("xev");

pub const JamSnpClient = struct {
    allocator: std.mem.Allocator,
    keypair: std.crypto.sign.Ed25519.KeyPair,
    socket: UdpSocket,

    packets_in_event: xev.UDP,
    tick_event: xev.Timer,

    lsquic_engine: *lsquic.lsquic_engine,
    lsquic_engine_api: lsquic.lsquic_engine_api,
    lsquic_engine_settings: lsquic.lsquic_engine_settings,
    lsquic_stream_iterface: lsquic.lsquic_stream_if = .{
        // Mandatory callbacks
        .on_new_conn = Connection.onNewConn,
        .on_conn_closed = Connection.onConnClosed,
        .on_new_stream = Stream.onNewStream,
        .on_read = Stream.onRead,
        .on_write = Stream.onWrite,
        .on_close = Stream.onClose,
        // Optional callbacks
        // .on_goaway_received = Connection.onGoawayReceived,
        // .on_dg_write = onDbWrite,
        // .on_datagram = onDatagram,
        // .on_hsk_done = Connection.onHskDone,
        // .on_new_token = onNewToken,
        // .on_sess_resume_info = onSessResumeInfo,
        // .on_reset = onReset,
        // .on_conncloseframe_received = Connection.onConnCloseFrameReceived,
    },

    ssl_ctx: *ssl.SSL_CTX,
    chain_genesis_hash: []const u8,
    is_builder: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        keypair: std.crypto.sign.Ed25519.KeyPair,
        chain_genesis_hash: []const u8,
        is_builder: bool,
    ) !*JamSnpClient {
        // Initialize lsquic globally (if not already initialized)
        if (lsquic.lsquic_global_init(lsquic.LSQUIC_GLOBAL_CLIENT) != 0) {
            return error.LsquicInitFailed;
        }

        // Create UDP socket
        var socket = try UdpSocket.init();
        errdefer socket.deinit();

        // Configure SSL context
        const ssl_ctx = try common.configureSSLContext(
            keypair,
            chain_genesis_hash,
            true, // is_client
            is_builder,
        );
        errdefer ssl.SSL_CTX_free(ssl_ctx);

        // Set up certificate verification
        ssl.SSL_CTX_set_cert_verify_callback(ssl_ctx, certificate_verifier.verifyCertificate, null);

        // Initialize lsquic engine settings
        var engine_settings: lsquic.lsquic_engine_settings = .{};
        lsquic.lsquic_engine_init_settings(&engine_settings, 0);
        engine_settings.es_versions = 1 << lsquic.LSQVER_ID29; // IETF QUIC v1

        // Create ALPN identifier
        var alpn_buffer: [64:0]u8 = undefined;
        var alpn_id = try common.buildAlpnIdentifier(&alpn_buffer, chain_genesis_hash, is_builder);

        // Since lsquic references these settings
        // we need this to be on the heap with a lifetime which outlasts the
        // engine
        const client = try allocator.create(JamSnpClient);
        client.* = JamSnpClient{
            .allocator = allocator,
            .keypair = keypair,
            .socket = socket,
            .lsquic_engine = undefined,
            .lsquic_engine_settings = engine_settings,
            .lsquic_engine_api = .{
                .ea_settings = &engine_settings,
                .ea_stream_if = &client.lsquic_stream_iterface,
                .ea_stream_if_ctx = null, // Will be set later
                .ea_packets_out = &sendPacketsOut,
                .ea_packets_out_ctx = null, // Will be et later
                .ea_get_ssl_ctx = &getSslContext,
                .ea_lookup_cert = null,
                .ea_cert_lu_ctx = null,
                .ea_alpn = @ptrCast(&alpn_id), // FIXME: we should own this memory
            },
            .ssl_ctx = ssl_ctx,
            .chain_genesis_hash = try allocator.dupe(u8, chain_genesis_hash),
            .is_builder = is_builder,
            // TODO:
            .packets_in_event = xev.UDP.initFd(socket.socket),
            .tick_event = try xev.Timer.init(),
        };

        client.lsquic_engine_api.ea_packets_out_ctx = &client.socket;

        // Create lsquic engine
        client.*.lsquic_engine = lsquic.lsquic_engine_new(0, &client.*.lsquic_engine_api) orelse {
            return error.LsquicEngineCreationFailed;
        };

        return client;
    }

    pub fn run(self: *@This()) !void {
        var loop = try xev.Loop.init(.{});
        defer loop.deinit();

        // Trigger first timer at 500ms setting the ticker in motion
        var tick_complete: xev.Completion = undefined;
        self.tick_event.run(&loop, &tick_complete, 500, @This(), self, onTick);

        var packets_in_complete: xev.Completion = undefined;

        // 1500 is the interface's MTU, so we'll never receive more bytes than that
        // from UDP.
        const read_buffer = try self.allocator.alloc(u8, 1500);
        defer self.allocator.free(read_buffer);

        var state: xev.UDP.State = undefined;
        self.packets_in_event.read(
            &loop,
            &packets_in_complete,
            &state,
            .{ .slice = read_buffer },
            @This(),
            self,
            onPacketsIn,
        );

        try loop.run(.until_done);
    }

    fn onTick(
        maybe_self: ?*@This(),
        xev_loop: *xev.Loop,
        xev_completion: *xev.Completion,
        xev_timer_error: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        errdefer |err| std.debug.panic("onTick failed with: {s}", .{@errorName(err)});
        try xev_timer_error;

        const self = maybe_self.?;

        lsquic.lsquic_engine_process_conns(self.lsquic_engine);

        // Delta is in 1/1_000_000 so we divide by 100 to get ms
        var delta: c_int = undefined;

        var timeout_in_ms: u64 = 100;
        if (lsquic.lsquic_engine_earliest_adv_tick(self.lsquic_engine, &delta) != 0) {
            if (delta > 0) {
                timeout_in_ms = @intCast(@divTrunc(delta, 1000));
            }
        }

        self.tick_event.run(xev_loop, xev_completion, timeout_in_ms, @This(), self, onTick);

        return .disarm;
    }

    fn onPacketsIn(
        maybe_self: ?*@This(),
        _: *xev.Loop,
        _: *xev.Completion,
        _: *xev.UDP.State,
        peer_address: std.net.Address,
        _: xev.UDP,
        xev_read_buffer: xev.ReadBuffer,
        xev_read_error: xev.ReadError!usize,
    ) xev.CallbackAction {
        errdefer |err| std.debug.panic("onPacketsIn failed with: {s}", .{@errorName(err)});

        const bytes = try xev_read_error;

        const self = maybe_self.?;

        const local_address = try self.socket.getLocalAddress();

        if (0 > lsquic.lsquic_engine_packet_in(
            self.lsquic_engine,
            xev_read_buffer.slice.ptr,
            bytes,
            @ptrCast(&local_address.any),
            @ptrCast(&peer_address.any),
            self,
            0,
        )) {
            @panic("lsquic_engine_packet_in failed");
        }

        return .rearm;
    }

    pub fn deinit(self: *JamSnpClient) void {
        lsquic.lsquic_engine_destroy(self.lsquic_engine);
        ssl.SSL_CTX_free(self.ssl_ctx);
        self.socket.deinit();
        self.allocator.free(self.chain_genesis_hash);
        // Global cleanup should be done at program exit
        self.allocator.destroy(self);
    }

    pub fn connect(self: *JamSnpClient, peer_addr: []const u8, peer_port: u16) !void {
        // Bind to a local address (use any address)
        try self.socket.bind("::1", 0);

        // Get the local socket address after binding
        const local_endpoint = try self.socket.getLocalAddress();

        // Parse peer address
        const peer_endpoint = try std.net.Address.parseIp(peer_addr, peer_port);

        // Create a connection
        const connection = try self.allocator.create(Connection);
        connection.* = .{
            .lsquic_connection = undefined,
            .client = self,
            .endpoint = peer_endpoint,
        };

        // Create QUIC connection
        _ = lsquic.lsquic_engine_connect(
            self.lsquic_engine,
            lsquic.N_LSQVER, // Use default version
            @ptrCast(&local_endpoint.any),
            @ptrCast(&peer_endpoint.any),
            self.ssl_ctx, // peer_ctx
            @ptrCast(connection), // conn_ctx
            null, // hostname for SNI
            0, // base_plpmtu - use default
            null,
            0, // session resumption
            null,
            0, // token
        ) orelse {
            return error.ConnectionFailed;
        };

        // Process connection establishment
        // lsquic.lsquic_engine_process_conns(self.lsquic_engine);
    }

    pub const Connection = struct {
        lsquic_connection: *lsquic.lsquic_conn_t,
        endpoint: std.net.Address,
        client: *JamSnpClient,

        fn onNewConn(
            _: ?*anyopaque,
            maybe_lsquic_connection: ?*lsquic.lsquic_conn_t,
        ) callconv(.C) *lsquic.lsquic_conn_ctx_t {
            const conn_ctx = lsquic.lsquic_conn_get_ctx(maybe_lsquic_connection).?;
            const self: *Connection = @alignCast(@ptrCast(conn_ctx));

            self.lsquic_connection = maybe_lsquic_connection.?;

            return @ptrCast(self);
        }

        fn onConnClosed(maybe_lsquic_connection: ?*lsquic.lsquic_conn_t) callconv(.C) void {
            const conn_ctx = lsquic.lsquic_conn_get_ctx(maybe_lsquic_connection).?;
            const conn: *Connection = @alignCast(@ptrCast(conn_ctx));

            lsquic.lsquic_conn_set_ctx(maybe_lsquic_connection, null);
            conn.client.allocator.destroy(conn);
        }
    };

    /// Handle incoming packets
    pub fn processPacket(self: *JamSnpClient, packet: []const u8, peer_addr: std.posix.sockaddr, local_addr: std.posix.sockaddr) !void {
        const result = lsquic.lsquic_engine_packet_in(
            self.lsquic_engine,
            packet.ptr,
            packet.len,
            &local_addr,
            &peer_addr,
            self, // peer_ctx
            0, // ecn
        );

        if (result < 0) {
            return error.PacketProcessingFailed;
        }

        // Process connection after receiving packet
        lsquic.lsquic_engine_process_conns(self.lsquic_engine);
    }

    fn getStreamInterface() lsquic.lsquic_stream_if {
        return .{
            // Mandatory callbacks
            .on_new_conn = Connection.onNewConn,
            .on_conn_closed = Connection.onConnClosed,
            .on_new_stream = Stream.onNewStream,
            .on_read = Stream.onRead,
            .on_write = Stream.onWrite,
            .on_close = Stream.onClose,
            // Optional callbacks
            // .on_hsk_done = null,
            // .on_goaway_received = null,
            // .on_new_token = null,
            // .on_sess_resume_info = null,
        };
    }

    const Stream = struct {
        lsquic_stream: *lsquic.lsquic_stream_t,
        connection: *Connection,

        fn onNewStream(
            _: ?*anyopaque,
            maybe_lsquic_stream: ?*lsquic.lsquic_stream_t,
        ) callconv(.C) *lsquic.lsquic_stream_ctx_t {
            const lsquic_connection = lsquic.lsquic_stream_conn(maybe_lsquic_stream);
            const conn_ctx = lsquic.lsquic_conn_get_ctx(lsquic_connection).?;
            const connection: *Connection = @alignCast(@ptrCast(conn_ctx));

            const stream = connection.client.allocator.create(Stream) catch
                @panic("OutOfMemory");
            stream.* = .{
                .lsquic_stream = maybe_lsquic_stream.?,
                .connection = connection,
            };

            _ = lsquic.lsquic_stream_wantwrite(maybe_lsquic_stream, 1);
            return @ptrCast(stream);
        }

        fn onRead(
            _: ?*lsquic.lsquic_stream_t,
            _: ?*lsquic.lsquic_stream_ctx_t,
        ) callconv(.C) void {
            @panic("uni-directional streams should never receive data");
        }

        fn onWrite(
            maybe_lsquic_stream: ?*lsquic.lsquic_stream_t,
            maybe_stream: ?*lsquic.lsquic_stream_ctx_t,
        ) callconv(.C) void {
            const stream: *Stream = @alignCast(@ptrCast(maybe_stream.?));

            _ = stream;

            // if (stream.packet.size != lsquic.lsquic_stream_write(
            //     maybe_lsquic_stream,
            //     &stream.packet.data,
            //     stream.packet.size,
            // )) {
            //     @panic("failed to write complete packet to stream");
            // }

            _ = lsquic.lsquic_stream_flush(maybe_lsquic_stream);
            _ = lsquic.lsquic_stream_wantwrite(maybe_lsquic_stream, 0);
            _ = lsquic.lsquic_stream_close(maybe_lsquic_stream);
        }

        fn onClose(
            _: ?*lsquic.lsquic_stream_t,
            maybe_stream: ?*lsquic.lsquic_stream_ctx_t,
        ) callconv(.C) void {
            const stream: *Stream = @alignCast(@ptrCast(maybe_stream.?));
            stream.connection.client.allocator.destroy(stream);
        }
    };

    fn getSslContext(peer_ctx: ?*anyopaque, _: ?*const lsquic.struct_sockaddr) callconv(.C) ?*lsquic.struct_ssl_ctx_st {
        return @ptrCast(peer_ctx.?);
    }

    fn sendPacketsOut(
        ctx: ?*anyopaque,
        specs_ptr: ?[*]const lsquic.lsquic_out_spec,
        specs_len: c_uint,
    ) callconv(.C) c_int {
        const socket = @as(*UdpSocket, @ptrCast(@alignCast(ctx)));

        const specs = specs_ptr.?[0..specs_len];

        var send_packets: c_int = 0;
        for (specs) |spec| {
            const iov = spec.iov[0..spec.iovlen];

            // Send the packet
            for (iov) |iovec| {
                const buf_ptr: [*]const u8 = @ptrCast(iovec.iov_base);
                const buf_len: usize = @intCast(iovec.iov_len);
                const buffer = buf_ptr[0..buf_len];
                _ = socket.sendToSockAddr(buffer, @ptrCast(@alignCast(spec.dest_sa))) catch break;
            }
            send_packets += 1;
        }

        return send_packets;
    }
};
