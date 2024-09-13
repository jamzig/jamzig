const std = @import("std");
const tv_types = @import("../vectors/libs/types.zig");
const tv_lib_codec = @import("../vectors/libs/codec.zig");

const lib_codec = @import("../../types.zig");

const Allocator = std.mem.Allocator;

fn convertOpaqueHash(from: tv_lib_codec.OpaqueHash) lib_codec.OpaqueHash {
    return convertHexBytesFixedToArray(32, from);
}

fn convertEd25519Key(from: tv_lib_codec.Ed25519Key) lib_codec.Ed25519Key {
    return convertHexBytesFixedToArray(32, from);
}

fn convertBandersnatchKey(from: tv_lib_codec.BandersnatchKey) lib_codec.BandersnatchKey {
    return convertHexBytesFixedToArray(32, from);
}

fn convertHexBytesFixedToArray(comptime size: u32, from: tv_types.hex.HexBytesFixed(size)) [size]u8 {
    var to: [size]u8 = undefined;
    for (from.bytes, 0..) |from_byte, i| {
        to[i] = from_byte;
    }
    return to;
}

pub fn refineContextFromTestVector(from: *const tv_lib_codec.RefineContext) lib_codec.RefineContext {
    return lib_codec.RefineContext{
        .anchor = convertOpaqueHash(from.anchor),
        .state_root = convertOpaqueHash(from.state_root),
        .beefy_root = convertOpaqueHash(from.beefy_root),
        .lookup_anchor = convertOpaqueHash(from.lookup_anchor),
        .lookup_anchor_slot = from.lookup_anchor_slot,
        .prerequisite = if (from.prerequisite) |prereq| convertOpaqueHash(prereq) else null,
    };
}

pub fn importSpecFromTestVector(from: *const tv_lib_codec.ImportSpec) lib_codec.ImportSpec {
    return lib_codec.ImportSpec{
        .tree_root = convertOpaqueHash(from.tree_root),
        .index = from.index,
    };
}

pub fn extrinsicSpecFromTestVector(from: *const tv_lib_codec.ExtrinsicSpec) lib_codec.ExtrinsicSpec {
    return lib_codec.ExtrinsicSpec{
        .hash = convertOpaqueHash(from.hash),
        .len = from.len,
    };
}

pub fn authorizerFromTestVector(allocator: Allocator, from: *const tv_lib_codec.Authorizer) !lib_codec.Authorizer {
    return lib_codec.Authorizer{
        .code_hash = convertOpaqueHash(from.code_hash),
        .params = try allocator.dupe(u8, from.params),
    };
}

pub fn workItemFromTestVector(allocator: Allocator, from: *const tv_lib_codec.WorkItem) !lib_codec.WorkItem {
    return lib_codec.WorkItem{
        .service = from.service,
        .code_hash = convertOpaqueHash(from.code_hash),
        .payload = try allocator.dupe(u8, from.payload),
        .gas_limit = from.gas_limit,
        .import_segments = try convertSlice(allocator, lib_codec.ImportSpec, from.import_segments, importSpecFromTestVector),
        .extrinsic = try convertSlice(allocator, lib_codec.ExtrinsicSpec, from.extrinsic, extrinsicSpecFromTestVector),
        .export_count = from.export_count,
    };
}

pub fn workPackageFromTestVector(allocator: Allocator, from: *const tv_lib_codec.WorkPackage) !lib_codec.WorkPackage {
    return lib_codec.WorkPackage{
        .authorization = try allocator.dupe(u8, from.authorization),
        .auth_code_host = from.auth_code_host,
        .authorizer = try authorizerFromTestVector(allocator, &from.authorizer),
        .context = refineContextFromTestVector(&from.context),
        .items = try convertSlice(allocator, lib_codec.WorkItem, from.items, workItemFromTestVector),
    };
}

pub fn workExecResultFromTestVector(allocator: Allocator, from: *const tv_lib_codec.WorkExecResult) !lib_codec.WorkExecResult {
    return switch (from.*) {
        .ok => |ok| lib_codec.WorkExecResult{ .ok = try allocator.dupe(u8, ok) },
        .out_of_gas => lib_codec.WorkExecResult.out_of_gas,
        .panic => lib_codec.WorkExecResult.panic,
        .bad_code => lib_codec.WorkExecResult.bad_code,
        .code_oversize => lib_codec.WorkExecResult.code_oversize,
    };
}

pub fn workResultFromTestVector(allocator: Allocator, from: *const tv_lib_codec.WorkResult) !lib_codec.WorkResult {
    return lib_codec.WorkResult{
        .service = from.service,
        .code_hash = convertOpaqueHash(from.code_hash),
        .payload_hash = convertOpaqueHash(from.payload_hash),
        .gas_ratio = from.gas_ratio,
        .result = try workExecResultFromTestVector(allocator, &from.result),
    };
}

pub fn workPackageSpecFromTestVector(from: *const tv_lib_codec.WorkPackageSpec) lib_codec.WorkPackageSpec {
    return lib_codec.WorkPackageSpec{
        .hash = convertOpaqueHash(from.hash),
        .len = from.len,
        .root = convertOpaqueHash(from.root),
        .segments = convertOpaqueHash(from.segments),
    };
}

pub fn workReportFromTestVector(allocator: Allocator, from: *const tv_lib_codec.WorkReport) !lib_codec.WorkReport {
    return lib_codec.WorkReport{
        .package_spec = workPackageSpecFromTestVector(&from.package_spec),
        .context = refineContextFromTestVector(&from.context),
        .core_index = from.core_index,
        .authorizer_hash = convertOpaqueHash(from.authorizer_hash),
        .auth_output = try allocator.dupe(u8, from.auth_output),
        .results = try convertSlice(allocator, lib_codec.WorkResult, from.results, workResultFromTestVector),
    };
}

pub fn headerFromTestVector(allocator: Allocator, from: *const tv_lib_codec.Header) !lib_codec.Header {
    return lib_codec.Header{
        .parent = convertOpaqueHash(from.parent),
        .parent_state_root = convertOpaqueHash(from.parent_state_root),
        .extrinsic_hash = convertOpaqueHash(from.extrinsic_hash),
        .slot = from.slot,
        .epoch_mark = if (from.epoch_mark) |epoch_mark| try convertEpochMark(allocator, epoch_mark) else null,
        .tickets_mark = if (from.tickets_mark) |tickets_mark| try convertTicketsMark(allocator, tickets_mark) else null,
        .offenders_mark = try convertSlice(allocator, lib_codec.Ed25519Key, from.offenders_mark, convertEd25519Key),
        .author_index = from.author_index,
        .entropy_source = convertHexBytesFixedToArray(96, from.entropy_source),
        .seal = convertHexBytesFixedToArray(96, from.seal),
    };
}

pub fn ticketEnvelopeFromTestVector(from: *const tv_lib_codec.TicketEnvelope) lib_codec.TicketEnvelope {
    return lib_codec.TicketEnvelope{
        .attempt = from.attempt,
        .signature = convertHexBytesFixedToArray(784, from.signature),
    };
}

pub fn judgementFromTestVector(from: *const tv_lib_codec.Judgement) lib_codec.Judgement {
    return lib_codec.Judgement{
        .vote = from.vote,
        .index = from.index,
        .signature = convertHexBytesFixedToArray(64, from.signature),
    };
}

pub fn verdictFromTestVector(allocator: Allocator, from: *const tv_lib_codec.Verdict) !lib_codec.Verdict {
    return lib_codec.Verdict{
        .target = convertOpaqueHash(from.target),
        .age = from.age,
        .votes = try convertSlice(allocator, lib_codec.Judgement, from.votes, judgementFromTestVector),
    };
}

pub fn culpritFromTestVector(from: *const tv_lib_codec.Culprit) lib_codec.Culprit {
    return lib_codec.Culprit{
        .target = convertOpaqueHash(from.target),
        .key = convertHexBytesFixedToArray(32, from.key),
        .signature = convertHexBytesFixedToArray(64, from.signature),
    };
}

pub fn faultFromTestVector(from: *const tv_lib_codec.Fault) lib_codec.Fault {
    return lib_codec.Fault{
        .target = convertOpaqueHash(from.target),
        .vote = from.vote,
        .key = convertHexBytesFixedToArray(32, from.key),
        .signature = convertHexBytesFixedToArray(64, from.signature),
    };
}

pub fn disputesExtrinsicFromTestVector(allocator: Allocator, from: *const tv_lib_codec.DisputesExtrinsic) !lib_codec.DisputesExtrinsic {
    return lib_codec.DisputesExtrinsic{
        .verdicts = try convertSlice(allocator, lib_codec.Verdict, from.verdicts, verdictFromTestVector),
        .culprits = try convertSlice(allocator, lib_codec.Culprit, from.culprits, culpritFromTestVector),
        .faults = try convertSlice(allocator, lib_codec.Fault, from.faults, faultFromTestVector),
    };
}

pub fn preimageFromTestVector(allocator: Allocator, from: *const tv_lib_codec.Preimage) !lib_codec.Preimage {
    return lib_codec.Preimage{
        .requester = from.requester,
        .blob = try allocator.dupe(u8, from.blob),
    };
}

pub fn availAssuranceFromTestVector(allocator: Allocator, from: *const tv_lib_codec.AvailAssurance) !lib_codec.AvailAssurance {
    return lib_codec.AvailAssurance{
        .anchor = convertOpaqueHash(from.anchor),
        .bitfield = try allocator.dupe(u8, from.bitfield),
        .validator_index = from.validator_index,
        .signature = convertHexBytesFixedToArray(64, from.signature),
    };
}

pub fn validatorSignatureFromTestVector(from: *const tv_lib_codec.ValidatorSignature) lib_codec.ValidatorSignature {
    return lib_codec.ValidatorSignature{
        .validator_index = from.validator_index,
        .signature = convertHexBytesFixedToArray(64, from.signature),
    };
}

pub fn reportGuaranteeFromTestVector(allocator: Allocator, from: *const tv_lib_codec.ReportGuarantee) !lib_codec.ReportGuarantee {
    return lib_codec.ReportGuarantee{
        .report = try workReportFromTestVector(allocator, &from.report),
        .slot = from.slot,
        .signatures = try convertSlice(allocator, lib_codec.ValidatorSignature, from.signatures, validatorSignatureFromTestVector),
    };
}

pub fn extrinsicFromTestVector(allocator: Allocator, from: *const tv_lib_codec.Extrinsic) !lib_codec.Extrinsic {
    return lib_codec.Extrinsic{
        .tickets = try convertSlice(allocator, lib_codec.TicketEnvelope, from.tickets, ticketEnvelopeFromTestVector),
        .disputes = try disputesExtrinsicFromTestVector(allocator, &from.disputes),
        .preimages = try convertSlice(allocator, lib_codec.Preimage, from.preimages, preimageFromTestVector),
        .assurances = try convertSlice(allocator, lib_codec.AvailAssurance, from.assurances, availAssuranceFromTestVector),
        .guarantees = try convertSlice(allocator, lib_codec.ReportGuarantee, from.guarantees, reportGuaranteeFromTestVector),
    };
}

pub fn blockFromTestVector(allocator: Allocator, from: *const tv_lib_codec.Block) !lib_codec.Block {
    return lib_codec.Block{
        .header = try headerFromTestVector(allocator, &from.header),
        .extrinsic = try extrinsicFromTestVector(allocator, &from.extrinsic),
    };
}

fn convertSlice(allocator: Allocator, comptime T: type, from: anytype, converter: anytype) ![]T {
    // @compileLog("convertSlice: ", @typeName(@TypeOf(from)));

    const to = try allocator.alloc(T, from.len);
    for (from, 0..) |item, i| {
        const info = @typeInfo(@TypeOf(converter));
        switch (info) {
            .@"fn" => |fnInfo| {
                if (fnInfo.params.len == 2 and fnInfo.params[0].type.? == Allocator) {
                    to[i] = try converter(allocator, item);
                } else {
                    to[i] = converter(item);
                }
            },
            else => unreachable,
        }
    }
    return to;
}

fn convertEpochMark(allocator: Allocator, from: tv_lib_codec.EpochMark) !lib_codec.EpochMark {
    return lib_codec.EpochMark{
        .entropy = convertOpaqueHash(from.entropy),
        .validators = try convertSlice(allocator, lib_codec.BandersnatchKey, from.validators, convertBandersnatchKey),
    };
}

fn convertTicketsMark(allocator: Allocator, from: tv_lib_codec.TicketsMark) !lib_codec.TicketsMark {
    return lib_codec.TicketsMark{
        .tickets = try convertSlice(allocator, lib_codec.TicketBody, from, convertTicketBody),
    };
}

fn convertTicketBody(from: tv_lib_codec.TicketBody) lib_codec.TicketBody {
    return lib_codec.TicketBody{
        .id = convertOpaqueHash(from.id),
        .attempt = from.attempt,
    };
}
