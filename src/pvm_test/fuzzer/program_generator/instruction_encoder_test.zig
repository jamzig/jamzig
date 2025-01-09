const std = @import("std");
const testing = std.testing;
const Instruction = @import("../../../pvm/instruction.zig").Instruction;
const Decoder = @import("../../../pvm/decoder.zig").Decoder;
const encoder = @import("instruction_encoder.zig").encoder;

test "encoder/decoder roundtrip - encodeOneImm" {
    var program: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&program);
    var enc = encoder(fbs.writer());

    const length = try enc.encodeOneImm(10, 42);
    _ = try enc.encodeNoArgs(1);
    const written = fbs.getWritten();

    var mask: [16]u8 = std.mem.zeroes([16]u8);
    mask[length / 8] |= @as(u8, 0x01) << @intCast(length % 8);

    const dec = Decoder.init(written, &mask);
    const instruction = try dec.decodeInstruction(0);

    try testing.expectEqual(10, @intFromEnum(instruction.instruction));
    try testing.expectEqual(@as(u64, 42), instruction.args.one_immediate.immediate);
}
