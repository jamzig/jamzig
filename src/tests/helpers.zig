const std = @import("std");

pub fn hashMapEqual(comptime K: type, comptime V: type, map1: std.AutoHashMap(K, V), map2: std.AutoHashMap(K, V)) !void {
    if (map1.count() != map2.count()) {
        std.debug.print("HashMap counts do not match: {} != {}\n", .{ map1.count(), map2.count() });
        return error.HashMapNotEqual;
    }

    var mismatch = false;
    var it = map1.iterator();
    while (it.next()) |entry| {
        const value2 = map2.get(entry.key_ptr.*);
        if (value2 == null or value2.? != entry.value_ptr.*) {
            std.debug.print("Mismatch for key {any}: {any} != {any}\n", .{ entry.key_ptr.*, entry.value_ptr.*, value2 });
            mismatch = true;
        } else {
            // std.debug.print("Match for key {any}: {any} == {any}\n", .{ entry.key_ptr.*, entry.value_ptr.*, value2 });
        }
    }

    if (mismatch) {
        return error.HashMapNotEqual;
    }
}
