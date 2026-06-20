const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const assert = std.debug.assert;
const Reader = std.Io.Reader;

const int_math = @import("int_math.zig");

const OverflowError = error{ Underflow, Overflow };

fn SignificandString(comptime max_digit_count: usize) type {
    return struct {
        digits: [max_digit_count]u8,
        digit_count: usize,
        digit_point: isize,

        pub fn toString(self: *const @This()) []const u8 {
            return self.digits[0..self.digit_count];
        }
    };
}

fn MantissaInt(T: type) type {
    return switch (T) {
        f16, f32, f64 => u64,
        f80, f128 => u128,
        else => @compileError("Unsupported type"),
    };
}

/// Returns the number of leading zeros discarded.
fn discardLeadingZeros(reader: *Reader) usize {
    assert(reader.end == reader.buffer.len);

    const leading_zero_count = std.mem.indexOfNone(u8, reader.buffered(), "0") orelse reader.bufferedLen();
    reader.toss(leading_zero_count);
    return leading_zero_count;
}

/// Peeks the next digit from `reader`, skipping a `_` if needed.
fn scanDigit(reader: *Reader, comptime base: u8) fmt.ParseFloatError!?u8 {
    assert(reader.end == reader.buffer.len);

    if (reader.bufferedLen() == 0) {
        return null;
    }

    const i: usize = if (reader.bufferedLen() >= 2 and reader.buffered()[0] == '_') 1 else 0;
    const d = switch (base) {
        2 => switch (reader.buffered()[i]) {
            '0'...'1' => |c| c - '0',
            // Cannot have 2 underscores in a row
            '_' => return error.InvalidCharacter,
            else => return null,
        },
        8 => switch (reader.buffered()[i]) {
            '0'...'7' => |c| c - '0',
            // Cannot have 2 underscores in a row
            '_' => return error.InvalidCharacter,
            else => return null,
        },
        10 => switch (reader.buffered()[i]) {
            '0'...'9' => |c| c - '0',
            // Cannot have 2 underscores in a row
            '_' => return error.InvalidCharacter,
            else => return null,
        },
        16 => switch (reader.buffered()[i]) {
            '0'...'9' => |c| c - '0',
            'A'...'F' => |c| c - 'A' + 10,
            'a'...'f' => |c| c - 'a' + 10,
            // Cannot have 2 underscores in a row
            '_' => return error.InvalidCharacter,
            else => return null,
        },
        else => @compileError("Unsupported base"),
    };
    assert(d < base);

    reader.toss(i + 1);
    return d;
}

/// Puts a continuous stream of digits from `reader` into `buf`, skipping `_` characters.
/// Returns the number of digits parsed.
fn takeDigits(reader: *Reader, buf: []u8, comptime base: u8) fmt.ParseFloatError!usize {
    switch (reader.peekByte() catch return 0) {
        '_' => return error.InvalidCharacter,
        else => {},
    }

    var i: usize = 0;
    while (try scanDigit(reader, base)) |d| {
        buf[i] = d;
        i += 1;
        if (i >= buf.len) break;
    }
    while (try scanDigit(reader, base)) |d| {
        // Keep sticky bit for rounding
        buf[buf.len - 1] |= @intFromBool(d != 0);
        i += 1;
    }
    return i;
}

fn parseSignificand(
    comptime base: u8,
    comptime max_digit_count: usize,
    comptime exponent_char: u8,
    reader: *Reader,
) fmt.ParseFloatError!SignificandString(max_digit_count) {
    // Discard leading zeros
    var has_leading_zero = discardLeadingZeros(reader) > 0;

    var digits: [max_digit_count]u8 = undefined;
    var digit_point: isize = @intCast(try takeDigits(reader, &digits, base));
    var digit_count: usize = @intCast(@min(max_digit_count, digit_point));
    if (std.mem.startsWith(u8, reader.buffered(), ".")) {
        reader.toss(1);
        if (digit_count == 0) {
            // .000123... case
            digit_point = -@as(isize, @intCast(discardLeadingZeros(reader)));
            has_leading_zero = has_leading_zero or (digit_point < 0);
        }
        const remaining = digits[digit_count..];
        const frac_digits = try takeDigits(reader, remaining, base);
        // Trim trailing zeros
        digit_count += std.mem.trimEnd(u8, remaining[0..@min(remaining.len, frac_digits)], &.{0}).len;
    }
    if (!has_leading_zero and digit_count == 0) {
        return error.InvalidCharacter;
    }

    // String was all zeros
    if (digit_count == 0) {
        if (std.ascii.startsWithIgnoreCase(reader.buffered(), &.{exponent_char})) {
            // Discard exponent
            reader.toss(1);
            while (try scanDigit(reader, 10)) |_| {}
        }
    }

    return .{
        .digits = digits,
        .digit_count = digit_count,
        .digit_point = digit_point,
    };
}

fn parseExponentDigits(T: type, reader: *Reader, comptime negative: bool) (fmt.ParseFloatError || OverflowError)!T {
    var exponent: T = try scanDigit(reader, 10) orelse return error.InvalidCharacter;
    if (negative) {
        exponent = -exponent;
    }

    const add = if (negative) math.sub else math.add;
    const overflow_error = if (negative) error.Underflow else error.Overflow;
    while (try scanDigit(reader, 10)) |d| {
        // Consume remaining digits on overflow
        errdefer while (true) {
            _ = scanDigit(reader, 10) catch break orelse break;
        };

        exponent = math.mul(T, exponent, 10) catch return overflow_error;
        exponent = add(T, exponent, d) catch return overflow_error;
    }
    return exponent;
}

fn parseExponent(T: type, reader: *Reader, digit_point: T) (fmt.ParseFloatError || OverflowError)!T {
    const negative = std.mem.startsWith(u8, reader.buffered(), "-");
    if (negative or std.mem.startsWith(u8, reader.buffered(), "+")) {
        reader.toss(1);
    }
    if (std.mem.startsWith(u8, reader.buffered(), "_")) return error.InvalidCharacter;

    const exponent: T = if (negative)
        try parseExponentDigits(T, reader, true)
    else
        try parseExponentDigits(T, reader, false);
    return math.add(T, exponent, digit_point) catch {
        return if (negative) error.Underflow else error.Overflow;
    };
}

/// Parses a floating point number with a `base` that is a power of 2.
/// Returns a tuple containing the normalized significand and exponent,
/// such that `abs(significand)` is in the interval `[1, 2)` and the value
/// of the float is `significand * 2^exponent`.
///
/// `reader` is assumed to come from `std.Io.Reader.fixed`.
pub fn parsePowerOf2Base(
    S: type,
    E: type,
    comptime base: u8,
    reader: *Reader,
) (Reader.Error || fmt.ParseFloatError)!struct { S, E } {
    comptime assert(base > 1);
    comptime assert(math.isPowerOfTwo(base));

    const C = @Int(.unsigned, @typeInfo(S).float.bits);
    const M = MantissaInt(S);
    const bits_per_digit: comptime_int = comptime math.log2(base);
    // 2 Extra bits needed for rounding
    const bit_width_with_rounding = math.floatFractionalBits(S) + 3;
    const max_digit_count = (bit_width_with_rounding + 2 * bits_per_digit - 2) / bits_per_digit;

    const sig_str = try parseSignificand(base, max_digit_count, 'p', reader);
    // String was all zeros
    if (sig_str.digit_count == 0) {
        return .{ 0, 0 };
    }

    // Adjust binary point
    var binary_point = sig_str.digit_point * bits_per_digit;
    binary_point -= @clz(sig_str.digits[0]) - (8 - bits_per_digit);
    binary_point -= 1;

    var mantissa: M = 0;
    for (sig_str.toString()) |d| {
        mantissa <<= bits_per_digit;
        mantissa |= @as(M, d);
    }
    assert(mantissa != 0);

    // Align mantissa
    const shift = @as(i32, @clz(mantissa)) - (@typeInfo(M).int.bits - bit_width_with_rounding);
    if (shift >= 0) {
        mantissa <<= @intCast(shift);
    } else {
        const dropped_mask = (@as(M, 1) << @intCast(-shift)) - 1;
        const dropped_bits = mantissa & dropped_mask;
        mantissa >>= @intCast(-shift);
        // Keep sticky bit for rounding
        mantissa |= @intFromBool(dropped_bits != 0);
    }
    // Round to nearest, tie to even
    if (mantissa & 0b11 == 0b11) {
        mantissa += 0b100;
    } else if (mantissa & 0b11 == 0b10) {
        mantissa += mantissa & 0b100;
    }
    // Drop rounding bits
    mantissa >>= 2;
    // Handle overflow
    if (mantissa >= @as(M, 1) << (math.floatFractionalBits(S) + 1)) {
        mantissa >>= 1;
        binary_point += 1;
    }
    // Remove implicit one
    assert(mantissa < @as(M, 1) << (math.floatMantissaBits(S) + 1));
    if (math.floatMantissaBits(S) == math.floatFractionalBits(S)) {
        mantissa &= ~(@as(M, 1) << math.floatMantissaBits(S));
    }
    // Insert biased 0 exponent
    const s_repr: C = @as(C, math.floatExponentMax(S) << math.floatMantissaBits(S)) | @as(C, @truncate(mantissa));
    const significand: S = @bitCast(s_repr);

    const EPlus = math.IntFittingRange(
        math.minInt(E) + math.minInt(isize),
        math.maxInt(E) + math.maxInt(isize),
    );
    const exponent: EPlus = if (std.ascii.startsWithIgnoreCase(reader.buffered(), "p")) exponent: {
        reader.toss(1);
        break :exponent parseExponent(EPlus, reader, binary_point) catch |err| switch (err) {
            error.Overflow => return .{ math.inf(S), 0 },
            error.Underflow => return .{ 0, 0 },
            error.InvalidCharacter => return error.InvalidCharacter,
        };
    } else binary_point;

    if (exponent < math.minInt(E)) {
        return .{ 0, 0 };
    }
    if (exponent > math.maxInt(E)) {
        return .{ math.inf(S), 0 };
    }
    return .{ significand, @intCast(exponent) };
}

// Returns `floor(log10(2) * 2^(b - 1))`, where `b` is the number of bits in `T`,
// or returns a value one more than that.
fn floor_log10_2pown(T: type) T {
    switch (@typeInfo(T).int.bits) {
        0...2 => return 0,
        3 => return 1,
        else => {},
    }

    const bits = @typeInfo(T).int.bits - 1;
    @setEvalBranchQuota(5 * bits);
    // Too low when the fractional part is small
    const floored = int_math.inverse(int_math.log2(bits, 10) + 1) >> 1;
    return floored + 1;
}

/// Parses a base-10 floating point number.
/// Returns a tuple containing the normalized significand and exponent,
/// such that `abs(significand)` is in the interval `[1, 2)` and the value
/// of the float is `significand * 2^exponent`.
///
/// `reader` is assumed to come from `std.Io.Reader.fixed`.
pub fn parseBase10(
    S: type,
    E: type,
    reader: *Reader,
) (Reader.Error || fmt.ParseFloatError)!struct { S, E } {
    const M = MantissaInt(S);
    const C = @Int(.unsigned, @typeInfo(S).float.bits);
    const Cx2 = @Int(
        .unsigned,
        @max(@typeInfo(M).int.bits, 2 * @typeInfo(S).float.bits),
    );
    const max_digit_count = switch (M) {
        u64 => 19,
        u128 => 38,
        else => unreachable,
    } + 1; // Add 1 for sticky bit

    var sig_str = try parseSignificand(10, max_digit_count, 'e', reader);
    // String was all zeros
    if (sig_str.digit_count == 0) return .{ 0, 0 };
    const sticky_bit = sig_str.digit_count == max_digit_count and sig_str.digits[max_digit_count - 1] > 0;
    sig_str.digit_count = @min(sig_str.digit_count, max_digit_count - 1);

    const EPlus = math.IntFittingRange(
        math.minInt(E) + math.minInt(isize),
        math.maxInt(E) + math.maxInt(usize),
    );
    const decimal_point = sig_str.digit_point - @as(EPlus, sig_str.digit_count);
    const e10: EPlus = if (std.ascii.startsWithIgnoreCase(reader.buffered(), "e")) exponent: {
        reader.toss(1);
        // The base-2 exponent has larger magnitude than the base-10 exponent,
        // so an overflow here is always an overflow for the final result.
        break :exponent parseExponent(EPlus, reader, decimal_point) catch |err| switch (err) {
            error.Overflow => return .{ math.inf(S), 0 },
            error.Underflow => return .{ 0, 0 },
            error.InvalidCharacter => return error.InvalidCharacter,
        };
    } else decimal_point;

    const max_exp = comptime floor_log10_2pown(E);
    const norm_e10 = e10 + (sig_str.digit_count - 1);
    if (norm_e10 < -max_exp - 1) return .{ 0, 0 };
    if (norm_e10 > max_exp) return .{ math.inf(S), 0 };

    var m10: M = 0;
    for (sig_str.toString()) |d| {
        m10 *= 10;
        m10 += @as(M, d);
    }
    assert(m10 != 0);
    const m10_lz = @clz(m10);
    m10 <<= @intCast(m10_lz);

    var m2: Cx2 = blk: {
        const Cx3 = @Int(.unsigned, @typeInfo(M).int.bits + @typeInfo(Cx2).int.bits);
        const m = @as(Cx3, m10) * int_math.pow10(Cx2, math.floatFractionalBits(S) + 1, e10);
        // pow10 can be off by a few bits, so we discard the inaccurate low bits
        break :blk @truncate((m >> @typeInfo(M).int.bits) + @intFromBool(sticky_bit));
    };
    // Align mantissa
    const m2_msb: u1 = @truncate(m2 >> (@typeInfo(Cx2).int.bits - 1));
    m2 <<= 1 - m2_msb;
    assert(m2 >> (@typeInfo(Cx2).int.bits - 1) == 1);

    var e2 = blk: {
        const guard_bits = 26;
        const Ex3 = int_math.TryInt(
            .signed,
            @max(32, 2 * @typeInfo(E).int.bits + guard_bits + 1),
        ) orelse @compileError("Too many bits");
        @setEvalBranchQuota(5 * @typeInfo(Ex3).int.bits);
        const @"log2(10)" = comptime int_math.log2(@typeInfo(E).int.bits + guard_bits + 2, 10);
        const exp = (@as(Ex3, @intCast(e10)) * @"log2(10)") >> (@typeInfo(E).int.bits + guard_bits);
        break :blk exp + @as(Ex3, m2_msb) - m10_lz + @typeInfo(M).int.bits - 1;
    };

    const frac_bits: comptime_int = @typeInfo(Cx2).int.bits - math.floatFractionalBits(S) - 1;
    const dropped_mask = (@as(Cx2, 1) << (frac_bits - 2)) - 1;
    const dropped_bits = m2 & dropped_mask;
    // Add 1 bit for rounding, 1 for sticky
    var s_repr: C = @truncate(m2 >> (frac_bits - 2));
    s_repr |= @intFromBool(sticky_bit or dropped_bits != 0); // Sticky bit
    // Round to nearest, tie to even
    if (s_repr & 0b11 == 0b11) {
        s_repr += 0b100;
    } else if (s_repr & 0b11 == 0b10) {
        s_repr += s_repr & 0b100;
    }
    // Drop rounding bits
    s_repr >>= 2;
    // Handle overflow
    if (s_repr >= @as(C, 1) << (math.floatFractionalBits(S) + 1)) {
        s_repr >>= 1;
        e2 += 1;
    }
    if (e2 < math.minInt(E)) return .{ 0, 0 };
    if (e2 > math.maxInt(E)) return .{ math.inf(S), 0 };

    // Remove implicit one
    if (math.floatMantissaBits(S) == math.floatFractionalBits(S)) {
        s_repr &= ~(@as(C, 1) << math.floatMantissaBits(S));
    }
    // Insert biased 0 exponent
    s_repr |= math.floatExponentMax(S) << math.floatMantissaBits(S);

    return .{ @bitCast(s_repr), @intCast(e2) };
}
