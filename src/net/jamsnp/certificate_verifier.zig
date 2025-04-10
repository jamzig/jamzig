const std = @import("std");
const ssl = @import("ssl");
const trace = @import("../../tracing.zig").scoped(.network);

/// Certificate verification callback for JAMSNP
pub fn verifyCertificate(certs: ?*ssl.X509_STORE_CTX, _: ?*anyopaque) callconv(.C) c_int {
    const span = trace.span(.verify_certificate);
    defer span.deinit();
    span.debug("Starting certificate verification", .{});

    // Get the peer certificate
    const cert = ssl.X509_STORE_CTX_get_current_cert(certs) orelse {
        span.err("Failed to get current certificate", .{});
        return 0; // Verification failed
    };
    span.debug("Got peer certificate", .{});

    // 1. Check signature algorithm is Ed25519
    const pkey = ssl.X509_get_pubkey(cert) orelse {
        span.err("Failed to get public key", .{});
        return 0; // Verification failed
    };
    defer ssl.EVP_PKEY_free(pkey);

    const key_type = ssl.EVP_PKEY_base_id(pkey);
    span.debug("Public key type: {d}", .{key_type});

    if (key_type != ssl.EVP_PKEY_ED25519) {
        span.err("Public key is not Ed25519 (type {d})", .{key_type});
        return 0; // Not Ed25519
    }
    span.debug("Verified Ed25519 signature algorithm", .{});

    // 2. Check that there is exactly one alternative name
    const alt_names = ssl.X509_get_ext_d2i(cert, ssl.NID_subject_alt_name, null, null) orelse {
        span.err("Certificate has no alternative names", .{});
        return 0; // No alt names
    };
    defer ssl.GENERAL_NAMES_free(@ptrCast(alt_names));

    const name_count = ssl.sk_GENERAL_NAME_num(@ptrCast(alt_names));
    span.debug("Found {d} alternative name(s)", .{name_count});

    if (name_count != 1) {
        span.err("Expected exactly 1 alternative name, found {d}", .{name_count});
        return 0; // More than one alt name
    }

    // 3. Check the alternative name format is a DNS name
    const gn = ssl.sk_GENERAL_NAME_value(@ptrCast(alt_names), 0) orelse {
        span.err("Failed to get alternative name at index 0", .{});
        return 0; // No alt name at index 0
    };

    const name_check_span = span.child(.check_alt_name);
    defer name_check_span.deinit();

    // 4. Extract the DNS name and verify format
    const dnsName = ssl.GENERAL_NAME_get0_value(gn, ssl.GEN_DNS) orelse {
        name_check_span.err("Alternative name is not a DNS name", .{});
        return 0; // Failed to get value
    };
    name_check_span.debug("Alternative name is a DNS name", .{});

    const dnsNameStr = ssl.ASN1_STRING_get0_data(@ptrCast(@alignCast(dnsName)));
    const dnsNameLen: usize = @intCast(ssl.ASN1_STRING_length(@ptrCast(@alignCast(dnsName))));

    name_check_span.debug("DNS name length: {d}", .{dnsNameLen});

    if (dnsNameLen != 53) { // 53-character DNS name
        name_check_span.err("DNS name has invalid length: {d} (expected 53)", .{dnsNameLen});
        return 0; // Incorrect length
    }

    // Create a buffer to safely print the DNS name for logging
    var dns_buffer: [54]u8 = undefined;
    @memcpy(dns_buffer[0..dnsNameLen], dnsNameStr[0..dnsNameLen]);
    dns_buffer[dnsNameLen] = 0; // null terminate
    name_check_span.trace("DNS name: {s}", .{dns_buffer[0..dnsNameLen]});

    // Check format 'e' + base32 encoded pubkey
    if (dnsNameStr[0] != 'e') {
        name_check_span.err("DNS name doesn't start with 'e'", .{});
        return 0; // Doesn't start with 'e'
    }
    name_check_span.debug("DNS name starts with 'e'", .{});

    // 5. Verify that the rest of the DNS name is base32 encoded
    const base32_check_span = span.child(.check_base32);
    defer base32_check_span.deinit();
    base32_check_span.debug("Checking base32 encoding for DNS name", .{});

    var invalid_chars: [10]u8 = undefined;
    var invalid_count: usize = 0;

    for (1..dnsNameLen) |i| {
        const c = dnsNameStr[i];
        const isValid =
            (c >= 'a' and c <= 'z') or
            (c >= '2' and c <= '7');

        if (!isValid) {
            if (invalid_count < invalid_chars.len) {
                invalid_chars[invalid_count] = c;
                invalid_count += 1;
            }
            base32_check_span.err("Invalid base32 character '{c}' at position {d}", .{ c, i });
            return 0; // Character not in the expected base32 alphabet
        }
    }

    base32_check_span.debug("DNS name is properly base32 encoded", .{});

    // TODO: Decode the base32 public key and compare with the certificate's key
    span.debug("Certificate verification successful", .{});
    return 1; // Verification successful
}
