const std = @import("std");
const testing = std.testing;

const BigFloat = @import("../root.zig").BigFloat;
const utils = @import("../test_utils.zig");

test "parse special" {
    inline for (utils.bigFloatTypes(&.{ f16, f32, f64, f80, f128 }, &.{ i23, i32 })) |F| {
        try testing.expect((try F.parse("nAn")).isNan());
        try testing.expectEqual(
            F.inf,
            try F.parse("iNf"),
        );
        try testing.expectEqual(
            F.inf,
            try F.parse("+Inf"),
        );
        try testing.expectEqual(
            F.inf.neg(),
            try F.parse("-iNf"),
        );

        try testing.expectEqual(
            F.inf,
            F.parse("0B1111p99999999999999999999"),
        );
        try testing.expectEqual(
            F.inf.neg(),
            try F.parse("-0b1111p99999999999999999999"),
        );
        try testing.expectEqual(
            F.inf,
            F.parse("0o7777p99999999999999999999"),
        );
        try testing.expectEqual(
            F.inf.neg(),
            try F.parse("-0O7777p99999999999999999999"),
        );
        try testing.expectEqual(
            F.inf,
            F.parse("0XFfFfp99999999999999999999"),
        );
        try testing.expectEqual(
            F.inf.neg(),
            try F.parse("-0xfFfFp99999999999999999999"),
        );
        try testing.expectEqual(
            F.inf,
            F.parse("9999e99999999999999999999"),
        );
        try testing.expectEqual(
            F.inf.neg(),
            try F.parse("-9999e99999999999999999999"),
        );
    }

    const BF = BigFloat(.{ .Significand = f32, .Exponent = isize });
    // Overflow
    try testing.expectEqual(
        BF.inf,
        try BF.parse(std.fmt.comptimePrint("0b10000000000000000p{d}", .{std.math.maxInt(usize) - 5})),
    );
    try testing.expectEqual(
        BF.inf,
        try BF.parse(std.fmt.comptimePrint("10000000000000000e{d}", .{std.math.maxInt(usize) - 5})),
    );
    try testing.expectEqual(
        BF.inf,
        try BF.parse(std.fmt.comptimePrint("0x10000000000000000p{d}", .{std.math.maxInt(usize) - 5})),
    );
    // Underflow
    try testing.expectEqual(
        BF.init(0),
        try BF.parse(std.fmt.comptimePrint("0b0.00000000000000001p-{d}", .{std.math.maxInt(usize) - 5})),
    );
    try testing.expectEqual(
        BF.init(0),
        try BF.parse(std.fmt.comptimePrint("0.00000000000000001e-{d}", .{std.math.maxInt(usize) - 5})),
    );
    try testing.expectEqual(
        BF.init(0),
        try BF.parse(std.fmt.comptimePrint("0x0.00000000000000001p-{d}", .{std.math.maxInt(usize) - 5})),
    );
}

test "parse zero" {
    inline for (utils.bigFloatTypes(&.{ f16, f32, f64, f80, f128 }, &.{ i23, i32 })) |F| {
        try testing.expectEqual(F.init(0), try F.parse("0B0"));
        try testing.expectEqual(F.init(0), try F.parse("0o0"));
        try testing.expectEqual(F.init(0), try F.parse("0X0"));
        try testing.expectEqual(F.init(0), try F.parse("0"));

        try utils.expectBitwiseEqual(F.init(-0.0), try F.parse("-0B0"));
        try utils.expectBitwiseEqual(F.init(-0.0), try F.parse("-0O0"));
        try utils.expectBitwiseEqual(F.init(-0.0), try F.parse("-0X0"));
        try utils.expectBitwiseEqual(F.init(-0.0), try F.parse("-0"));

        try testing.expectEqual(F.init(0), try F.parse("0x00000000000000000000000000.0000000000000000000"));
        try testing.expectEqual(F.init(0), try F.parse("0000000000000000000000000000.0000000000000000000"));

        try testing.expectEqual(F.init(0), try F.parse("0b0p42"));
        try testing.expectEqual(F.init(0), try F.parse("0O0p42"));
        try testing.expectEqual(F.init(0), try F.parse("0x0p42"));
        try testing.expectEqual(F.init(0), try F.parse("0e42"));

        try utils.expectBitwiseEqual(F.init(-0.0), try F.parse("-0b0.00000p42"));
        try utils.expectBitwiseEqual(F.init(-0.0), try F.parse("-0o0.00000p42"));
        try utils.expectBitwiseEqual(F.init(-0.0), try F.parse("-0x0.00000p42"));
        try utils.expectBitwiseEqual(F.init(-0.0), try F.parse("-0.00000e42"));

        try testing.expectEqual(F.init(0), try F.parse("0B0.00000p123456789012"));
        try testing.expectEqual(F.init(0), try F.parse("0O0.00000p123456789012"));
        try testing.expectEqual(F.init(0), try F.parse("0X0.00000p123456789012"));
        try testing.expectEqual(F.init(0), try F.parse("0.00000e123456789012"));
    }
}

test "parse error" {
    inline for (utils.bigFloatTypes(&.{ f16, f32, f64, f80, f128 }, &.{ i23, i32 })) |F| {
        try testing.expectError(error.InvalidCharacter, F.parse(""));
        try testing.expectError(error.InvalidCharacter, F.parse("0b"));
        try testing.expectError(error.InvalidCharacter, F.parse("0o"));
        try testing.expectError(error.InvalidCharacter, F.parse("0x"));

        try testing.expectError(error.InvalidCharacter, F.parse("_"));
        try testing.expectError(error.InvalidCharacter, F.parse("0_."));
        try testing.expectError(error.InvalidCharacter, F.parse("0._1"));
        try testing.expectError(error.InvalidCharacter, F.parse("_._"));
        try testing.expectError(error.InvalidCharacter, F.parse("1.1e"));
        try testing.expectError(error.InvalidCharacter, F.parse("1.1e_1"));

        try testing.expectError(error.InvalidCharacter, F.parse("0x_"));
        try testing.expectError(error.InvalidCharacter, F.parse("0x0_."));
        try testing.expectError(error.InvalidCharacter, F.parse("0x0._1"));
        try testing.expectError(error.InvalidCharacter, F.parse("0x_._"));
        try testing.expectError(error.InvalidCharacter, F.parse("0x1.1p"));
        try testing.expectError(error.InvalidCharacter, F.parse("0x1.1p_1"));
    }
}

test "parse decimal" {
    inline for (utils.bigFloatTypes(&.{ f16, f32, f64, f80, f128 }, &.{ i23, i32 })) |F| {
        try testing.expectEqual(
            F.init(1e0),
            try F.parse("1e0"),
        );
        try testing.expectEqual(
            F.init(-1E-1),
            try F.parse("-1E-1"),
        );
        try testing.expectEqual(
            F.init(10e+10),
            try F.parse("10e+10"),
        );
        try testing.expectEqual(
            F.init(10e-10),
            try F.parse("10e-10"),
        );
        try testing.expectEqual(
            F.init(0.999_9_9999E12_8),
            try F.parse("0.999_9_9999E12_8"),
        );
        try testing.expectEqual(
            F.init(0.1234570e-125),
            try F.parse("0.1234570e-125"),
        );
        try testing.expectEqual(
            F{ .significand = -1.1641329014465341360604276125731042, .exponent = 2939632 },
            try F.parse("-2.98e884917"),
        );
        try testing.expectEqual(
            F{ .significand = -1.1220675346033635219128088409542306, .exponent = -4156124 },
            try F.parse("-1.149e-1251118"),
        );

        try testing.expectEqual(
            F.init(123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123),
            try F.parse("123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123"),
        );
        try testing.expectEqual(
            F.init(0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001),
            try F.parse("0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"),
        );
        try testing.expectEqual(
            F.inf,
            try F.parse("123.456e1234567890123456789012345678901234567890"),
        );
        try testing.expectEqual(
            F.init(0),
            try F.parse("123.456e-1234567890123456789012345678901234567890"),
        );

        @setEvalBranchQuota(50000);
        const max_value_str = std.fmt.comptimePrint("{e}", .{F.max_value});
        const min_value_str = std.fmt.comptimePrint("{e}", .{F.min_value});
        try testing.expectEqual(
            F.max_value,
            try F.parse(max_value_str),
        );
        try testing.expectEqual(
            F.max_value.neg(),
            try F.parse("-" ++ max_value_str),
        );
        try testing.expectEqual(
            F.min_value,
            try F.parse(min_value_str),
        );
        try testing.expectEqual(
            F.min_value.neg(),
            try F.parse("-" ++ min_value_str),
        );
    }
}

// Failed cases from fuzzer
test "parse decimal fuzz" {
    const BF32 = BigFloat(.{ .Significand = f32, .Exponent = i128 });
    try testing.expectEqual(
        -41999781497045633317315380311157951373,
        (try BF32.parse("1.0693013e-12643194041943804629407517803902603710")).exponent,
    );

    const BF64 = BigFloat(.{ .Significand = f64, .Exponent = i128 });
    try testing.expectEqual(
        169457330695573499036228701731869445796,
        (try BF64.parse("3.4571953819264144e51011739524518317909985126567442417081")).exponent,
    );
}

test "parse decimal fuzz failing" {
    return error.SkipZigTest;

    // const BF16 = BigFloat(.{ .Significand = f16, .Exponent = i128 });
    // try testing.expectEqual(
    //     64860025656353236083789072948066756057,
    //     (try BF16.parse("3.72e19524813242097723733436035443233760677")).exponent,
    // );
}

test "parse decimal rounding" {
    inline for (utils.bigFloatTypes(&.{f32}, &.{ i23, i32 })) |F| {
        try testing.expectEqual(
            F.init(1.000000178813934326171875),
            try F.parse("1.000000178813934326171875"),
        );

        // Overflow on rounding
        try testing.expectEqual(
            F.init(0.9999999701976776125),
            try F.parse("0.9999999701976776125"),
        );
        try testing.expectEqual(
            F.init(1.99999999999999999999999999999999999999e0),
            try F.parse("1.99999999999999999999999999999999999999e0"),
        );
    }
}

test "parse hex" {
    inline for (utils.bigFloatTypes(&.{ f16, f32, f64, f80, f128 }, &.{ i23, i32 })) |F| {
        try testing.expectEqual(
            F.init(0x1p0),
            try F.parse("0x1p0"),
        );
        try testing.expectEqual(
            F.init(-0x1p-1),
            try F.parse("-0x1p-1"),
        );
        try testing.expectEqual(
            F.init(0x10p+10),
            try F.parse("0X10p+10"),
        );
        try testing.expectEqual(
            F.init(0x10p-10),
            try F.parse("0x10p-10"),
        );
        try testing.expectEqual(
            F.init(0x0.fff_f_ffffp12_8),
            try F.parse("0x0.fff_f_ffffp12_8"),
        );
        try testing.expectEqual(
            F.init(0x0.1234570p-125),
            try F.parse("0X0.1234570p-125"),
        );

        try testing.expectEqual(
            F.init(0x123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123),
            try F.parse("0x123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123123"),
        );
        try testing.expectEqual(
            F.init(0x0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001),
            try F.parse("0x0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"),
        );
        try testing.expectEqual(
            F.inf,
            try F.parse("0x123.456p1234567890123456789012345678901234567890"),
        );
        try testing.expectEqual(
            F.init(0),
            try F.parse("0x123.456p-1234567890123456789012345678901234567890"),
        );

        @setEvalBranchQuota(50000);
        const max_value_str = std.fmt.comptimePrint("{x}", .{F.max_value});
        const min_value_str = std.fmt.comptimePrint("{x}", .{F.min_value});
        try testing.expectEqual(
            F.max_value,
            try F.parse(max_value_str),
        );
        try testing.expectEqual(
            F.max_value.neg(),
            try F.parse("-" ++ max_value_str),
        );
        try testing.expectEqual(
            F.min_value,
            try F.parse(min_value_str),
        );
        try testing.expectEqual(
            F.min_value.neg(),
            try F.parse("-" ++ min_value_str),
        );
    }
}

test "parse 2^n base rounding" {
    inline for (utils.bigFloatTypes(&.{f32}, &.{ i23, i32 })) |F| {
        try testing.expectEqual(
            F.init(0x2),
            try F.parse("0b1.111111111111111111111111"),
        );
        try testing.expectEqual(
            F.init(0x1.fffffe),
            try F.parse("0b1.11111111111111111111111011111111111111111111111"),
        );
        try testing.expectEqual(
            F.init(0x1.fffffc),
            try F.parse("0b1.111111111111111111111101"),
        );
        try testing.expectEqual(
            F.init(0x1.fffffe),
            try F.parse("0b1.111111111111111111111101000000000000000000000001"),
        );

        try testing.expectEqual(
            F.init(0x2),
            try F.parse("0x1.ffffff"),
        );
        try testing.expectEqual(
            F.init(0x1.fffffe),
            try F.parse("0x1.fffffefffffffffffffffffffffffffffffffffffffffff"),
        );
        try testing.expectEqual(
            F.init(0x1.fffffc),
            try F.parse("0x1.fffffd"),
        );
        try testing.expectEqual(
            F.init(0x1.fffffe),
            try F.parse("0x1.fffffd00000000000000000000000000000000000000001"),
        );
    }
}
