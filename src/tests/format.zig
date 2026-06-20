const std = @import("std");
const testing = std.testing;

const BigFloat = @import("../root.zig").BigFloat;
const utils = @import("../test_utils.zig");

test "format" {
    inline for (utils.bigFloatTypes(&.{ f64, f128 }, &.{ i23, i64 })) |F| {
        // Format options are not passed down when using the default format function
        try testing.expectFmt("0", "{f}", .{F.init(0)});
        try testing.expectFmt("-0", "{f}", .{F.init(-0.0)});
        try testing.expectFmt("0", "{f:.5}", .{F.init(0)});
        try testing.expectFmt("inf", "{f}", .{F.inf});
        try testing.expectFmt("-inf", "{f}", .{F.inf.neg()});
        try testing.expectFmt("nan", "{f}", .{F.nan});
        try testing.expectFmt("-nan", "{f}", .{F.nan.neg()});
        try testing.expectFmt(
            switch (@FieldType(F, "significand")) {
                f64 => "-7.629816726897621e31",
                f128 => "-7.6298167268976215867137861343298125e31",
                else => unreachable,
            },
            "{f:.9}",
            .{F.init(-76298167268976215867137861343298.123)},
        );
        try testing.expectFmt(
            "-0.0061267346318123",
            "{f:^100.4}",
            .{F.init(-6.1267346318123e-3)},
        );
    }
}

test "formatDecimal" {
    // Crazy large numbers were verified by calculating them in log10 form in wolfram alpha
    inline for (utils.bigFloatTypes(&.{ f64, f128 }, &.{ i8, i12 })) |F| {
        try testing.expectFmt("0", "{d}", .{F.init(0)});
        try testing.expectFmt("-0", "{d}", .{F.init(-0.0)});
        try testing.expectFmt("0", "{d:.0}", .{F.init(0)});
        try testing.expectFmt("0.00000", "{d:.5}", .{F.init(0)});
        try testing.expectFmt("inf", "{d}", .{F.inf});
        try testing.expectFmt("-inf", "{d}", .{F.inf.neg()});
        try testing.expectFmt("nan", "{d}", .{F.nan});
        try testing.expectFmt("-nan", "{d}", .{F.nan.neg()});
        try testing.expectFmt("12345", "{d}", .{F.init(12345)});
        try testing.expectFmt(
            switch (@FieldType(F, "significand")) {
                f64 => "-76298167268976210000000000000000.000000000",
                f128 => "-76298167268976215867137861343298.125000000",
                else => unreachable,
            },
            "{d:.9}",
            .{F.init(-76298167268976215867137861343298.123)},
        );
        try testing.expectFmt(
            "      -0.0061       ",
            "{d:^20.4}",
            .{F.init(-6.1267346318123e-3)},
        );
        try testing.expectFmt(
            "1.2300000000000000000000000000000000000000",
            "{d:.40}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "1",
            "{d:.0}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "10",
            "{d:.0}",
            .{F.init(9.9)},
        );
        try testing.expectFmt(
            "0.0000",
            "{d:.4}",
            .{F.init(1e-10)},
        );
        try testing.expectFmt(
            "0.1",
            "{d:.1}",
            .{F.init(0.05)},
        );
        try testing.expectFmt(
            switch (@FieldType(F, "significand")) {
                f64 => "69696969696969700",
                f128 => "69696969696969696.96969696969696969",
                else => unreachable,
            },
            "{d}",
            .{F.init(69696969696969696.96969696969696969)},
        );

        var buf: [1024]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        try writer.print("{d:>.1}", .{F.init(256)});
        try testing.expectEqualStrings("256.0", writer.buffered());
    }

    const Tiny = BigFloat(.{
        .Significand = f16,
        .Exponent = i1,
        .bake_render = true,
    });
    try testing.expectFmt("0.54", "{d}", .{Tiny.init(0.54)});
    try testing.expectFmt("-1.999", "{d}", .{Tiny.max_value.neg()});
    try testing.expectFmt("1.999", "{d}", .{Tiny.max_value});
    try testing.expectFmt("-0.5", "{d}", .{Tiny.min_value.neg()});

    const Big = BigFloat(.{
        .Significand = f128,
        .Exponent = i1000,
        .bake_render = true,
    });
    try testing.expectFmt("1.2", "{d}", .{Big.init(1.2)});
    try testing.expectFmt(
        "-10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "{d}",
        .{Big.init(-1e100)},
    );
    try testing.expectFmt(
        "10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "{d}",
        .{Big.init(1e100)},
    );
    try testing.expectFmt(
        "-0.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
        "{d}",
        .{Big.init(-1e-100)},
    );
}

test "formatScientific" {
    // Crazy large numbers were verified by calculating them in log10 form in wolfram alpha
    inline for (utils.bigFloatTypes(&.{ f64, f128 }, &.{ i53, i64 })) |F| {
        try testing.expectFmt("0e0", "{e}", .{F.init(0)});
        try testing.expectFmt("-0e0", "{e}", .{F.init(-0.0)});
        try testing.expectFmt("0.00000e0", "{e:.5}", .{F.init(0)});
        try testing.expectFmt("inf", "{e}", .{F.inf});
        try testing.expectFmt("-inf", "{e}", .{F.inf.neg()});
        try testing.expectFmt("nan", "{e}", .{F.nan});
        try testing.expectFmt("-nan", "{e}", .{F.nan.neg()});
        try testing.expectFmt("1.2345e4", "{e}", .{F.init(12345)});
        try testing.expectFmt(
            "-7.629816727e35",
            "{e:.9}",
            .{F.init(-762981672689762158671378613432987234.123)},
        );
        try testing.expectFmt(
            "    -6.1267e-23     ",
            "{e:^20.4}",
            .{F.init(-6.1267346318123e-23)},
        );
        try testing.expectFmt(
            "1.2300000000000000000000000000000000000000e0",
            "{e:.40}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "1e0",
            "{e:.0}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "1e1",
            "{e:.0}",
            .{F.init(9.9)},
        );
        try testing.expectFmt(
            "3.00000000000000000000e0",
            "{e:.20}",
            .{F.init(3)},
        );
        try testing.expectFmt("6.969e69696969696969", "{e}", .{F{
            .significand = 1.1936405809786527348488982195707378,
            .exponent = 231528321764877,
        }});

        try testing.expectFmt("0e0", "{E}", .{F.init(0)});
        try testing.expectFmt("INF", "{E}", .{F.inf});
        try testing.expectFmt("-NAN", "{E}", .{F.nan.neg()});
        try testing.expectFmt("1.2345e4", "{E}", .{F.init(12345)});

        var buf: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        try writer.print("{e:>0}", .{F.init(256)});
        try testing.expectEqualStrings("2.56e2", writer.buffered());
    }

    const Tiny = BigFloat(.{
        .Significand = f16,
        .Exponent = i1,
        .bake_render = true,
    });
    try testing.expectFmt("5.4e-1", "{e}", .{Tiny.init(0.54)});
    try testing.expectFmt("-1.999e0", "{e}", .{Tiny.max_value.neg()});
    try testing.expectFmt("1.999e0", "{e}", .{Tiny.max_value});
    try testing.expectFmt("-5e-1", "{e}", .{Tiny.min_value.neg()});

    const Big = BigFloat(.{
        .Significand = f128,
        .Exponent = i1000,
        .bake_render = true,
    });
    try testing.expectFmt("1.2e0", "{e}", .{Big.init(1.2)});
    try testing.expectFmt(
        "-1.74873540141175310457335403747254e1612781156876002906875571082584823201862449472531419045065794674069106383716117052919457727193362579413227119899182498925712743046831971577883865387701955331933942161297844459829891638312939843401472423805414763286757270514940834671439119961744112646874840130936383580584822955244454679295610137107954",
        "{e}",
        .{Big.max_value.neg()},
    );
    try testing.expectFmt(
        "1.74873540141175310457335403747254e1612781156876002906875571082584823201862449472531419045065794674069106383716117052919457727193362579413227119899182498925712743046831971577883865387701955331933942161297844459829891638312939843401472423805414763286757270514940834671439119961744112646874840130936383580584822955244454679295610137107954",
        "{e}",
        .{Big.max_value},
    );
    try testing.expectFmt(
        "-5.718418001904122048746596962547775e-1612781156876002906875571082584823201862449472531419045065794674069106383716117052919457727193362579413227119899182498925712743046831971577883865387701955331933942161297844459829891638312939843401472423805414763286757270514940834671439119961744112646874840130936383580584822955244454679295610137107955",
        "{e}",
        .{Big.min_value.neg()},
    );
}

test "formatBinary" {
    inline for (utils.bigFloatTypes(&.{ f64, f128 }, &.{ i53, i64 })) |F| {
        try testing.expectFmt("0b0.0p0", "{b}", .{F.init(0)});
        try testing.expectFmt("-0b0.0p0", "{b}", .{F.init(-0.0)});
        try testing.expectFmt("0b0.00000p0", "{b:.5}", .{F.init(0)});
        try testing.expectFmt("inf", "{b}", .{F.inf});
        try testing.expectFmt("-inf", "{b}", .{F.inf.neg()});
        try testing.expectFmt("nan", "{b}", .{F.nan});
        try testing.expectFmt("-nan", "{b}", .{F.nan.neg()});
        try testing.expectFmt("aaaaaaaa-nan", "{b:a>12}", .{F.nan.neg()});
        try testing.expectFmt("0b1.1000000111001p13", "{b}", .{F.init(12345)});
        try testing.expectFmt(
            "-0b1.001001100p119",
            "{b:.9}",
            .{F.init(-762981672689762158671378613432987234.123)},
        );
        try testing.expectFmt(
            "    0b1.0011p-74    ",
            "{b:^20.4}",
            .{F.init(6.1267346318123e-23)},
        );
        try testing.expectFmt(
            "0b1.0011101011100001010001111010111000010100p0",
            "{b:.40}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "0b1p0",
            "{b:.0}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "0b1p1",
            "{b:.0}",
            .{F.init(1.9)},
        );
        try testing.expectFmt(
            "0b1.10000000000000000000p1",
            "{b:.20}",
            .{F.init(3)},
        );
        try testing.expectFmt(
            switch (@FieldType(F, "significand")) {
                f64 => "0b1.0011000110010010011011011101101001111011010101000011p231528321764877",
                f128 => "0b1.0011000110010010011011011101101001111011010101000010110011111111010000010111011111100100111100010110010100100011p231528321764877",
                else => unreachable,
            },
            "{b}",
            .{F{
                .significand = 1.1936405809786527348488982195707378,
                .exponent = 231528321764877,
            }},
        );

        var buf: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        try writer.print("{b:>0}", .{F.init(256)});
        try testing.expectEqualStrings("0b1p8", writer.buffered());
    }

    const Tiny = BigFloat(.{
        .Significand = f16,
        .Exponent = i1,
        .bake_render = true,
    });
    try testing.expectFmt("0b1.000101001p-1", "{b}", .{Tiny.init(0.54)});
    try testing.expectFmt("-0b1.1111111111p0", "{b}", .{Tiny.max_value.neg()});
    try testing.expectFmt("-0b1p-1", "{b}", .{Tiny.min_value.neg()});

    const Big = BigFloat(.{
        .Significand = f128,
        .Exponent = i1000,
        .bake_render = true,
    });
    try testing.expectFmt(
        "0b1.0011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011p0",
        "{b}",
        .{Big.init(1.2)},
    );
    try testing.expectFmt(
        "0b1.1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111p5357543035931336604742125245300009052807024058527668037218751941851755255624680612465991894078479290637973364587765734125935726428461570217992288787349287401967283887412115492710537302531185570938977091076523237491790970633699383779582771973038531457285598238843271083830214915826312193418602834034687",
        "{b}",
        .{Big.max_value},
    );
    try testing.expectFmt(
        "-0b1p-5357543035931336604742125245300009052807024058527668037218751941851755255624680612465991894078479290637973364587765734125935726428461570217992288787349287401967283887412115492710537302531185570938977091076523237491790970633699383779582771973038531457285598238843271083830214915826312193418602834034688",
        "{b}",
        .{Big.min_value.neg()},
    );
}

test "formatOctal" {
    inline for (utils.bigFloatTypes(&.{ f64, f128 }, &.{ i53, i64 })) |F| {
        try testing.expectFmt("0o0.0p0", "{o}", .{F.init(0)});
        try testing.expectFmt("-0o0.0p0", "{o}", .{F.init(-0.0)});
        try testing.expectFmt("0o0.00000p0", "{o:.5}", .{F.init(0)});
        try testing.expectFmt("inf", "{o}", .{F.inf});
        try testing.expectFmt("-inf", "{o}", .{F.inf.neg()});
        try testing.expectFmt("nan", "{o}", .{F.nan});
        try testing.expectFmt("-nan", "{o}", .{F.nan.neg()});
        try testing.expectFmt("aaaaaaaa-nan", "{o:a>12}", .{F.nan.neg()});
        try testing.expectFmt("0o1.40344p13", "{o}", .{F.init(12345)});
        try testing.expectFmt(
            "-0o1.113617152p119",
            "{o:.9}",
            .{F.init(-762981672689762158671378613432987234.123)},
        );
        try testing.expectFmt(
            "    0o1.1204p-74    ",
            "{o:^20.4}",
            .{F.init(6.1267346318123e-23)},
        );
        try testing.expectFmt(
            switch (@FieldType(F, "significand")) {
                f64 => "0o1.1656050753412172700000000000000000000000p0",
                f128 => "0o1.1656050753412172702436560507534121727000p0",
                else => unreachable,
            },
            "{o:.40}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "0o1p0",
            "{o:.0}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "0o1p1",
            "{o:.0}",
            .{F.init(1.9)},
        );
        try testing.expectFmt(
            "0o1.40000000000000000000p1",
            "{o:.20}",
            .{F.init(3)},
        );
        try testing.expectFmt(
            switch (@FieldType(F, "significand")) {
                f64 => "0o1.143111556647552414p231528321764877",
                f128 => "0o1.14311155664755241317750135762361312214p231528321764877",
                else => unreachable,
            },
            "{o}",
            .{F{
                .significand = 1.1936405809786527348488982195707378,
                .exponent = 231528321764877,
            }},
        );

        var buf: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        try writer.print("{o:>0}", .{F.init(256)});
        try testing.expectEqualStrings("0o1p8", writer.buffered());
    }

    const Tiny = BigFloat(.{
        .Significand = f16,
        .Exponent = i1,
        .bake_render = true,
    });
    try testing.expectFmt("0o1.051p-1", "{o}", .{Tiny.init(0.54)});
    try testing.expectFmt("-0o1.7774p0", "{o}", .{Tiny.max_value.neg()});
    try testing.expectFmt("-0o1p-1", "{o}", .{Tiny.min_value.neg()});

    const Big = BigFloat(.{
        .Significand = f128,
        .Exponent = i1000,
        .bake_render = true,
    });
    try testing.expectFmt(
        "0o1.14631463146314631463146314631463146314p0",
        "{o}",
        .{Big.init(1.2)},
    );
    try testing.expectFmt(
        "0o1.77777777777777777777777777777777777774p5357543035931336604742125245300009052807024058527668037218751941851755255624680612465991894078479290637973364587765734125935726428461570217992288787349287401967283887412115492710537302531185570938977091076523237491790970633699383779582771973038531457285598238843271083830214915826312193418602834034687",
        "{o}",
        .{Big.max_value},
    );
    try testing.expectFmt(
        "-0o1p-5357543035931336604742125245300009052807024058527668037218751941851755255624680612465991894078479290637973364587765734125935726428461570217992288787349287401967283887412115492710537302531185570938977091076523237491790970633699383779582771973038531457285598238843271083830214915826312193418602834034688",
        "{o}",
        .{Big.min_value.neg()},
    );
}

test "formatHex" {
    inline for (utils.bigFloatTypes(&.{ f64, f128 }, &.{ i53, i64 })) |F| {
        try testing.expectFmt("0x0.0p0", "{x}", .{F.init(0)});
        try testing.expectFmt("-0x0.0p0", "{x}", .{F.init(-0.0)});
        try testing.expectFmt("0x0.00000p0", "{x:.5}", .{F.init(0)});
        try testing.expectFmt("inf", "{x}", .{F.inf});
        try testing.expectFmt("-inf", "{x}", .{F.inf.neg()});
        try testing.expectFmt("nan", "{x}", .{F.nan});
        try testing.expectFmt("-nan", "{x}", .{F.nan.neg()});
        try testing.expectFmt("aaaaaaaa-nan", "{x:a>12}", .{F.nan.neg()});
        try testing.expectFmt("0x1.81c8p13", "{x}", .{F.init(12345)});
        try testing.expectFmt(
            "-0x1.25e3cd373p119",
            "{x:.9}",
            .{F.init(-762981672689762158671378613432987234.123)},
        );
        try testing.expectFmt(
            "    0x1.2845p-74    ",
            "{x:^20.4}",
            .{F.init(6.1267346318123e-23)},
        );
        try testing.expectFmt(
            switch (@FieldType(F, "significand")) {
                f64 => "0x1.3ae147ae147ae000000000000000000000000000p0",
                f128 => "0x1.3ae147ae147ae147ae147ae147ae000000000000p0",
                else => unreachable,
            },
            "{x:.40}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "0x1p0",
            "{x:.0}",
            .{F.init(1.23)},
        );
        try testing.expectFmt(
            "0x1p1",
            "{x:.0}",
            .{F.init(1.9)},
        );
        try testing.expectFmt(
            "0x1.80000000000000000000p1",
            "{x:.20}",
            .{F.init(3)},
        );
        try testing.expectFmt(
            switch (@FieldType(F, "significand")) {
                f64 => "0x1.31926dda7b543p231528321764877",
                f128 => "0x1.31926dda7b542cff4177e4f16523p231528321764877",
                else => unreachable,
            },
            "{x}",
            .{F{
                .significand = 1.1936405809786527348488982195707378,
                .exponent = 231528321764877,
            }},
        );

        try testing.expectFmt("0x0.0p0", "{X}", .{F.init(0)});
        try testing.expectFmt("INF", "{X}", .{F.inf});
        try testing.expectFmt("-NAN", "{X}", .{F.nan.neg()});
        try testing.expectFmt("0x1.81C8p13", "{X}", .{F.init(12345)});

        var buf: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        try writer.print("{x:>0}", .{F.init(256)});
        try testing.expectEqualStrings("0x1p8", writer.buffered());
    }

    const Tiny = BigFloat(.{
        .Significand = f16,
        .Exponent = i1,
        .bake_render = true,
    });
    try testing.expectFmt("0x1.148p-1", "{x}", .{Tiny.init(0.54)});
    try testing.expectFmt("-0x1.FFCp0", "{X}", .{Tiny.max_value.neg()});
    try testing.expectFmt("0x1.ffcp0", "{x}", .{Tiny.max_value});
    try testing.expectFmt("-0x1p-1", "{x}", .{Tiny.min_value.neg()});

    const Big = BigFloat(.{
        .Significand = f128,
        .Exponent = i1000,
        .bake_render = true,
    });
    try testing.expectFmt("0x1.3333333333333333333333333333p0", "{x}", .{Big.init(1.2)});
    try testing.expectFmt(
        "-0x1.ffffffffffffffffffffffffffffp5357543035931336604742125245300009052807024058527668037218751941851755255624680612465991894078479290637973364587765734125935726428461570217992288787349287401967283887412115492710537302531185570938977091076523237491790970633699383779582771973038531457285598238843271083830214915826312193418602834034687",
        "{x}",
        .{Big.max_value.neg()},
    );
    try testing.expectFmt(
        "0x1.FFFFFFFFFFFFFFFFFFFFFFFFFFFFp5357543035931336604742125245300009052807024058527668037218751941851755255624680612465991894078479290637973364587765734125935726428461570217992288787349287401967283887412115492710537302531185570938977091076523237491790970633699383779582771973038531457285598238843271083830214915826312193418602834034687",
        "{X}",
        .{Big.max_value},
    );
    try testing.expectFmt(
        "-0x1p-5357543035931336604742125245300009052807024058527668037218751941851755255624680612465991894078479290637973364587765734125935726428461570217992288787349287401967283887412115492710537302531185570938977091076523237491790970633699383779582771973038531457285598238843271083830214915826312193418602834034688",
        "{x}",
        .{Big.min_value.neg()},
    );
}

// Failed cases from fuzzer
test "format fuzz" {
    const BF16 = BigFloat(.{ .Significand = f16, .Exponent = i128 });
    try testing.expectFmt(
        "2.134e-31120238684812306949365838700533485735",
        "{e}",
        .{BF16{ .significand = 1.042, .exponent = -103379195206678541637689605389987816880 }},
    );
}
