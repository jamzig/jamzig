const std = @import("std");
const testing = std.testing;

const codec = @import("codec.zig");
const codec_test = @import("tests/vectors/codec.zig");

const convert = @import("tests/convert/codec.zig");

const types = @import("types.zig");

/// The Tiny PARAMS as they are defined in the ASN
const TINY_PARAMS = types.CodecParams{
    .validators = 6,
    .epoch_length = 12,
    .cores_count = 2,
    .validators_super_majority = 5,
    .avail_bitfield_bytes = 1,
};

/// Helper function to decode and compare test vectors
fn testDecodeAndCompare(comptime DomainType: type, comptime VectorType: type, name: []const u8) !void {
    const allocator = std.testing.allocator;

    const file_path = try std.fmt.allocPrint(allocator, "src/tests/vectors/codec/codec/data/{s}.json", .{name});
    defer allocator.free(file_path);

    const vector = try codec_test.CodecTestVector(VectorType).build_from(allocator, file_path);
    defer vector.deinit();

    var decoded = try codec.deserialize(
        DomainType,
        TINY_PARAMS,
        allocator,
        vector.binary,
    );
    defer decoded.deinit();

    const expected: DomainType = try convert.convert(VectorType, DomainType, allocator, vector.expected.value);
    defer convert.generic.free(allocator, expected);

    try std.testing.expectEqualDeep(expected, decoded.value);
}

const test_cases = [_]struct {
    name: []const u8,
    domain_type: type,
    vector_type: type,
}{
    .{ .name = "header_0", .domain_type = types.Header, .vector_type = codec_test.types.Header },
    .{ .name = "header_1", .domain_type = types.Header, .vector_type = codec_test.types.Header },
    .{ .name = "extrinsic", .domain_type = types.Extrinsic, .vector_type = codec_test.types.Extrinsic },
    .{ .name = "block", .domain_type = types.Block, .vector_type = codec_test.types.Block },
    .{ .name = "assurances_extrinsic", .domain_type = types.AssurancesExtrinsic, .vector_type = codec_test.types.AssurancesExtrinsic },
    .{ .name = "disputes_extrinsic", .domain_type = types.DisputesExtrinsic, .vector_type = codec_test.types.DisputesExtrinsic },
    .{ .name = "guarantees_extrinsic", .domain_type = types.GuaranteesExtrinsic, .vector_type = codec_test.types.GuaranteesExtrinsic },
    .{ .name = "preimages_extrinsic", .domain_type = types.PreimagesExtrinsic, .vector_type = codec_test.types.PreimagesExtrinsic },
    .{ .name = "refine_context", .domain_type = types.RefineContext, .vector_type = codec_test.types.RefineContext },
    .{ .name = "tickets_extrinsic", .domain_type = types.TicketsExtrinsic, .vector_type = codec_test.types.TicketsExtrinsic },
    .{ .name = "work_item", .domain_type = types.WorkItem, .vector_type = codec_test.types.WorkItem },
    .{ .name = "work_package", .domain_type = types.WorkPackage, .vector_type = codec_test.types.WorkPackage },
    .{ .name = "work_report", .domain_type = types.WorkReport, .vector_type = codec_test.types.WorkReport },
    .{ .name = "work_result_0", .domain_type = types.WorkResult, .vector_type = codec_test.types.WorkResult },
    .{ .name = "work_result_1", .domain_type = types.WorkResult, .vector_type = codec_test.types.WorkResult },
};

test "codec: decode" {
    inline for (test_cases) |test_case| {
        const test_name = "codec: decode " ++ test_case.name;
        std.debug.print("{s}\n", .{test_name});

        try testDecodeAndCompare(test_case.domain_type, test_case.vector_type, test_case.name);
    }
}
