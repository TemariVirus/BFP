const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const BigFloat = @import("BFP").BigFloat;

const TestOp = enum {
    inv,
    exp2,
    log2,
    add,
    sub,
    mul,
    div,
    pow,

    pub fn argCount(op: TestOp) usize {
        return switch (op) {
            .inv, .exp2, .log2 => 1,
            .add, .sub, .mul, .div, .pow => 2,
        };
    }

    pub fn apply(comptime op: TestOp, args: anytype) std.meta.Child(@TypeOf(args)) {
        return switch (op) {
            .inv => args[0].inv(),
            .exp2 => args[0].exp2(),
            .log2 => args[0].log2(),
            .add => args[0].add(args[1]),
            .sub => args[0].sub(args[1]),
            .mul => args[0].mul(args[1]),
            .div => args[0].div(args[1]),
            .pow => args[0].pow(args[1]),
        };
    }
};

// TODO: use fuzzer to generate this?
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        return error.MissingPath;
    }
    const working_path = args[1];

    try Io.Dir.deleteTree(.cwd(), io, working_path);
    const dir = try Io.Dir.createDirPathOpen(.cwd(), io, working_path, .{});
    defer dir.close(io);

    var wait_grp: Io.Group = .init;
    defer wait_grp.cancel(io);
    inline for (.{
        BigFloat(.{ .Significand = f32, .Exponent = i32 }),
        BigFloat(.{ .Significand = f64, .Exponent = i64 }),
        BigFloat(.{ .Significand = f128, .Exponent = i64 }),
    }) |BF| {
        inline for (@typeInfo(TestOp).@"enum".field_values) |op| {
            wait_grp.async(
                io,
                generateTask(BF, @enumFromInt(op)),
                .{ io, init.gpa, dir },
            );
        }
    }
    try wait_grp.await(io);
}

fn generateTask(comptime BF: type, comptime op: TestOp) fn (Io, Allocator, Io.Dir) void {
    return (struct {
        fn closure(io: Io, allocator: Allocator, dir: Io.Dir) void {
            generate(BF, op, io, allocator, dir) catch |err| {
                if (err == Io.Cancelable.Canceled) return;

                std.debug.panic("generate() failed with error: {t}\n", .{err});
            };
        }
    }).closure;
}

fn generate(
    comptime BF: type,
    comptime op: TestOp,
    io: Io,
    allocator: Allocator,
    dir: Io.Dir,
) !void {
    var name_buf: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "{s}-{}.zig", .{ @tagName(op), @FieldType(BF, "significand") }) catch unreachable;
    const file = try dir.createFile(io, name, .{ .truncate = true });
    defer file.close(io);

    const file_buf = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(file_buf);
    var file_writer = file.writer(io, file_buf);
    const writer = &file_writer.interface;

    var chacha: std.Random.ChaCha = .init("おかころは不滅！😾🐶".*);
    const rng = chacha.random();

    const COUNT = 5000;
    try bigFloatDecl(writer, BF);
    try writer.print(
        \\
        \\pub const values: []const [{d}]BF = blk: {{
        \\    @setEvalBranchQuota({d});
        \\    break :blk &.{{
        \\
    , .{ op.argCount() + 1, 100 * COUNT });
    for (0..COUNT) |_| {
        var args: [op.argCount()]BF = undefined;
        try writer.print("    [_]BF{{ ", .{});
        for (0..op.argCount()) |i| {
            var bf = nextValue(BF, rng);
            switch (op) {
                .exp2 => {
                    // Use smaller values for more variation in result
                    bf.value = @floatCast(rng.floatNorm(f64) * 1024 * 1024);
                },
                .log2 => {
                    bf.value = @abs(bf.value);
                },
                .pow => {
                    // Use smaller values for more variation in result
                    if (i == 0) {
                        bf.value = @floatCast(rng.floatNorm(f64) * 1024);
                        bf.value = @abs(bf.value);
                    } else {
                        bf.value = @floatCast(rng.floatNorm(f64) * 1024);
                    }
                },
                else => {},
            }

            args[i] = .init(bf.value);
            try writer.print("{f}, ", .{bf});
        }
        try printBigFloat(writer, op.apply(args));
        try writer.print(" }}, \n", .{});
    }
    try writer.print(
        \\    }};
        \\}};
        \\
    , .{});

    try file_writer.end();
}

fn bigFloatDecl(w: *Io.Writer, comptime BF: type) Io.Writer.Error!void {
    try w.print(
        \\pub const BF = @import("BFP").BigFloat(.{{
        \\    .Significand = {},
        \\    .Exponent    = {},
        \\}});
        \\
    , .{ @FieldType(BF, "significand"), @FieldType(BF, "exponent") });
}

/// Each bit pattern is equally likely.
fn randomFloat(comptime F: type, rng: std.Random) F {
    var float: F = undefined;
    rng.bytes(@ptrCast(&float));
    while (std.math.isNan(float)) {
        rng.bytes(@ptrCast(&float));
    }
    return float;
}

fn BigFloatValue(comptime BF: type) type {
    const S = @FieldType(BF, "significand");
    return struct {
        value: S,

        pub fn format(self: @This(), w: *Io.Writer) Io.Writer.Error!void {
            if (std.math.isPositiveInf(self.value)) {
                try w.print(".init(std.math.inf({}))", .{S});
            } else if (std.math.isNegativeInf(self.value)) {
                try w.print(".init(-std.math.inf({}))", .{S});
            } else {
                try w.print(".init(@as({}, {x}))", .{ S, self.value });
            }
        }
    };
}

fn nextValue(comptime BF: type, rng: std.Random) BigFloatValue(BF) {
    return .{ .value = randomFloat(@FieldType(BF, "significand"), rng) };
}

fn printBigFloat(w: *Io.Writer, bf: anytype) Io.Writer.Error!void {
    if (bf.isNan()) {
        try w.writeAll(".nan");
    } else if (std.math.isPositiveInf(bf.significand)) {
        try w.writeAll(".inf");
    } else if (std.math.isNegativeInf(bf.significand)) {
        try w.writeAll(".inf.neg()");
    } else {
        try w.print("{any}", .{bf});
    }
}
