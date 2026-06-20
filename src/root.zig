const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const testing = std.testing;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

// Use software implementation of exp2 and log2 instead of @exp2 and @log2
// as those may use a hardware instruction which may not always be the same.
const _exp2 = (struct {
    fn f(x: anytype) @TypeOf(x) {
        return @import("exp2.zig").exp2(x, false);
    }
}).f;
const _log2 = @import("log2.zig").log2;
const formatting = @import("format.zig");
const parsing = @import("parse.zig");
const schubfach = @import("schubfach.zig");
const test_utils = @import("test_utils.zig");

pub const Options = struct {
    /// The floating-point type used for the significand.
    Significand: type,
    /// The signed integer type used for the exponent.
    Exponent: type,
    /// Whether to bake constants used for rendering decimal representations more quickly.
    ///
    /// This should only be disabled to increase compilation speed.
    /// Binary sizes are smaller when this is enabled as the baked constants
    /// take up less space than the code for generating them at runtime.
    bake_render: bool = @import("builtin").mode != .Debug,
};

/// Represents a floating-point number as `significand * 2^exponent`.
/// `abs(significand)` is in the interval `[1, 2)`.
///
/// Special cases:
///  - `+-0   => significand = +-0,   exponent = 0`
///  - `+-inf => significand = +-inf, exponent = 0`
///  - `nan   => significand = nan,   exponent = 0`
pub fn BigFloat(comptime float_options: Options) type {
    const S = float_options.Significand;
    const E = float_options.Exponent;
    @setEvalBranchQuota(10000);
    if (@typeInfo(S) != .float) @compileError("significand must be a float");
    switch (@typeInfo(E)) {
        .int => |info| if (info.signedness != .signed) @compileError("exponent must be a signed int"),
        else => @compileError("exponent must be a signed int"),
    }

    const Render = schubfach.Render(S, E, float_options.bake_render);

    return packed struct {
        comptime {
            @setFloatMode(.strict);
        }

        /// The significand, normalized to the range `[1, 2)`.
        /// `normalize` must be called after modifying this field directly.
        significand: S,
        /// The base-2 exponent. `normalize` must be called after modifying this field directly.
        exponent: E,

        const Self = @This();

        pub const Decimal = Render.Decimal;

        // zig fmt: off
        pub const inf: Self =       .{ .significand = math.inf(S),             .exponent = 0 };
        pub const nan: Self =       .{ .significand = math.nan(S),             .exponent = 0 };
        /// Largest value smaller than `+inf`.
        /// The smallest value larger than `-inf` is `max_value.neg()`.
        pub const max_value: Self = .{ .significand = math.nextAfter(S, 2, 0), .exponent = math.maxInt(E) };
        /// Smallest value larger than `+0`.
        pub const min_value: Self = .{ .significand = 1,                       .exponent = math.minInt(E) };
        // zig fmt: on

        const zero: Self = .{ .significand = 0, .exponent = 0 };
        const one: Self = .{ .significand = 1, .exponent = 0 };

        /// Returns a `BigFloat` with the closest representable value to `x`.
        /// Use `initExact` if you want an exact conversion.
        ///
        /// Special cases:
        ///  - `+-inf => +-inf`
        ///  - `nan   => nan`
        pub fn init(x: anytype) Self {
            const T = @TypeOf(x);
            switch (@typeInfo(T)) {
                .int => |info| {
                    if (x == 0) return zero;

                    const Unsigned = @Int(.unsigned, info.bits);
                    // Zig ints go up to 65,535 bits, so using i32 is always safe
                    var exponent: i32 = math.log2_int(Unsigned, @abs(x));

                    const shift = @max(0, exponent - math.floatFractionalBits(S));
                    const frac_mask = (@as(Unsigned, 1) << @intCast(shift)) - 1;
                    const half = frac_mask >> 1;
                    const frac = @as(Unsigned, @bitCast(x)) & frac_mask;
                    // Ties are rounded away from zero
                    const round_up: T = @intFromBool(frac > half);

                    // Bit shift to ensure x fits in the range of S
                    var significand: S = @floatFromInt((x >> @intCast(shift)) + round_up);
                    significand = math.ldexp(significand, shift - exponent);
                    if (significand == 2) {
                        significand = 1;
                        exponent += 1;
                    }
                    if (exponent > math.maxInt(E)) {
                        return if (x > 0) inf else inf.neg();
                    }

                    return .{
                        .significand = significand,
                        .exponent = @intCast(exponent),
                    };
                },
                .comptime_int => {
                    if (x == 0) return zero;
                    const exponent = math.log2(@abs(x));
                    const Int = @Int(.signed, exponent + 2);
                    return comptime init(@as(Int, x));
                },
                .float => {
                    const fr = math.frexp(x);
                    const significand, const exponent = blk: {
                        var significand: S = @floatCast(2 * fr.significand);
                        var exponent = fr.exponent - 1;
                        if (significand == 2) {
                            significand = 1;
                            exponent += 1;
                        }
                        break :blk .{ significand, exponent };
                    };

                    comptime assert(nan.exponent == inf.exponent);
                    if (math.isNan(significand) or math.isInf(significand)) {
                        return .{ .significand = significand, .exponent = nan.exponent };
                    }
                    if (significand == 0 or exponent < math.minInt(E)) return zero.copysign(significand);
                    if (exponent > math.maxInt(E)) return inf.copysign(significand);

                    return .{
                        .significand = significand,
                        .exponent = @intCast(exponent),
                    };
                },
                .comptime_float => {
                    // comptime_float internally is a f128; this preserves precision.
                    return comptime init(@as(f128, x));
                },
                else => @compileError("x must be an int or float"),
            }
        }

        /// Returns a `BigFloat` with the exact same value as `x`.
        /// Use `init` if you want a lossy conversion.
        ///
        /// Special cases:
        ///  - `+-inf => +-inf`
        ///  - `nan   => nan`
        pub fn initExact(x: anytype) ?Self {
            return if (canRepresentExact(x)) .init(x) else null;
        }

        /// Converts `self` to the closest representable value of `FloatT`.
        pub fn toFloat(self: Self, FloatT: type) FloatT {
            comptime assert(@typeInfo(FloatT) == .float);

            const f: FloatT = @floatCast(self.significand);
            return math.ldexp(f, math.lossyCast(i32, self.exponent));
        }

        // Returns whether `x` can be represented exactly by `BigFloat`.
        pub fn canRepresentExact(x: anytype) bool {
            if (x == 0) return true;

            const T = @TypeOf(x);
            switch (@typeInfo(T)) {
                .int => |info| {
                    const Unsigned = @Int(.unsigned, info.bits);
                    const log2_x = math.log2_int(Unsigned, @abs(x));
                    const frac_bits_needed = @as(i32, log2_x) - @ctz(x);
                    // Precision check
                    if (frac_bits_needed > math.floatFractionalBits(S)) return false;
                    // Size check
                    return log2_x <= math.maxInt(E);
                },
                .comptime_int => {
                    const exponent = math.log2(@abs(x));
                    const Int = @Int(.signed, exponent + 2);
                    return comptime canRepresentExact(@as(Int, x));
                },
                .float => {
                    if (math.isInf(x) or math.isNan(x)) return true;
                    const lossy = init(x).toFloat(T);
                    return lossy == x;
                },
                .comptime_float => {
                    // comptime_float internally is a f128
                    return comptime canRepresentExact(@as(f128, x));
                },
                else => @compileError("x must be an int or float"),
            }
        }

        fn parsePartialInfOrNan(str: []const u8, n: *usize) ?Self {
            if (std.ascii.startsWithIgnoreCase(str, "inf")) {
                n.* = 3;
                if (std.ascii.startsWithIgnoreCase(str[3..], "inity")) {
                    n.* = 8;
                }
                return inf;
            }
            if (std.ascii.startsWithIgnoreCase(str, "nan")) {
                n.* = 3;
                return nan;
            }
            return null;
        }

        fn parseInfOrNan(str: []const u8) ?Self {
            var consumed: usize = 0;
            if (parsePartialInfOrNan(str, &consumed)) |special| {
                if (str.len == consumed) {
                    return special;
                }
            }
            return null;
        }

        /// Parses a string into the nearest `BigFloat`. Ties are broken by rounding to even.
        ///  - A prefix of "0b" implies base 2,
        ///  - A prefix of "0o" implies base 8,
        ///  - A prefix of "0x" implies base 16,
        ///  - Otherwise base 10 is assumed.
        ///
        /// Base-10 formats are not guaranteed to round correctly.
        /// Base-10 formats are not guaranteed to roundtrip when used with `format`.
        /// Use the hexadecimal format if exact roundtripping is needed.
        pub fn parse(str: []const u8) std.fmt.ParseFloatError!Self {
            var r: Reader = .fixed(str);
            const negative = std.mem.startsWith(u8, str, "-");
            if (negative or std.mem.startsWith(u8, str, "+")) {
                r.toss(1);
            }

            if (parseInfOrNan(r.buffered())) |special| {
                return if (negative) special.neg() else special;
            }

            const s, const e = blk: {
                if (r.bufferedLen() >= 2 and r.buffered()[0] == '0') {
                    const base_prefix = r.buffered()[1];
                    switch (base_prefix) {
                        'B', 'b' => {
                            r.toss(2);
                            break :blk parsing.parsePowerOf2Base(S, E, 2, &r);
                        },
                        'O', 'o' => {
                            r.toss(2);
                            break :blk parsing.parsePowerOf2Base(S, E, 8, &r);
                        },
                        'X', 'x' => {
                            r.toss(2);
                            break :blk parsing.parsePowerOf2Base(S, E, 16, &r);
                        },
                        else => {},
                    }
                }

                break :blk parsing.parseBase10(S, E, &r);
            } catch |err| switch (err) {
                error.ReadFailed => unreachable,
                else => return error.InvalidCharacter,
            };

            assert(!math.isNan(s));
            if (s == 0) {
                assert(e == zero.exponent);
            } else if (math.isInf(s)) {
                assert(e == inf.exponent);
            } else assert(1 <= s and s < 2);
            if (r.seek < str.len) {
                return error.InvalidCharacter;
            }

            return .{
                .significand = if (negative) -s else s,
                .exponent = e,
            };
        }

        /// Returns the decimal scientific representation of `self`.
        /// The result is not normalized, i.e., the digits may have trailing zeros.
        ///
        /// The result is not guaranteed to always be rounded correctly (although it almost always is).
        pub fn toDecimal(self: Self) Decimal {
            assert(self.isFinite());

            if (self.significand == 0) return .{ .digits = 0, .exponent = 0 };
            assert(1 <= self.significand and self.significand < 2);

            return Render.toDecimal(self.significand, self.exponent);
        }

        /// Returns the maximum buffer size required to format a `BigFloat` with the given options.
        pub fn maxFormatLength(options: std.fmt.Number) usize {
            const e_bits: comptime_int = @typeInfo(E).int.bits;
            const log10_2f = 0.3010299956639811952137388947244930;
            const maxBinaryExponentDigitCount: comptime_int = 2 + @floor(log10_2f * @as(f128, e_bits - 1));

            const width = switch (options.mode) {
                .decimal =>
                // 2^(e_bits - 3) < log10(2) * 2^(e_bits - 1) < 2^(e_bits - 2)
                if (e_bits - 3 >= @typeInfo(usize).int.bits)
                    math.maxInt(usize)
                else
                    // When p is null, the longest value is `min_value`.
                    // When p is non-null, the longest value is `max_value`.
                    1 + // Negative sign
                        1 + // Decimal point
                        // Leading zeros when p is null. Otherwise, the integer part.
                        @as(usize, @intFromFloat(@ceil(log10_2f * math.ldexp(@as(f64, 1.0), e_bits - 1)))) +
                        // Non-zero digits when p is null. Otherwise, the fractional part.
                        (if (options.precision) |p| p else Decimal.maxDigitCount),
                .scientific => 1 + // Negative sign
                    1 + // Decimal point
                    (if (options.precision) |p| p + 1 else Decimal.maxDigitCount) + // Significand
                    1 + // 'e'
                    Decimal.maxExponentDigitCount,
                .binary => 1 + // Negative sign
                    2 + // '0b'
                    1 + // Integer part
                    1 + // Binary point
                    // Fractional part
                    (if (options.precision) |p| p else math.floatFractionalBits(S)) +
                    1 + // 'p'
                    maxBinaryExponentDigitCount,
                .octal => 1 + // Negative sign
                    2 + // '0o'
                    1 + // Integer part
                    1 + // Octal point
                    // Fractional part
                    (if (options.precision) |p| p else (math.floatFractionalBits(S) + 2) / 3) +
                    1 + // 'p'
                    maxBinaryExponentDigitCount,
                .hex => 1 + // Negative sign
                    2 + // '0x'
                    1 + // Integer part
                    1 + // Hex point
                    // Fractional part
                    (if (options.precision) |p| p else (math.floatFractionalBits(S) + 3) / 4) +
                    1 + // 'p'
                    maxBinaryExponentDigitCount,
            };
            // The longest special cases have length 4 (-inf, -nan)
            return @max(width, 4, options.width orelse 0);
        }

        /// The default formatting function. Called when using the `{f}` format specifier.
        ///
        /// Base-10 formats are not guaranteed to always round correctly (although they almost always do).
        pub fn format(self: Self, writer: *Writer) Writer.Error!void {
            // TODO: change the numbers to follow std when this PR is merged.
            // https://github.com/ziglang/zig/pull/22971#issuecomment-2676157243
            const decimal_min: Self = .init(1e-6);
            const decimal_max: Self = .init(1e15);
            if (self.significand != 0 and (self.abs().lt(decimal_min) or self.abs().gte(decimal_max))) {
                return self.formatNumber(writer, .{ .mode = .scientific });
            }
            return self.formatNumber(writer, .{ .mode = .decimal });
        }

        /// Formats `self` according to `options`. It is recommended to use a format string instead.
        ///
        /// Base-10 formats are not guaranteed to always round correctly (although they almost always do).
        pub fn formatNumber(self: Self, writer: *Writer, options: std.fmt.Number) Writer.Error!void {
            if (options.width == null) return formatting.formatNoWidth(Decimal.maxDigitCount, self, writer, options);

            // If possible, use writer's buffer to align without printing twice.
            const remaining_capacity = writer.buffer.len - writer.end;
            if (remaining_capacity >= maxFormatLength(options)) {
                const start = writer.end;
                try formatting.formatNoWidth(Decimal.maxDigitCount, self, writer, options);
                const len = writer.end - start;
                const left_padding, const right_padding = formatting.calculatePadding(len, options);
                if (left_padding != 0) {
                    @memmove(writer.buffer[start + left_padding ..][0..len], writer.buffer[start..writer.end]);
                }
                @memset(writer.buffer[start..][0..left_padding], options.fill);
                @memset(writer.buffer[start + left_padding + len ..][0..right_padding], options.fill);
                writer.end += left_padding + right_padding;
                return;
            }

            var discard_writer: Writer.Discarding = .init(&.{});
            formatting.formatNoWidth(Decimal.maxDigitCount, self, &discard_writer.writer, options) catch unreachable;
            const len: usize = @intCast(discard_writer.fullCount());

            const left_padding, const right_padding = formatting.calculatePadding(len, options);
            try writer.splatByteAll(options.fill, left_padding);
            try formatting.formatNoWidth(Decimal.maxDigitCount, self, writer, options);
            try writer.splatByteAll(options.fill, right_padding);
        }

        /// Returns -1, 0, or 1.
        pub fn sign(self: Self) S {
            return math.sign(self.significand);
        }

        /// Returns whether `self` is negative or negative 0.
        pub fn signBit(self: Self) bool {
            return math.signbit(self.significand);
        }

        /// Returns a value with the magnitude of `magnitude` and the sign of `_sign`.
        pub fn copysign(magnitude: Self, _sign: S) Self {
            return .{
                .significand = math.copysign(magnitude.significand, _sign),
                .exponent = magnitude.exponent,
            };
        }

        /// Returns whether `self` is an infinity, ignoring sign.
        pub fn isInf(self: Self) bool {
            return math.isInf(self.significand);
        }

        /// Returns whether `self` is NaN.
        pub fn isNan(self: Self) bool {
            return math.isNan(self.significand);
        }

        /// Returns whether `self` is a finite value.
        pub fn isFinite(self: Self) bool {
            return math.isFinite(self.significand);
        }

        /// Returns whether `self` is in canonical form.
        ///
        /// - For +-0, +-inf, and nan, the exponent must be 0.
        /// - For all other values, `abs(significand)` must be in the interval [1, 2).
        pub fn isCanonical(self: Self) bool {
            if (!self.isFinite() or self.significand == 0) {
                return self.exponent == 0;
            } else {
                return 1.0 <= @abs(self.significand) and @abs(self.significand) < 2.0;
            }
        }

        /// Returns whether `lhs` and `rhs` have equal value.
        ///
        /// NaN values are never considered equal to any value.
        pub fn eql(lhs: Self, rhs: Self) bool {
            return lhs.significand == rhs.significand and lhs.exponent == rhs.exponent;
        }

        /// Performs an approximate comparison of `lhs` and `rhs`.
        /// Returns true if the absolute difference between them is less or equal than
        /// `max(|lhs|, |rhs|) * tolerance`, where `tolerance` is a positive number greater
        /// than zero.
        ///
        /// NaN values are never considered equal to any value.
        pub fn approxEqRel(lhs: Self, rhs: Self, tolerance: S) bool {
            assert(tolerance > 0);

            // Fast paths.
            if (lhs.eql(rhs)) return true;
            if (lhs.isNan() or rhs.isNan()) return false;

            const lhs_abs = lhs.abs();
            const rhs_abs = rhs.abs();
            const abs_max = max(lhs_abs, rhs_abs);
            const abs_diff = lhs.sub(rhs).abs();
            return abs_diff.lte(abs_max.mul(.init(tolerance)));
        }

        /// Returns whether the exponents should be compared in a comparison between `a` and `b`.
        fn shouldCmpExp(a: Self, b: Self) bool {
            return a.isFinite() and b.isFinite() and
                a.sign() == b.sign() and a.exponent != b.exponent;
        }

        /// Returns whether `lhs` is greater than `rhs`.
        ///
        /// This function always returns `false` if either `lhs` or `rhs` is NaN.
        pub fn gt(lhs: Self, rhs: Self) bool {
            return if (shouldCmpExp(lhs, rhs))
                lhs.signBit() == (lhs.exponent < rhs.exponent)
            else
                lhs.significand > rhs.significand;
        }

        /// Returns whether `lhs` is greater than or euqal to `rhs`.
        ///
        /// This function always returns `false` if either `lhs` or `rhs` is NaN.
        pub fn gte(lhs: Self, rhs: Self) bool {
            return if (shouldCmpExp(lhs, rhs))
                lhs.signBit() == (lhs.exponent < rhs.exponent)
            else
                lhs.significand >= rhs.significand;
        }

        /// Returns whether `lhs` is smaller than `rhs`.
        ///
        /// This function always returns `false` if either `lhs` or `rhs` is NaN.
        pub fn lt(lhs: Self, rhs: Self) bool {
            return if (shouldCmpExp(lhs, rhs))
                lhs.signBit() == (lhs.exponent > rhs.exponent)
            else
                lhs.significand < rhs.significand;
        }

        /// Returns whether `lhs` is smaller than or equal to `rhs`.
        ///
        /// This function always returns `false` if either `lhs` or `rhs` is NaN.
        pub fn lte(lhs: Self, rhs: Self) bool {
            return if (shouldCmpExp(lhs, rhs))
                lhs.signBit() == (lhs.exponent > rhs.exponent)
            else
                lhs.significand <= rhs.significand;
        }

        /// Returns the absolute value of `self`.
        pub fn abs(self: Self) Self {
            return .{
                .significand = @abs(self.significand),
                .exponent = self.exponent,
            };
        }

        /// Returns `-self`.
        pub fn neg(self: Self) Self {
            return .{
                .significand = -self.significand,
                .exponent = self.exponent,
            };
        }

        /// Returns `1 / self`.
        /// This function only rounds once, and is as accurate as the underlying float type.
        ///
        /// Special cases:
        ///  - `nan   => nan`
        ///  - `+-0   => +-inf`
        ///  - `+-inf => +-0`
        pub fn inv(self: Self) Self {
            if (!self.isFinite() or self.significand == 0) {
                @branchHint(.unlikely);
                comptime assert(nan.exponent == inf.exponent);
                comptime assert(zero.exponent == inf.exponent);
                return .{
                    .significand = 1.0 / self.significand,
                    .exponent = inf.exponent,
                };
            }

            if (@abs(self.significand) == 1) {
                return if (self.exponent == math.minInt(E))
                    inf.copysign(self.significand)
                else
                    .{
                        .significand = self.significand,
                        .exponent = -self.exponent,
                    };
            }

            return .{
                .significand = 2.0 / self.significand,
                .exponent = -1 - self.exponent,
            };
        }

        /// Returns e where `x = s * 2^e` and `abs(s)` is in the interval `[1, 2)`.
        ///
        /// Asserts that `x` is finite and non-zero.
        fn floatExponent(x: S) i32 {
            assert(math.isFinite(x));
            assert(x != 0);

            const Int: type = @Int(.unsigned, @typeInfo(S).float.bits);
            const MantInt: type = @Int(.unsigned, math.floatMantissaBits(S));
            const ExpInt = @Int(.unsigned, math.floatExponentBits(S));
            const bias: comptime_int = (1 << (math.floatExponentBits(S) - 1)) - 1;
            const ones_place: comptime_int = math.floatMantissaBits(S) - math.floatFractionalBits(S);

            const v: Int = @bitCast(x);
            const m: MantInt = @truncate(v);
            const e: ExpInt = @truncate(v >> math.floatMantissaBits(S));

            return switch (e) {
                // subnormal
                0 => -math.floatExponentMax(S) - @as(i32, @clz(m)) + ones_place,
                // normal
                else => @as(i32, e) - bias,
            };
        }

        /// Returns x * 2^n.
        /// Asserts that `x` is normal.
        /// Asserts that the result is normal.
        fn ldexpFast(x: S, n: i32) S {
            assert(math.isNormal(x));
            {
                const result_exponent = floatExponent(x) +| n;
                // The trick below doesn't work if the result is subnormal or infinity.
                assert(result_exponent <= math.floatExponentMax(S));
                assert(result_exponent >= math.floatExponentMin(S));
            }

            const SBits = @Int(.signed, @typeInfo(S).float.bits);
            const mantissa_bits = math.floatMantissaBits(S);
            const repr: SBits = @bitCast(x);
            const exp_diff = @as(SBits, @intCast(n)) << mantissa_bits;
            return @bitCast(repr + exp_diff);
        }

        /// Normalizes the significand and exponent of `x` so that the significand is in the
        /// interval `[1, 2)`, or returns one of the special cases for zero, infinity, or NaN.
        ///
        /// `normalize` must be called after modifying the significand or exponent of `x` directly.
        pub fn normalize(x: Self) Self {
            comptime assert(nan.exponent == inf.exponent);
            if (!x.isFinite()) return .{ .significand = x.significand, .exponent = inf.exponent };
            return normalizeFinite(x);
        }

        /// Performs the same function as `normalize`, but asserts that `x.significand` is finite.
        ///
        /// This is slightly faster than `normalize` as it skips some checks.
        pub fn normalizeFinite(x: Self) Self {
            assert(x.isFinite());

            if (x.significand == 0) {
                return .{
                    .significand = x.significand,
                    .exponent = zero.exponent,
                };
            }

            const exp_offset = floatExponent(x.significand);
            const ExpInt = @Int(.signed, @as(u16, @max(
                @typeInfo(E).int.bits,
                @typeInfo(@TypeOf(exp_offset)).int.bits,
            )) + 1);
            const new_exponent = @as(ExpInt, x.exponent) + @as(ExpInt, exp_offset);
            if (new_exponent > math.maxInt(E)) {
                return inf.copysign(x.significand);
            }
            if (new_exponent < math.minInt(E)) {
                return zero.copysign(x.significand);
            }
            return .{
                .significand = math.ldexp(x.significand, -exp_offset),
                .exponent = @intCast(new_exponent),
            };
        }

        /// Returns the largest value between `lhs` and `rhs`.
        pub fn max(lhs: Self, rhs: Self) Self {
            return if (lhs.gt(rhs)) lhs else rhs;
        }

        /// Returns the smallest value between `lhs` and `rhs`.
        pub fn min(lhs: Self, rhs: Self) Self {
            return if (lhs.lt(rhs)) lhs else rhs;
        }

        /// Returns `lhs + rhs`.
        /// This function only rounds once, and is as accurate as the underlying float type.
        ///
        /// Special cases:
        ///  - `x + nan     => nan`
        ///  - `nan + y     => nan`
        ///  - `+inf + -inf => nan`
        ///  - `-inf + +inf => nan`
        ///  - `x + +-inf   => +-inf` for finite x
        ///  - `+-inf + y   => +-inf` for finite y
        pub fn add(lhs: Self, rhs: Self) Self {
            if (!lhs.isFinite() or !rhs.isFinite()) {
                comptime assert(nan.exponent == inf.exponent);
                return .{
                    .significand = lhs.significand + rhs.significand,
                    .exponent = inf.exponent,
                };
            }
            if (lhs.significand == 0 or rhs.significand == 0) {
                assert(lhs.exponent == 0 or rhs.exponent == 0);
                return .{
                    .significand = lhs.significand + rhs.significand,
                    .exponent = lhs.exponent + rhs.exponent,
                };
            }
            return if (lhs.exponent < rhs.exponent) add2(rhs, lhs) else add2(lhs, rhs);
        }

        fn add2(lhs: Self, rhs: Self) Self {
            assert(lhs.exponent >= rhs.exponent);
            assert(!lhs.isNan() and !rhs.isNan());
            assert(!lhs.isInf() and !rhs.isInf());
            assert(lhs.significand != 0 and rhs.significand != 0);

            // The exponent difference is too large, we can just return lhs
            const exp_diff = math.sub(E, lhs.exponent, rhs.exponent) catch return lhs;
            if (exp_diff > math.floatFractionalBits(S) + 2) return lhs;

            const normalized_rhs = ldexpFast(rhs.significand, @intCast(-exp_diff));
            return normalizeFinite(.{
                .significand = lhs.significand + normalized_rhs,
                .exponent = lhs.exponent,
            });
        }

        /// Returns `lhs - rhs`.
        /// This function only rounds once, and is as accurate as the underlying float type.
        ///
        /// Special cases:
        ///  - `x - nan     => nan`
        ///  - `nan - y     => nan`
        ///  - `+inf - +inf => nan`
        ///  - `-inf - -inf => nan`
        ///  - `x - +-inf   => -+inf` for finite x
        ///  - `+-inf - y   => +-inf` for finite y
        pub fn sub(lhs: Self, rhs: Self) Self {
            if (!lhs.isFinite() or !rhs.isFinite()) {
                comptime assert(nan.exponent == inf.exponent);
                return .{
                    .significand = lhs.significand - rhs.significand,
                    .exponent = inf.exponent,
                };
            }
            if (lhs.significand == 0 or rhs.significand == 0) {
                assert(lhs.exponent == 0 or rhs.exponent == 0);
                return .{
                    .significand = lhs.significand - rhs.significand,
                    .exponent = lhs.exponent + rhs.exponent,
                };
            }
            return if (lhs.exponent < rhs.exponent) sub2(rhs, lhs).neg() else sub2(lhs, rhs);
        }

        fn sub2(lhs: Self, rhs: Self) Self {
            assert(lhs.exponent >= rhs.exponent);
            assert(!lhs.isNan() and !rhs.isNan());
            assert(!lhs.isInf() and !rhs.isInf());
            assert(lhs.significand != 0 and rhs.significand != 0);

            // The exponent difference is too large, we can just return lhs
            const exp_diff = math.sub(E, lhs.exponent, rhs.exponent) catch return lhs;
            if (exp_diff > math.floatFractionalBits(S) + 2) return lhs;

            const normalized_rhs = ldexpFast(rhs.significand, @intCast(-exp_diff));
            return normalizeFinite(.{
                .significand = lhs.significand - normalized_rhs,
                .exponent = lhs.exponent,
            });
        }

        /// Returns `lhs * rhs`.
        /// This function only rounds once, and is as accurate as the underlying float type.
        ///
        /// Special cases:
        ///  - `x * nan     => nan`
        ///  - `nan * y     => nan`
        ///  - `+-inf * +-0 => nan`
        ///  - `+-0 * +-inf => nan`
        pub fn mul(lhs: Self, rhs: Self) Self {
            const significand = lhs.significand * rhs.significand;
            if (!math.isFinite(significand) or significand == 0) {
                comptime assert(nan.exponent == inf.exponent);
                comptime assert(nan.exponent == zero.exponent);
                return .{ .significand = significand, .exponent = nan.exponent };
            }

            assert(1 <= @abs(significand) and @abs(significand) < 4);
            const ExpInt = @Int(.signed, @max(32, @typeInfo(E).int.bits) + 2);
            const exp_offset = @intFromBool(@abs(significand) >= 2);
            const exponent = @as(ExpInt, lhs.exponent) + @as(ExpInt, rhs.exponent) + exp_offset;
            if (exponent > math.maxInt(E)) return inf.copysign(significand);
            if (exponent < math.minInt(E)) return zero.copysign(significand);
            return .{
                .significand = significand * ([2]S{ 1.0, 0.5 })[exp_offset],
                .exponent = @intCast(exponent),
            };
        }

        /// Returns `lhs / rhs`.
        /// This function only rounds once, and is as accurate as the underlying float type.
        ///
        /// Special cases:
        ///  - `x / nan       => nan`
        ///  - `nan / y       => nan`
        ///  - `+-inf / +-inf => nan`
        ///  - `+-x / inf     => +-0` for finite x
        ///  - `+-x / -inf    => -+0` for finite x
        ///  - `0 / 0         => nan`
        ///  - `+-x / 0       => +-inf` for x != 0
        pub fn div(lhs: Self, rhs: Self) Self {
            const significand = lhs.significand / rhs.significand;
            if (!math.isFinite(significand) or significand == 0) {
                comptime assert(nan.exponent == inf.exponent);
                comptime assert(nan.exponent == zero.exponent);
                return .{ .significand = significand, .exponent = nan.exponent };
            }

            assert(0.5 <= @abs(significand) and @abs(significand) < 2);
            const ExpInt = @Int(.signed, @max(32, @typeInfo(E).int.bits) + 2);
            const exp_offset = @intFromBool(@abs(significand) < 1);
            const exponent = @as(ExpInt, lhs.exponent) - @as(ExpInt, rhs.exponent) - exp_offset;
            if (exponent > math.maxInt(E)) return inf.copysign(significand);
            if (exponent < math.minInt(E)) return zero.copysign(significand);
            return .{
                .significand = significand * ([2]S{ 1.0, 2.0 })[exp_offset],
                .exponent = @intCast(exponent),
            };
        }

        /// Returns `base` raised to the power of `power`.
        /// For `|power| >= 1`, relative error is proportional to `log(|power|)`.
        /// For `|power| < 1`, absolute error is approximately `5e-17`.
        ///
        /// This function is faster than `powi` but usually less accurate.
        ///
        /// Special Cases:
        ///  - pow(x, +-0)    = 1
        ///  - pow(+-0, y)    = +-inf  for y an odd integer < 0
        ///  - pow(+-0, −inf) = +inf
        ///  - pow(+-0, +inf) = +0
        ///  - pow(+-0, y)    = +-0    for finite y > 0 an odd integer
        ///  - pow(−1, +-inf) = 1
        ///  - pow(+1, y)     = 1
        ///  - pow(x, +inf)   = +0     for −1 < x < 1
        ///  - pow(x, +inf)   = +inf   for x < −1 or for 1 < x (including +-inf)
        ///  - pow(x, −inf)   = +inf   for −1 < x < 1
        ///  - pow(x, −inf)   = +0     for x < −1 or for 1 < x (including +-inf)
        ///  - pow(+inf, y)   = +0     for a number y < 0
        ///  - pow(+inf, y)   = +inf   for a number y > 0
        ///  - pow(−inf, y)   = −0     for finite y < 0 an odd integer
        ///  - pow(−inf, y)   = −inf   for finite y > 0 an odd integer
        ///  - pow(−inf, y)   = +0     for finite y < 0 and not an odd integer
        ///  - pow(−inf, y)   = +inf   for finite y > 0 and not an odd integer
        ///  - pow(+-0, y)    = +inf   for finite y < 0 and not an odd integer
        ///  - pow(+-0, y)    = +0     for finite y > 0 and not an odd integer
        ///  - pow(x, y)      = nan    for finite x < 0 and finite non-integer y
        ///  - pow(x, 1)      = x
        ///  - pow(nan, y)    = nan    for y != +-0
        ///  - pow(x, nan)    = nan    for x != 1
        pub fn pow(base: Self, power: Self) Self {
            // x^y = 2^(log2(x) * y)

            if (power.significand == 0 or base.eql(one)) return one;
            // log2 and exp2 are highly unlikely to round-trip
            if (power.eql(one)) return base;
            if (base.isNan() or power.isNan()) {
                @branchHint(.unlikely);
                return nan;
            }
            if (power.isInf()) {
                return if (base.eql(comptime init(-1)))
                    one
                else if ((base.significand == 0 or base.exponent < 0) == math.isPositiveInf(power.significand))
                    zero
                else
                    inf;
            }
            if (base.isInf()) {
                return if (math.isNegativeInf(base.significand))
                    pow(comptime init(-0.0), power.neg())
                else if (power.significand < 0)
                    zero
                else
                    inf;
            }
            if (!base.signBit()) return exp2(log2(base).mul(power));

            const Int: type = @Int(.unsigned, @typeInfo(S).float.bits);
            const power_repr: Int = @bitCast(power.significand);
            const frac_mask = (@as(Int, 1) << math.floatFractionalBits(S)) - 1;
            const power_mantissa = (power_repr & frac_mask) | (1 << math.floatFractionalBits(S));
            const binary_point: math.Log2Int(Int) = @intCast(
                math.floatFractionalBits(S) -
                    math.clamp(power.exponent, -1, math.floatFractionalBits(S)),
            );
            const is_odd = ((power_mantissa >> binary_point) & 1 == 1) and
                (power.exponent <= math.floatFractionalBits(S));
            const fraction = power_mantissa & ((@as(Int, 1) << binary_point) - 1);

            if (base.significand != 0 and fraction != 0) {
                return nan;
            }
            const abs_result = exp2(log2(base.neg()).mul(power));
            return if (is_odd and fraction == 0) abs_result.neg() else abs_result;
        }

        /// Returns `base` raised to the power of `power`.
        /// Relative error is proportional to `log(|power|)`.
        ///
        /// This function is slower than `pow` but usually more accurate.
        ///
        /// Special Cases:
        ///  - powi(x, 0)    = 1
        ///  - powi(+-0, n)  = +-inf  for odd n < 0
        ///  - powi(+-0, n)  = +inf   for even n < 0
        ///  - powi(+-0, n)  = +0     for even n > 0
        ///  - powi(+-0, n)  = +-0    for odd n > 0
        ///  - powi(+inf, n) = +inf   for n > 0
        ///  - powi(−inf, n) = −inf   for odd n > 0
        ///  - powi(−inf, n) = +inf   for even n > 0
        ///  - powi(+inf, n) = +0     for n < 0
        ///  - powi(−inf, n) = −0     for odd n < 0
        ///  - powi(−inf, n) = +0     for even n < 0
        ///  - powi(nan, n)  = nan    for n != 0
        pub fn powi(base: Self, power: E) Self {
            if (power == 0) return one;

            if (power < 0) {
                const inverse: Self = base.inv();
                // -power can overflow
                const powered = powi(inverse, -1 - power);
                return powered.mul(inverse);
            }

            var result = base;
            var bit = math.log2_int(@Int(.unsigned, @typeInfo(E).int.bits -| 1), @intCast(power));
            while (bit > 0) {
                result = result.mul(result);
                bit -= 1;
                if (((power >> bit) & 1) == 1) {
                    result = result.mul(base);
                }
            }
            return result;
        }

        /// Returns 2^n.
        /// Asserts that n < 0.
        fn exp2Int(n: E) S {
            assert(n < 0);

            const mantissa_bits = math.floatMantissaBits(S);
            const fractional_bits = math.floatFractionalBits(S);

            const SBits = @Int(.unsigned, @typeInfo(S).float.bits);
            const mantissa_mask: SBits = (1 << mantissa_bits) - 1;
            const repr: SBits = @bitCast(@as(S, 1));

            const exponent = math.floatExponentMax(S);
            if (n <= -exponent) {
                if (n < -(mantissa_bits + exponent)) {
                    return 0; // Severe underflow. Return 0
                }

                // Result underflowed, we need to shift and round
                const shift: math.Log2Int(SBits) = @intCast(-exponent - n);
                const exact_tie: bool = fractional_bits + 1 == shift;
                var result: SBits = comptime (repr & mantissa_mask);

                if (S != f80) // Include integer bit
                    result |= @as(SBits, 1) << fractional_bits;
                result = @intCast(result >> shift);

                // Round result, including round-to-even for exact ties
                result = ((result + 1) >> 1) & ~@as(SBits, @intFromBool(exact_tie));
                return @as(S, @bitCast(result));
            }

            // Result is exact, and needs no shifting
            return @as(S, @bitCast(repr - (@as(SBits, @intCast(-n)) << mantissa_bits)));
        }

        /// Returns `2` raised to the power of `self`.
        ///
        /// Special cases:
        ///  - `+-0  => 1`
        ///  - `+inf => +inf`
        ///  - `-inf => 0`
        ///  - `nan  => nan`
        pub fn exp2(self: Self) Self {
            // 2^(s * 2^e) = 2^(i + f) ; 0 <= f < 1
            //             = 2^f * 2^i ; 1 <= s < 2
            // i = floor(s * 2^e)      ; i >= 0

            if (self.isNan()) {
                @branchHint(.unlikely);
                return nan;
            }
            if (self.significand == math.inf(S)) {
                @branchHint(.unlikely);
                return inf;
            }
            if (self.significand < 0) {
                return exp2(self.neg()).inv();
            }
            if (self.significand == 0) {
                return one;
            }
            if (self.exponent < 0) {
                // 0 <= s * 2^e < 1
                // 1 <= 2^(s * 2^e) < 2
                const @"2^e" = exp2Int(self.exponent);
                return .{ .significand = _exp2(self.significand * @"2^e"), .exponent = zero.exponent };
            }
            if (self.exponent >= @typeInfo(E).int.bits) {
                // Result always overflows
                return inf;
            }

            // Enough bits for E and the fractional bits of S
            const SE = @Int(.unsigned, @typeInfo(E).int.bits + math.floatFractionalBits(S));
            const SMask = @Int(.unsigned, @typeInfo(S).float.bits);
            const SInt = @Int(.unsigned, math.floatFractionalBits(S) + 1);
            const FInt = @Int(.unsigned, math.floatFractionalBits(S));
            const @"2^e" = @as(SE, 1) << @intCast(self.exponent);
            const s = @as(SInt, @truncate(@as(SMask, @bitCast(self.significand)))) | (1 << math.floatFractionalBits(S));
            const exponent = @"2^e" * s;
            if (exponent >> math.floatFractionalBits(S) > math.maxInt(E)) {
                return inf;
            }
            const i: E = @intCast(exponent >> math.floatFractionalBits(S));

            const f_mantissa: FInt = @truncate(exponent);
            const f = math.ldexp(@as(S, @floatFromInt(f_mantissa)), -math.floatFractionalBits(S));
            return .{ .significand = _exp2(f), .exponent = i };
        }

        /// Returns the base-2 logarithm of `self`.
        ///
        /// Special cases:
        ///  - `< 0  => nan`
        ///  - `+-0  => -inf`
        ///  - `+inf => +inf`
        ///  - `nan  => nan`
        pub fn log2(self: Self) Self {
            // log2(s * 2^e) = log2(s) + e

            // Use extra bits for accuracy
            const _S = switch (S) {
                f16 => f32,
                f32 => f64,
                else => S,
            };
            // Result always fits in the range of _S
            if (math.minInt(E) >= -math.floatMax(_S)) {
                return init(_log2(@as(_S, self.significand)) + @as(_S, @floatFromInt(self.exponent)));
            }
            // Result always fits in the range of f64
            if (math.minInt(E) >= -math.floatMax(f64) and @typeInfo(S).float.bits <= 64) {
                const s: f64 = _log2(@as(f64, self.significand));
                const e: f64 = @floatFromInt(self.exponent);
                return init(s + e);
            }
            return init(_log2(self.significand)).add(init(self.exponent));
        }
    };
}

test {
    testing.refAllDecls(@This());

    _ = @import("tests/init.zig");
    _ = @import("tests/to.zig");
    _ = @import("tests/parse.zig");
    _ = @import("tests/format.zig");
    _ = @import("tests/sign.zig");
    _ = @import("tests/isinf.zig");
    _ = @import("tests/isnan.zig");
    _ = @import("tests/normalize.zig");
    _ = @import("tests/unary_ops.zig");
    _ = @import("tests/compare.zig");
    _ = @import("tests/add.zig");
    _ = @import("tests/sub.zig");
    _ = @import("tests/mul.zig");
    _ = @import("tests/div.zig");
    _ = @import("tests/exp.zig");
    _ = @import("tests/log.zig");
    _ = @import("tests/pow.zig");

    _ = @import("tests/fuzz.zig");
}

test "floatExponent" {
    inline for (test_utils.bigFloatTypes(&.{ f32, f64, f80, f128 }, &.{i32})) |F| {
        try testing.expectEqual(0, F.floatExponent(1));
        try testing.expectEqual(-1, F.floatExponent(0.6));
        try testing.expectEqual(1, F.floatExponent(-2.0));
        try testing.expectEqual(119, F.floatExponent(1e36));

        try testing.expectEqual(-133, F.floatExponent(1e-40));
        try testing.expectEqual(-133, F.floatExponent(-1e-40));
    }
}
