const std = @import("std");

const TestVector = @import("tests/vectors/libs/safrole.zig").TestVector;

const tests = @import("tests.zig");
const safrole = @import("safrole.zig");

test "update tau" {
    const allocator = std.testing.allocator;
    const tv_parsed = try TestVector.build_from(allocator, "src/tests/vectors/jam/safrole/tiny/enact-epoch-change-with-no-tickets-1.json");
    defer tv_parsed.deinit();
    const tv = &tv_parsed.value;

    // Assume these are populated from your JSON parsing
    const pre_state = try tests.stateFromTestVector(allocator, &tv.pre_state);
    const input = try tests.inputFromTestVector(allocator, &tv.input);

    // this needs to be fixed
    const post_state = pre_state;

    _ = try safrole.transition(
        allocator,
        pre_state,
        input,
        post_state,
    );

    try std.testing.expectEqual(1, post_state.tau);
}
