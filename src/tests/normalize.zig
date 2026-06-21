const std = @import("std");
const math = std.math;
const testing = std.testing;

const BigFloat = @import("../root.zig").BigFloat;
const utils = @import("../test_utils.zig");

test "normalize" {
    inline for (utils.bigFloatTypes(&.{ f32, f64, f80, f128 }, &.{ i8, i16, i19, i32 })) |F| {
        const S = @FieldType(F, "significand");
        const E = @FieldType(F, "exponent");

        try testing.expectEqual(F{
            .significand = 1,
            .exponent = 1,
        }, F.normalize(.{ .significand = 2, .exponent = 0 }));
        try testing.expectEqual(F{
            .significand = -123.0 / 64.0,
            .exponent = 6,
        }, F.normalize(.{ .significand = -123, .exponent = 0 }));
        try testing.expectEqual(F{
            .significand = 0.0043 * 256.0,
            .exponent = -8,
        }, F.normalize(.{ .significand = 0.0043, .exponent = 0 }));
        try testing.expectEqual(F{
            .significand = 0,
            .exponent = 0,
        }, F.normalize(.{ .significand = 0, .exponent = 0 }));
        try testing.expectEqual(F.init(1.545), F.init(1.545).normalize());

        @setEvalBranchQuota(10_000);
        try testing.expectEqual(
            if (comptime utils.fitsInt(E, math.floatExponentMin(S)))
                F{
                    .significand = 1,
                    .exponent = math.floatExponentMin(S),
                }
            else
                F.init(0),
            F.normalize(.{ .significand = math.floatMin(S), .exponent = 0 }),
        );
        try testing.expectEqual(
            if (comptime utils.fitsInt(E, math.floatExponentMin(S) - math.floatFractionalBits(S)))
                F{
                    .significand = 1,
                    .exponent = math.floatExponentMin(S) - math.floatFractionalBits(S),
                }
            else
                F.init(0),
            F.normalize(.{ .significand = math.floatTrueMin(S), .exponent = 0 }),
        );

        try utils.expectBitwiseEqual(F{
            .significand = 0,
            .exponent = 0,
        }, F.normalize(.{ .significand = 0, .exponent = 0 }));
        try utils.expectBitwiseEqual(F{
            .significand = -0.0,
            .exponent = 0,
        }, F.normalize(.{ .significand = -0.0, .exponent = 0 }));
        try testing.expectEqual(F{
            .significand = math.inf(S),
            .exponent = 0,
        }, F.normalize(.{ .significand = math.inf(S), .exponent = 0 }));
        try testing.expect(math.isNan(
            F.normalize(.{ .significand = math.nan(S), .exponent = 0 }).significand,
        ));
    }
}

// Failed cases from fuzzer
test "normalize fuzz" {
    const BF = BigFloat(.{ .Significand = f80, .Exponent = i23 });
    try testing.expectEqual(BF{
        .significand = -1.37979654136095563287,
        .exponent = 1253368,
    }, BF.normalize(.{
        .significand = @bitCast(@as(u80, 0x8000b09d2c4e23bd57ae)),
        .exponent = 1269750,
    }));
}
