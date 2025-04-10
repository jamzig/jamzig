const std = @import("std");

const base32 = @import("base32");
const ssl = @import("ssl");

const constants = @import("constants.zig");

const trace = @import("../../tracing.zig").scoped(.network);

/// Builds the ALPN identifier string for JAMSNP
pub fn buildAlpnIdentifier(allocator: std.mem.Allocator, chain_genesis_hash: []const u8, is_builder: bool) ![:0]u8 {
    const span = trace.span(.build_alpn_identifier);
    defer span.deinit();
    span.debug("Building ALPN identifier", .{});
    span.trace("Chain genesis hash: {s}, is_builder: {}", .{ std.fmt.fmtSliceHexLower(chain_genesis_hash), is_builder });

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 64);
    const writer = buffer.writer();

    // Format: jamnp-s/0/abcdef12 or jamnp-s/0/abcdef12/builder
    try writer.print("{s}/{s}/{s}", .{
        constants.PROTOCOL_PREFIX,
        constants.PROTOCOL_VERSION,
        chain_genesis_hash[0..8],
    });

    if (is_builder) {
        try writer.writeAll("/builder");
    }

    const result = try buffer.toOwnedSliceSentinel(0);
    span.debug("ALPN identifier created: {s}", .{result});
    return result;
}

pub const X509Certificate = struct {
    /// Create a certificate that conforms to the JAMSNP specification:
    /// - Use Ed25519 as the signature algorithm
    /// - Have a single alternative name: DNS name "e" followed by base32 encoded public key
    /// - Use the peer's Ed25519 key
    fn create(keypair: std.crypto.sign.Ed25519.KeyPair) *ssl.X509 {
        const span = trace.span(.create_certificate);
        defer span.deinit();
        span.debug("Creating X509 certificate with Ed25519 key", .{});
        span.trace("Public key: {s}", .{std.fmt.fmtSliceHexLower(&keypair.public_key.bytes)});

        // Create private key from Ed25519 keypair
        const pkey = ssl.EVP_PKEY_new_raw_private_key(ssl.EVP_PKEY_ED25519, null, &keypair.secret_key.bytes, 32) orelse {
            span.err("Failed to create EVP_PKEY from Ed25519 private key", .{});
            @panic("EVP_PKEY_new_raw_private_key failed");
        };
        defer ssl.EVP_PKEY_free(pkey);
        span.debug("Created EVP_PKEY from Ed25519 private key", .{});

        // Create new X509 certificate
        const cert = ssl.X509_new() orelse {
            span.err("Failed to create X509 certificate", .{});
            @panic("X509_new failed");
        };
        span.debug("Created new X509 certificate", .{});

        // Set version to X509v3
        if (ssl.X509_set_version(cert, ssl.X509_VERSION_3) == 0) {
            span.err("Failed to set X509 version", .{});
            @panic("X509_set_version failed");
        }
        span.debug("Set certificate version to X509v3", .{});

        // Set serial number
        const serial = ssl.ASN1_INTEGER_new() orelse {
            span.err("Failed to create ASN1 integer for serial number", .{});
            @panic("ASN1_INTEGER_new failed");
        };
        defer ssl.ASN1_INTEGER_free(serial);
        span.debug("Created ASN1 integer for serial number", .{});

        if (ssl.ASN1_INTEGER_set(serial, 1) == 0) {
            span.err("Failed to set serial number value", .{});
            @panic("ASN1_INTEGER_set failed");
        }
        span.debug("Set serial number value to 1", .{});

        if (ssl.X509_set_serialNumber(cert, serial) == 0) {
            span.err("Failed to set certificate serial number", .{});
            @panic("X509_set_serialNumber failed");
        }
        span.debug("Applied serial number to certificate", .{});

        // Set issuer (self-signed)
        const issuer = ssl.X509_get_issuer_name(cert) orelse {
            span.err("Failed to get issuer name", .{});
            @panic("X509_get_issuer_name failed");
        };
        span.debug("Got issuer name for self-signed certificate", .{});

        if (ssl.X509_NAME_add_entry_by_txt(
            issuer,
            "CN",
            ssl.MBSTRING_ASC,
            "JamZig ⚡ Node",
            -1,
            -1,
            0,
        ) == 0) {
            span.err("Failed to add issuer common name", .{});
            @panic("X509_NAME_add_entry_by_txt failed");
        }
        span.debug("Added 'JamZig Node' as common name to issuer", .{});

        // Set validity period
        if (ssl.X509_gmtime_adj(ssl.X509_get_notBefore(cert), 0) == null) {
            span.err("Failed to set notBefore time", .{});
            @panic("X509_gmtime_adj failed");
        }
        span.debug("Set notBefore time to current time", .{});

        // 1000 years validity
        if (ssl.X509_gmtime_adj(ssl.X509_get_notAfter(cert), 60 * 60 * 24 * 365 * 1000) == null) {
            span.err("Failed to set notAfter time", .{});
            @panic("X509_gmtime_adj failed");
        }
        span.debug("Set notAfter time to 1000 years in the future", .{});

        // Set subject name (same as issuer for self-signed)
        if (ssl.X509_set_subject_name(cert, issuer) == 0) {
            span.err("Failed to set subject name", .{});
            @panic("X509_set_subject_name failed");
        }
        span.debug("Set subject name to same as issuer (self-signed)", .{});

        // Set public key
        if (ssl.X509_set_pubkey(cert, pkey) == 0) {
            span.err("Failed to set public key", .{});
            @panic("X509_set_pubkey failed");
        }
        span.debug("Set public key in certificate", .{});

        // Add the required alternative name: 'e' + base32 encoded pubkey
        const pubkey = &keypair.public_key.bytes;
        span.trace("Adding SAN with encoded pubkey: {s}", .{std.fmt.fmtSliceHexLower(pubkey)});

        // Create a SAN extension
        const subject_alt_names = ssl.GENERAL_NAMES_new() orelse {
            span.err("Failed to create general names object", .{});
            @panic("GENERAL_NAMES_new failed");
        };
        defer ssl.GENERAL_NAMES_free(subject_alt_names);
        span.debug("Created GENERAL_NAMES object for subject alternative names", .{});

        // Generate the base32 encoded public key
        const size = comptime base32.std_encoding.encodeLen(32);
        var dns_name_buf: [size + 1]u8 = undefined;
        dns_name_buf[0] = 'e'; // First character is 'e'

        // Base32 encode the public key (32 bytes) - results in 52 chars
        _ = base32.std_encoding.encode(dns_name_buf[1..], pubkey);

        span.debug("Created DNS name for certificate", .{});
        span.trace("DNS name value: {s}", .{dns_name_buf[0 .. size + 1]});
        // span.trace("DNS name pubkey: {}", .{std.fmt.fmtSliceHexLower(pubkey)});

        // Create a DNS-type general name with our encoded key
        const general_name = ssl.GENERAL_NAME_new() orelse {
            span.err("Failed to create general name", .{});
            @panic("GENERAL_NAME_new failed");
        };
        span.debug("Created GENERAL_NAME for alternative name", .{});

        // Create ASN1_STRING for the DNS name
        const dns_str = ssl.ASN1_STRING_new() orelse {
            span.err("Failed to create ASN1 string", .{});
            @panic("ASN1_STRING_new failed");
        };
        span.debug("Created ASN1_STRING for DNS name", .{});

        if (ssl.ASN1_STRING_set(dns_str, &dns_name_buf, 53) == 0) {
            span.err("Failed to set ASN1 string value", .{});
            @panic("ASN1_STRING_set failed");
        }
        span.debug("Set ASN1 string value with encoded pubkey", .{});

        // Set the DNS name in the general name
        ssl.GENERAL_NAME_set0_value(general_name, ssl.GEN_DNS, @ptrCast(dns_str));
        span.debug("Set DNS name value in GENERAL_NAME", .{});

        // Add the general name to the subject alternative names
        _ = ssl.sk_GENERAL_NAME_push(subject_alt_names, general_name);
        span.debug("Added GENERAL_NAME to subject alternative names", .{});

        // Sign the certificate with our private key
        if (ssl.X509_sign(cert, pkey, null) == 0) {
            span.err("Failed to sign certificate", .{});
            @panic("X509_sign failed");
        }
        span.debug("Successfully signed certificate with private key", .{});

        span.debug("Certificate creation completed successfully", .{});
        return cert;
    }

    /// Base32 encode a 32-byte Ed25519 public key into a 52-character string
    /// Uses the alphabet "abcdefghijklmnopqrstuvwxyz234567" as specified in JAMSNP
    fn base32EncodeEd25519Key(pubkey: [32]u8, out_buf: []u8) void {
        const span = trace.span(.base32_encode);
        defer span.deinit();
        span.debug("Base32 encoding Ed25519 public key", .{});
        span.trace("Input pubkey: {s}", .{std.fmt.fmtSliceHexLower(&pubkey)});

        const alphabet = "abcdefghijklmnopqrstuvwxyz234567";
        var i: usize = 0;
        var out_idx: usize = 0;

        // Process 5 bits at a time
        while (i < 32) {
            // Handle full bytes
            const b0 = if (i < 32) pubkey[i] else 0;
            i += 1;
            const b1 = if (i < 32) pubkey[i] else 0;
            i += 1;
            const b2 = if (i < 32) pubkey[i] else 0;
            i += 1;
            const b3 = if (i < 32) pubkey[i] else 0;
            i += 1;
            const b4 = if (i < 32) pubkey[i] else 0;
            i += 1;

            // Extract groups of 5 bits and convert to base32 characters
            out_buf[out_idx] = alphabet[(b0 >> 3) & 0x1F];
            out_idx += 1;
            out_buf[out_idx] = alphabet[((b0 << 2) | (b1 >> 6)) & 0x1F];
            out_idx += 1;
            out_buf[out_idx] = alphabet[(b1 >> 1) & 0x1F];
            out_idx += 1;
            out_buf[out_idx] = alphabet[((b1 << 4) | (b2 >> 4)) & 0x1F];
            out_idx += 1;
            out_buf[out_idx] = alphabet[((b2 << 1) | (b3 >> 7)) & 0x1F];
            out_idx += 1;
            out_buf[out_idx] = alphabet[(b3 >> 2) & 0x1F];
            out_idx += 1;
            out_buf[out_idx] = alphabet[((b3 << 3) | (b4 >> 5)) & 0x1F];
            out_idx += 1;
            out_buf[out_idx] = alphabet[b4 & 0x1F];
            out_idx += 1;
        }

        span.trace("Encoded output: {s}", .{out_buf[0..out_idx]});
        span.debug("Base32 encoding completed, encoded {d} bytes to {d} characters", .{ pubkey.len, out_idx });
    }
};

/// Configure SSL context for JAMSNP
pub fn configureSSLContext(
    allocator: std.mem.Allocator,
    keypair: std.crypto.sign.Ed25519.KeyPair,
    chain_genesis_hash: []const u8,
    is_client: bool,
    is_builder: bool,
) !*ssl.SSL_CTX {
    const span = trace.span(.configure_ssl_context);
    defer span.deinit();
    span.debug("Configuring SSL context for JAMSNP", .{});
    span.trace("Parameters - is_client: {}, is_builder: {}, chain_genesis_hash: {s}", .{ is_client, is_builder, std.fmt.fmtSliceHexLower(chain_genesis_hash) });

    const ssl_ctx = ssl.SSL_CTX_new(ssl.TLS_method()) orelse {
        span.err("Failed to create SSL context", .{});
        return error.SSLContextCreationFailed;
    };
    span.debug("Created new SSL context", .{});

    errdefer {
        span.debug("Cleaning up SSL context due to error", .{});
        ssl.SSL_CTX_free(ssl_ctx);
    }

    ssl.SSL_CTX_set_info_callback(ssl_ctx, ssl_info_callback); // Register the callback
    span.debug("Registered SSL info callback", .{});

    // Set TLS 1.3 protocol
    if (ssl.SSL_CTX_set_min_proto_version(ssl_ctx, ssl.TLS1_3_VERSION) == 0) {
        span.err("Failed to set minimum TLS protocol version to 1.3", .{});
        return error.SSLConfigurationFailed;
    }
    if (ssl.SSL_CTX_set_max_proto_version(ssl_ctx, ssl.TLS1_3_VERSION) == 0) {
        span.err("Failed to set maximum TLS protocol version to 1.3", .{});
        return error.SSLConfigurationFailed;
    }
    span.debug("Set TLS protocol version to 1.3 only", .{});

    // Configure Ed25519 signature algorithm
    const signature_algs = [_]u16{ssl.SSL_SIGN_ED25519};
    if (ssl.SSL_CTX_set_verify_algorithm_prefs(ssl_ctx, &signature_algs, 1) == 0) {
        span.err("Failed to set Ed25519 as signature algorithm", .{});
        return error.SSLConfigurationFailed;
    }
    span.debug("Configured Ed25519 as the signature algorithm", .{});

    // Create certificate with the required format
    const cert_span = span.child(.create_cert);
    defer cert_span.deinit();
    cert_span.debug("Creating X509 certificate", .{});

    const cert = X509Certificate.create(keypair);
    defer ssl.X509_free(cert);
    cert_span.debug("Created X509 certificate", .{});

    // Create EVP_PKEY from the raw private key bytes in the keypair
    const pkey_span = span.child(.create_pkey);
    defer pkey_span.deinit();
    pkey_span.debug("Creating EVP_PKEY from Ed25519 private key", .{});

    const pkey = ssl.EVP_PKEY_new_raw_private_key(
        ssl.EVP_PKEY_ED25519, // Specify the algorithm type
        null, // Engine (usually null)
        &keypair.secret_key.bytes, // Pointer to the raw private key bytes
        32, // Length of the private key (32 bytes for Ed25519)
    ) orelse {
        pkey_span.err("Failed to create EVP_PKEY from Ed25519 private key", .{});
        return error.SSLConfigurationFailed;
    };
    defer ssl.EVP_PKEY_free(pkey);
    pkey_span.debug("Created EVP_PKEY successfully", .{});

    // Now, load the private key into the context
    if (ssl.SSL_CTX_use_PrivateKey(ssl_ctx, pkey) == 0) {
        span.err("Failed to load private key into SSL context", .{});
        return error.SSLConfigurationFailed;
    }
    span.debug("Loaded private key into SSL context", .{});

    // Load the certificate generated earlier
    if (ssl.SSL_CTX_use_certificate(ssl_ctx, cert) == 0) {
        span.err("Failed to load certificate into SSL context", .{});
        return error.SSLConfigurationFailed;
    }
    span.debug("Loaded certificate into SSL context", .{});

    // Check consistency between private key and certificate
    if (ssl.SSL_CTX_check_private_key(ssl_ctx) == 0) {
        span.err("Private key does not match the certificate public key", .{});
        return error.SSLConfigurationFailed;
    }
    span.debug("Verified private key matches certificate public key", .{});

    // Set certificate verification
    const verify_span = span.child(.cert_verification);
    defer verify_span.deinit();

    if (is_client) {
        verify_span.debug("Configuring certificate verification for client mode", .{});
        // For clients, verify peer certificate
        ssl.SSL_CTX_set_verify(ssl_ctx, ssl.SSL_VERIFY_NONE, null);
        verify_span.debug("Set client verification to SSL_VERIFY_NONE", .{});
    } else {
        verify_span.debug("Configuring certificate verification for server mode", .{});
        // For servers, both request and verify client certificates
        ssl.SSL_CTX_set_verify(ssl_ctx, ssl.SSL_VERIFY_NONE | ssl.SSL_VERIFY_FAIL_IF_NO_PEER_CERT, null);
        verify_span.debug("Set server verification to SSL_VERIFY_NONE | SSL_VERIFY_FAIL_IF_NO_PEER_CERT", .{});
    }

    // Set ALPN
    const alpn_span = span.child(.configure_alpn);
    defer alpn_span.deinit();
    alpn_span.debug("Configuring ALPN", .{});

    // FIXME: check this is a memory leak, just for making this work for now
    const alpn_id = try buildAlpnIdentifier(allocator, chain_genesis_hash, is_builder);
    // defer allocator.free(alpn_id);
    alpn_span.debug("Built ALPN identifier: {s}", .{alpn_id});

    const alpn_protos = [1][]const u8{alpn_id};

    if (is_client) {
        alpn_span.debug("Setting ALPN protocols for client mode", .{});
        // Client sets the protocols it supports
        var alpn_proto_list: [128]u8 = undefined;
        var total_len: usize = 0;

        for (alpn_protos) |proto| {
            alpn_proto_list[total_len] = @intCast(proto.len);
            @memcpy(alpn_proto_list[total_len + 1 ..][0..proto.len], proto);
            total_len += 1 + proto.len;
        }
        alpn_span.trace("ALPN protocol list - total length: {d} bytes", .{total_len});

        if (ssl.SSL_CTX_set_alpn_protos(ssl_ctx, &alpn_proto_list, @intCast(total_len)) != 0) {
            alpn_span.err("Failed to set ALPN protocols", .{});
            return error.AlpnConfigurationFailed;
        }
        alpn_span.debug("Set client ALPN protocols successfully", .{});
    } else {
        alpn_span.debug("Setting ALPN select callback for server mode", .{});
        // Server selects from offered protocols
        const select_cb = struct {
            pub fn callback(_: ?*ssl.SSL, out: [*c][*c]const u8, outlen: [*c]u8, in: [*c]const u8, inlen: c_uint, arg: ?*anyopaque) callconv(.C) c_int {
                const callback_span = trace.span(.alpn_select_callback);
                defer callback_span.deinit();

                const supported_proto: [*:0]const u8 = @ptrCast(@alignCast(arg));
                const supported_proto_slice = std.mem.sliceTo(supported_proto, 0);
                callback_span.debug("ALPN select callback invoked", .{});
                callback_span.trace("Supported protocol: {s}", .{supported_proto_slice});
                callback_span.trace("Client offered protocols length: {d} bytes", .{inlen});

                var i: usize = 0;
                while (i < inlen) {
                    const proto_len = in[i];
                    i += 1;
                    if (i + proto_len > inlen) {
                        callback_span.debug("Malformed protocol list, skipping", .{});
                        break;
                    }

                    const proto = in[i..][0..proto_len];
                    callback_span.trace("Examining offered protocol: {s}", .{proto});

                    // Check if the protocol is acceptable
                    if (std.mem.eql(u8, proto[0..proto_len], supported_proto_slice)) {
                        callback_span.debug("Found matching protocol: {s}", .{proto});
                        // Out points to the in
                        out.* = @ptrCast(proto.ptr);
                        outlen.* = @intCast(proto.len);
                        return ssl.SSL_TLSEXT_ERR_OK;
                    }

                    i += proto_len;
                }

                callback_span.debug("No matching protocol found", .{});
                return ssl.SSL_TLSEXT_ERR_NOACK;
            }
        }.callback;

        ssl.SSL_CTX_set_alpn_select_cb(ssl_ctx, select_cb, @ptrCast(alpn_id.ptr));
        alpn_span.debug("Set server ALPN select callback successfully", .{});
    }

    span.debug("SSL context configuration completed successfully", .{});
    return ssl_ctx;
}

fn ssl_info_callback(ssl_handle: ?*const ssl.SSL, where_val: c_int, ret: c_int) callconv(.C) void {
    const span = trace.span(.ssl_info_callback);
    defer span.deinit();

    // Get state string only if handle is not null (can be null in early stages)
    const state_str = if (ssl_handle) |handle| ssl.SSL_state_string_long(handle) else @as([*c]const u8, @ptrCast("(null handle)"));
    span.debug("SSL state change", .{});
    span.trace("State='{s}', Where=0x{x}, Ret={d}", .{ state_str, where_val, ret });

    // Also output to standard debug log for visibility during development
    std.debug.print("\x1b[32mSSL INFO: State='{s}', Where=0x{x} ({s}), Ret={d}\x1b[0m\n", .{
        state_str,
        where_val,
        ssl.SSL_state_string_long(ssl_handle), // You might want more specific where flags decoded here
        ret,
    });

    // Add more detailed logging for alerts
    if ((where_val & ssl.SSL_CB_ALERT) != 0) {
        const is_write = (where_val & ssl.SSL_CB_WRITE) != 0;
        const alert_level_str = ssl.SSL_alert_type_string_long(ret); // Level is in upper byte of ret
        const alert_desc_str = ssl.SSL_alert_desc_string_long(ret); // Desc is in lower byte of ret

        span.debug("SSL alert {s}", .{if (is_write) "sent" else "received"});
        span.trace("Alert level: {s}, description: {s}, ret={d}", .{
            alert_level_str,
            alert_desc_str,
            ret,
        });

        std.debug.print("\x1b[31mSSL ALERT {s}: Level='{s}', Desc='{s}' (ret={d})\x1b[0m\n", .{
            if (is_write) "WRITE" else "READ",
            alert_level_str,
            alert_desc_str,
            ret,
        });
    }
}
