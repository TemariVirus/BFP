const std = @import("std");
const assert = std.debug.assert;
const math = std.math;

pub fn TryInt(comptime signedness: std.builtin.Signedness, bits: comptime_int) ?type {
    if (bits > math.maxInt(u16)) return null;
    return @Int(signedness, bits);
}

/// Returns whether `x` is divisible by `2^n`
pub fn divisibleByPow2(T: type, x: T, n: math.Log2Int(T)) bool {
    const @"2^n" = @as(T, 1) << n;
    return x & (@"2^n" - 1) == 0;
}

/// Returns the high bits of `a * b`.
pub fn mulHigh(T: type, a: T, b: T) T {
    const bits = @typeInfo(T).int.bits;
    comptime assert(@typeInfo(T).int.signedness == .unsigned);

    // Multiplying with a wider type is faster than 3 smaller multiplications.
    if (TryInt(.unsigned, bits * 2)) |WideT| {
        const result = @as(WideT, a) * @as(WideT, b);
        return @truncate(result >> bits);
    }

    const shift = bits / 2;
    const mask = (1 << shift) - 1;
    const al = a & mask;
    const ah = a >> shift;
    const bl = b & mask;
    const bh = b >> shift;

    const lh = al * bh;
    const hl = ah * bl;
    const m, const of = @addWithOverflow(lh, hl);
    const hh = ah * bh;
    return hh + (m >> shift) + (@as(T, of) << (bits - shift));
}

/// Returns the first `bits` bits of `log2(x)` truncated.
pub fn log2(comptime bits: u16, x: comptime_int) @Int(.unsigned, bits) {
    comptime assert(bits >= 2);
    const T = TryInt(.unsigned, 2 * (@as(comptime_int, bits) + 1)) orelse @compileError("Too many bits");
    const X = math.IntFittingRange(0, x);

    // log2(x) = int + fractional part
    const int: comptime_int = comptime math.log2_int(X, x);
    const frac_bits = bits - int + @ctz(@as(X, x));
    var result: @Int(.unsigned, bits) = int;

    // fractional part = log2(x * 2^-int)
    // v = x * 2^-int * 2^bits
    //   = x * 2^(bits - int)
    var v: T = x << (bits - int);
    for (0..frac_bits) |_| {
        const v2 = v * v;
        result <<= 1;

        const one = 1 << (2 * bits);
        if (v2 >= 2 * one) {
            result |= 1;
            v = v2 >> (bits + 1);
        } else {
            v = v2 >> bits;
        }
    }

    return result;
}

/// Returns `round(2^b / x)`, where `b` is `@typeInfo(@TypeOf(x)).int.bits`. Ties are rounded to +inf.
pub fn inverse(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    const bits: comptime_int = @typeInfo(T).int.bits;
    comptime assert(@typeInfo(T).int.signedness == .unsigned);
    const p = bits + 1;
    const P = TryInt(.unsigned, p) orelse @compileError("Too many bits");

    // Trial division
    var v: P = 1 << bits;
    var result: T = 0;
    for (0..bits) |_| {
        result <<= 1;
        if (v >= x) {
            result |= 1;
            v -= x;
        }
        v <<= 1;
    }

    return result;
}

/// Returns the square root of `n`, rounded down.
pub fn sqrt(T: type, n: T) T {
    comptime assert(@typeInfo(T).int.signedness == .unsigned);

    const m = n - 1; // Round down
    // Halfing the number of bits is very close to square rooting
    const digit_count = @typeInfo(T).int.bits - @clz(n);
    var x: T = n >> @intCast(digit_count / 2);
    while (true) {
        // Newton-raphson method
        const next_x = (x + (m / x)) >> 1;
        if (x == next_x) return next_x;
        x = next_x;
    }
}

/// Returns `2^(n * 2^-b)) * 2^(b - 1)`, where `b` is the number of bits in `T`.
/// The answer may be slightly overestimated.
pub fn pow2(T: type, n: T) T {
    const bits: comptime_int = @typeInfo(T).int.bits;
    comptime assert(@typeInfo(T).int.signedness == .unsigned);
    comptime assert(bits >= 3);
    const guard: comptime_int = bits / 12;
    const p: comptime_int = 2 * (bits + guard);
    const P = TryInt(.unsigned, p) orelse @compileError("Too many bits");

    // [2^1, 2^0.5, 2^0.25, 2^0.125, ...]
    // The size of this table seems to be generally the same or smaller than the code
    // for generating it. The cost of evaluating this block is also negligible (3-12ms).
    const pow2s = comptime pow: {
        @setEvalBranchQuota(bits * p * 2);
        var pow: P = 1 << (p - 1); // Start with 2^1 = 2
        var pow2s: [bits]P = undefined;
        for (0..bits) |i| {
            const bits_lost = p / 2 - 1;
            pow = (sqrt(P, pow) + 1) << bits_lost;
            pow2s[i] = pow;
        }
        break :pow pow2s;
    };

    var result: P = 1 << (p - 1);
    for (0..bits) |i| {
        const mask = @as(T, 1) << @intCast(bits - i - 1);
        if (n & mask == mask) {
            result = mulHigh(P, result, pow2s[i]);
        }
    }
    return @truncate(math.shl(P, result, @as(i32, @clz(result)) - (p - bits)));
}

pub fn pow10(T: type, guard_bits: comptime_int, k: anytype) T {
    // There are unique beta and r such that 10^k = beta 2^r and
    // 2^63 <= beta < 2^64, namely r = floor(log_2 10^k) - 63 and
    // beta = 2^-r 10^k.
    // Let g = ceil(beta), so (g-1) 2^r < 10^k <= g 2^r, with the latter
    // value being a pretty good overestimate for 10^k.

    // r = floor(log2(10^k)) - 127
    // 10^k <= g 2^r
    // 10^k 2^-r <= g
    // 10^k 2^(-floor(log2(10^k)) + 127) <= g
    // 10^k 2^ceil(-log2(10^k) + 127) <= g
    // f = log2(10^k) - floor(log2(10^k))
    // log2(10^k) - f = floor(log2(10^k))
    // f = k*log2(10) - floor(k*log2(10))
    // 10^k 2^(f - log2(10^k) + 127) <= g
    // 2^f 2^127 <= g

    // @abs(k) must not overflow.
    // In practice this never happens because:
    // q >= math.minInt(_E), log10(2) < 0.5
    // k = log10(2) * q > math.minInt(_E) > math.minInt(E)
    const E = @TypeOf(k);
    assert(k > math.minInt(E));

    const bits: comptime_int = @typeInfo(T).int.bits;
    const p: comptime_int = @max(bits + 8, @typeInfo(E).int.bits + guard_bits);
    const P = @Int(.unsigned, p);

    @setEvalBranchQuota(5 * (p + 2));
    const @"log2(10)": P = comptime @truncate(log2(p + 2, 10));
    var f: P = (@"log2(10)" + @intFromBool(k >= 0)) *% @abs(k);
    if (k < 0) {
        f = 0 -% f;
    }
    const g = pow2(T, @truncate(f >> (p - bits)));
    return g + 1;
}
