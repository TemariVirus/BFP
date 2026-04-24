const std = @import("std");
const Io = std.Io;
const math = std.math;
const linux = std.os.linux;
const PERF = linux.PERF;

const BigFloat = @import("BFP").BigFloat;

// Note: The instruction counts for extremely lightweight benchmarks are inflated
// from having to load the data. (E.g., f64 addition is only 1 instruction, but was recorded as 3)
//
// Zig: 0.16.0
// CPU: Intel(R) Core(TM) i7-8700 CPU @ 4.60GHz

// ==========
//  Addition
// ==========
// f32                   1.609GFLOP/s |  1.000x
// f64                   1.131GFLOP/s |  1.423x
// f128                 84.074MFLOP/s | 19.140x
// BigFloat(f32, i32)  125.485MFLOP/s | 12.824x
// BigFloat(f32, i96)   94.943MFLOP/s | 16.949x
// BigFloat(f64, i64)  133.624MFLOP/s | 12.043x
// BigFloat(f64, i128) 111.836MFLOP/s | 14.389x

// f64
//   Thread time:  0.91ns
//   Cycles:       4.1   | 0.88ns
//   Instructions: 3.0
//   Branches:     0.01  | 0.00% miss
// BigFloat(f64, i64)
//   Thread time:  7.82ns
//   Cycles:       34.4  | 7.48ns
//   Instructions: 50.9
//   Branches:     9.69  | 5.76% miss

// ================
//  Multiplication
// ================
// f32                   0.429GFLOP/s |  1.897x
// f64                   0.813GFLOP/s |  1.000x
// f128                 56.449MFLOP/s | 14.403x
// BigFloat(f32, i32)    0.319GFLOP/s |  2.549x
// BigFloat(f32, i96)    0.267GFLOP/s |  3.047x
// BigFloat(f64, i64)    0.272GFLOP/s |  2.992x
// BigFloat(f64, i128)   0.166GFLOP/s |  4.910x

// f64
//   Thread time:  1.29ns
//   Cycles:       5.7   | 1.23ns
//   Instructions: 3.0
//   Branches:     0.01  | 0.00% miss
// BigFloat(f64, i64)
//   Thread time:  3.81ns
//   Cycles:       16.9  | 3.68ns
//   Instructions: 41.0
//   Branches:     5.01  | 0.00% miss

// ==========
//  Division
// ==========
// f32                   0.354GFLOP/s |  1.782x
// f64                   0.630GFLOP/s |  1.000x
// f128                 23.503MFLOP/s | 26.815x
// BigFloat(f32, i32)    0.340GFLOP/s |  1.851x
// BigFloat(f32, i96)    0.227GFLOP/s |  2.776x
// BigFloat(f64, i64)    0.259GFLOP/s |  2.435x
// BigFloat(f64, i128)   0.155GFLOP/s |  4.076x

// f64
//   Thread time:  1.66ns
//   Cycles:       7.3   | 1.59ns
//   Instructions: 3.0
//   Branches:     0.01  | 0.00% miss
// BigFloat(f64, i64)
//   Thread time:  4.01ns
//   Cycles:       17.8  | 3.86ns
//   Instructions: 41.0
//   Branches:     5.01  | 0.00% miss

// =========
//  Inverse
// =========
// f32                   0.899GFLOP/s |  1.103x
// f64                   0.991GFLOP/s |  1.000x
// f128                 27.414MFLOP/s | 36.142x
// BigFloat(f32, i32)    0.608GFLOP/s |  1.630x
// BigFloat(f32, i96)    0.316GFLOP/s |  3.137x
// BigFloat(f64, i64)    0.514GFLOP/s |  1.926x
// BigFloat(f64, i128)   0.422GFLOP/s |  2.346x

// f64
//   Thread time:  1.05ns
//   Cycles:       4.6   | 1.01ns
//   Instructions: 2.0
//   Branches:     0.00  | 0.00% miss
// BigFloat(f64, i64)
//   Thread time:  2.01ns
//   Cycles:       8.9   | 1.94ns
//   Instructions: 19.0
//   Branches:     4.00  | 0.00% miss

// =======
//  Power
// =======
// f32                  38.451MFLOP/s |  1.127x
// f64                  43.345MFLOP/s |  1.000x
// f128                 46.816MFLOP/s |  0.926x
// BigFloat(f32, i32)   24.942MFLOP/s |  1.738x
// BigFloat(f32, i96)   22.766MFLOP/s |  1.904x
// BigFloat(f64, i64)   26.431MFLOP/s |  1.640x
// BigFloat(f64, i128)  24.318MFLOP/s |  1.782x

// f64
//   Thread time:  24.1ns
//   Cycles:       106.1 | 23.1ns
//   Instructions: 140.2
//   Branches:     27.04 | 4.46% miss
// BigFloat(f64, i64)
//   Thread time:  39.2ns
//   Cycles:       174.0 | 37.8ns
//   Instructions: 206.4
//   Branches:     30.21 | 4.64% miss

// ===============
//  Integer Power
// ===============
// f32                  21.698MFLOP/s |  1.000x
// f64                  20.755MFLOP/s |  1.045x
// f128                 49.920MFLOP/s |  0.435x
// BigFloat(f32, i32)   14.539MFLOP/s |  1.492x
// BigFloat(f32, i96)   13.399MFLOP/s |  1.619x
// BigFloat(f64, i64)   14.652MFLOP/s |  1.481x
// BigFloat(f64, i128)  13.411MFLOP/s |  1.618x

// f64
//   Thread time:  49.9ns
//   Cycles:       221.6 | 48.2ns
//   Instructions: 233.8
//   Branches:     47.18 | 11.66% miss
// BigFloat(f64, i64)
//   Thread time:  71.8ns
//   Cycles:       313.9 | 68.2ns
//   Instructions: 549.3
//   Branches:     91.89 | 0.75% miss

// ======
//  Exp2
// ======
// f32                 122.541MFLOP/s |  1.050x
// f64                 128.685MFLOP/s |  1.000x
// f128                 83.288MFLOP/s |  1.545x
// BigFloat(f32, i32)   76.905MFLOP/s |  1.673x
// BigFloat(f32, i96)   68.311MFLOP/s |  1.884x
// BigFloat(f64, i64)   88.783MFLOP/s |  1.449x
// BigFloat(f64, i128)  75.350MFLOP/s |  1.708x

// f64
//   Thread time:  8.03ns
//   Cycles:       35.7  | 7.77ns
//   Instructions: 25.9
//   Branches:     6.21  | 13.12% miss
// BigFloat(f64, i64)
//   Thread time:  11.8ns
//   Cycles:       51.8  | 11.3ns
//   Instructions: 60.4
//   Branches:     13.59 | 8.62% miss

// ======
//  Log2
// ======
// f32                   0.161GFLOP/s |  1.000x
// f64                   0.145GFLOP/s |  1.110x
// f128                 76.906MFLOP/s |  2.092x
// BigFloat(f32, i32)   74.886MFLOP/s |  2.149x
// BigFloat(f32, i96)   61.844MFLOP/s |  2.602x
// BigFloat(f64, i64)   82.915MFLOP/s |  1.941x
// BigFloat(f64, i128)  66.644MFLOP/s |  2.414x

// f64
//   Thread time:  7.36ns
//   Cycles:       31.7  | 6.90ns
//   Instructions: 45.5
//   Branches:     5.00  | 10.00% miss
// BigFloat(f64, i64)
//   Thread time:  12.8ns
//   Cycles:       55.5  | 12.1ns
//   Instructions: 82.5
//   Branches:     11.00 | 4.62% miss

// ==================
//  FormatScientific
// ==================
// f32                  19.618MFLOP/s |  1.000x
// f64                  19.301MFLOP/s |  1.016x
// f128                  2.008MFLOP/s |  9.769x
// BigFloat(f32, i32)    3.841MFLOP/s |  5.107x
// BigFloat(f32, i96)    3.366MFLOP/s |  5.827x
// BigFloat(f64, i64)    0.735MFLOP/s | 26.693x
// BigFloat(f64, i128)   0.682MFLOP/s | 28.747x

// f64
//   Thread time:  53.9ns
//   Cycles:       238.3 | 51.8ns
//   Instructions: 640.8
//   Branches:     67.54 | 3.21% miss
// BigFloat(f64, i64)
//   Thread time:  1.427us
//   Cycles:       6259.1 | 1.36us
//   Instructions: 14148.4
//   Branches:     424.28 | 15.08% miss

// =================
//  ParseScientific
// =================
// f32                  27.523MFLOP/s |  1.000x
// f64                  24.934MFLOP/s |  1.104x
// f128                  0.920kFLOP/s | 29916.573x
// BigFloat(f32, i32)    3.383MFLOP/s |  8.135x
// BigFloat(f32, i96)    2.904MFLOP/s |  9.476x
// BigFloat(f64, i64)    0.717MFLOP/s | 38.375x
// BigFloat(f64, i128)   0.667MFLOP/s | 41.255x

// f64
//   Thread time:  42.4ns
//   Cycles:       184.5 | 40.1ns
//   Instructions: 409.9
//   Branches:     62.64 | 3.19% miss
// BigFloat(f64, i64)
//   Thread time:  1.445us
//   Cycles:       6413.7 | 1.394us
//   Instructions: 14367.2
//   Branches:     513.18 | 12.84% miss

pub fn main(init: std.process.Init) !void {
    var stdout_writer = Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_writer.interface;

    const cpu_info = CpuInfo.init(init.io) catch |err| {
        std.debug.panic("unable to get CPU info: {t}\n", .{err});
    };
    stdout.print("Zig: {s}\n", .{@import("builtin").zig_version_string}) catch {};
    cpu_info.prettyPrint(stdout) catch {};

    bench("Addition", runAdd, 2, init.io, stdout, cpu_info) catch {};
    bench("Multiplication", runMul, 2, init.io, stdout, cpu_info) catch {};
    bench("Division", runDiv, 2, init.io, stdout, cpu_info) catch {};
    bench("Inverse", runInv, 1, init.io, stdout, cpu_info) catch {};
    bench("Power", runPow, 2, init.io, stdout, cpu_info) catch {};
    bench("Integer Power", runPowi, 1, init.io, stdout, cpu_info) catch {};
    bench("Exp2", runExp2, 1, init.io, stdout, cpu_info) catch {};
    bench("Log2", runLog2, 1, init.io, stdout, cpu_info) catch {};
    bench("FormatScientific", runFmt, 1, init.io, stdout, cpu_info) catch {};
    bench("ParseScientific", runParse, 1, init.io, stdout, cpu_info) catch {};
}

fn AllocFn(T: type) type {
    return fn (type, usize, std.mem.Allocator) []T;
}
fn FreeFn(T: type) type {
    return fn (type, std.mem.Allocator, []T) void;
}
fn RunFn(T: type) type {
    return fn (type, []const T) void;
}

const CpuInfo = struct {
    name: []const u8,
    max_hz: u64,

    pub fn init(io: Io) !@This() {
        switch (@import("builtin").os.tag) {
            .linux => {},
            else => @compileError("Unsupported OS"),
        }

        const f = try Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{});
        defer f.close(io);
        var line_buf: [4096]u8 = undefined;
        var reader = f.reader(io, &line_buf);

        const full_name = while (try reader.interface.takeDelimiter(':')) |key_full| {
            const key = std.mem.trim(u8, key_full, " \t\n");
            if (' ' != try reader.interface.takeByte()) { // Skip leading space
                return error.InvalidFormat;
            }

            if (std.mem.eql(u8, key, "model name")) {
                const value = try reader.interface.takeDelimiter('\n');
                break value orelse return error.InvalidFormat;
            } else {
                _ = try reader.interface.discardDelimiterInclusive('\n');
            }
        } else return error.InvalidFormat;

        const f2 = try Io.Dir.openFileAbsolute(
            io,
            "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq",
            .{},
        );
        defer f2.close(io);
        var max_khz_buf: [32]u8 = undefined;
        const max_khz_str = max_khz_buf[0..try f2.readPositionalAll(io, &max_khz_buf, 0)];
        const max_khz = std.fmt.parseInt(
            u64,
            std.mem.trimEnd(u8, max_khz_str, "\n"),
            10,
        ) catch return error.InvalidFormat;

        // Get rid of '@ X.XXGHz' suffix from CPU name
        const at_pos = std.mem.lastIndexOfScalar(u8, full_name, '@') orelse full_name.len;
        const name = std.mem.trim(u8, full_name[0..at_pos], " ");
        return CpuInfo{ .name = name, .max_hz = max_khz * 1000 };
    }

    pub fn prettyPrint(self: @This(), w: *Io.Writer) !void {
        var max_hz_buf: [64]u8 = undefined;
        const hz_str = std.fmt.bufPrint(&max_hz_buf, "{B:.2}", .{self.max_hz}) catch unreachable;
        try w.print("CPU: {s} @ {s}Hz\n", .{ self.name, std.mem.trimEnd(u8, hz_str, "B") });
    }
};

const Bench = struct {
    perf_fds: [perf_measurements.len]linux.fd_t,
    start_ts: Io.Timestamp,

    const clock: Io.Clock = .cpu_thread;

    const perf_measurements = [_]PERF.COUNT.HW{
        .CPU_CYCLES,
        .INSTRUCTIONS,
        .BRANCH_INSTRUCTIONS,
        .BRANCH_MISSES,
    };

    pub const Result = struct {
        thread_nanos: u64,
        cycles: usize,
        instructions: usize,
        branches: usize,
        branch_misses: usize,

        fn perOp(total: usize, op_count: u64) f64 {
            return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(op_count));
        }

        pub fn flops(result: Result, op_count: u64, cpu_hz: u64) u64 {
            return op_count * cpu_hz / @as(u64, @intCast(result.cycles));
        }

        pub fn prettyPrint(result: Result, w: *Io.Writer, op_count: u64, cpu_hz: u64) !void {
            try w.print("  Thread time:  {f}\n", .{
                smallDuration(perOp(result.thread_nanos, op_count)),
            });

            const cycles_as_nanos = perOp(result.cycles, op_count) * std.time.ns_per_s / @as(f64, @floatFromInt(cpu_hz));
            try w.print("  Cycles:       {d:<5.1} | {f}\n", .{
                perOp(result.cycles, op_count),
                smallDuration(cycles_as_nanos),
            });

            try w.print("  Instructions: {d:.1}\n", .{perOp(result.instructions, op_count)});

            const branch_miss_rate = if (result.branches == 0)
                0.0
            else
                @as(f64, @floatFromInt(result.branch_misses)) / @as(f64, @floatFromInt(result.branches));
            try w.print("  Branches:     {d:<5.2} | {d:.2}% miss\n", .{
                perOp(result.branches, op_count),
                branch_miss_rate * 100.0,
            });
        }
    };

    pub fn init() @This() {
        var self = Bench{
            .perf_fds = @splat(-1),
            .start_ts = undefined,
        };
        for (perf_measurements, &self.perf_fds) |measurement, *perf_fd| {
            var attr: linux.perf_event_attr = .{
                .type = PERF.TYPE.HARDWARE,
                .config = @intFromEnum(measurement),
                .flags = .{
                    .disabled = true,
                    .exclude_kernel = true,
                    .exclude_hv = true,
                },
            };
            perf_fd.* = std.posix.perf_event_open(&attr, 0, -1, self.perf_fds[0], PERF.FLAG.FD_CLOEXEC) catch |err| {
                std.debug.panic("unable to open perf event: {t}\n", .{err});
            };
        }
        return self;
    }

    pub fn start(self: *@This(), io: Io) void {
        self.start_ts = .now(io, clock);
        _ = linux.ioctl(self.perf_fds[0], PERF.EVENT_IOC.RESET, PERF.IOC_FLAG_GROUP);
        _ = linux.ioctl(self.perf_fds[0], PERF.EVENT_IOC.ENABLE, PERF.IOC_FLAG_GROUP);
    }

    pub fn stop(self: *@This(), io: Io) Result {
        _ = linux.ioctl(self.perf_fds[0], PERF.EVENT_IOC.DISABLE, PERF.IOC_FLAG_GROUP);
        const res = Result{
            .thread_nanos = @intCast(self.start_ts.untilNow(io, clock).toNanoseconds()),
            .cycles = readPerfFd(self.perf_fds[0]),
            .instructions = readPerfFd(self.perf_fds[1]),
            .branches = readPerfFd(self.perf_fds[2]),
            .branch_misses = readPerfFd(self.perf_fds[3]),
        };

        for (&self.perf_fds) |*perf_fd| {
            // Seems to work lol
            Io.File.close(.{ .handle = perf_fd.*, .flags = .{ .nonblocking = false } }, io);
            perf_fd.* = -1;
        }
        return res;
    }

    fn readPerfFd(fd: linux.fd_t) usize {
        var result: usize = 0;
        const n = std.posix.read(fd, std.mem.asBytes(&result)) catch |err| {
            std.debug.panic("unable to read perf fd: {t}\n", .{err});
        };
        std.debug.assert(n == @sizeOf(usize));
        return result;
    }
};

fn typeName(T: type) []const u8 {
    if (comptime isFloat(T)) {
        return std.fmt.comptimePrint("{}", .{T});
    } else {
        return std.fmt.comptimePrint(
            "BigFloat({}, {})",
            .{ @FieldType(T, "significand"), @FieldType(T, "exponent") },
        );
    }
}

fn getAllocFree(T: type) struct { AllocFn(T), FreeFn(T) } {
    return switch (T) {
        []const u8 => .{ allocStrings, freeStrings },
        else => .{ allocFloats, freeFloats },
    };
}

fn formatSmallDuration(nanos: f64, w: *Io.Writer) !void {
    if (nanos >= 100) {
        try w.print("{f}", .{Io.Duration.fromNanoseconds(@intFromFloat(nanos))});
    } else if (nanos >= 10) {
        try w.print("{d:.1}ns", .{nanos});
    } else {
        try w.print("{d:.2}ns", .{nanos});
    }
}

fn smallDuration(nanos: f64) std.fmt.Alt(f64, formatSmallDuration) {
    return .{ .data = nanos };
}

fn iterCount(
    T: type,
    InputT: type,
    comptime run: RunFn(InputT),
    comptime args_per_run: usize,
    io: Io,
    target_ns: u64,
) u64 {
    var iters: u64 = 1;

    const allocator = std.heap.page_allocator;
    const alloc, const free = getAllocFree(InputT);
    const args = alloc(T, args_per_run, allocator);
    defer free(T, allocator, args);

    // Find rough number of iterations needed to take at least 10ms
    const ns_taken: u64 = while (true) : (iters *= 2) {
        const start: Io.Timestamp = .now(io, .real);
        for (0..iters) |_| {
            run(T, args);
        }
        const time_taken = start.untilNow(io, .real);
        const time_limit = 10 * std.time.ns_per_ms;
        // Prevent overflow
        if (time_taken.toNanoseconds() >= time_limit or iters *% 2 < iters) {
            break @intCast(time_taken.toNanoseconds());
        }
    };

    // Extrapolate to target_ns
    return (iters * target_ns) / ns_taken;
}

fn bench(
    comptime name: []const u8,
    comptime run: anytype,
    comptime args_per_run: usize,
    io: Io,
    w: *Io.Writer,
    cpu_info: CpuInfo,
) !void {
    try w.print(
        \\
        \\{1s}
        \\ {0s}
        \\{1s}
        \\
    , .{ name, @as([name.len + 2]u8, @splat('=')) });

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const types = [_]type{
        f32,
        f64,
        f128,
        BigFloat(.{ .Significand = f32, .Exponent = i32, .bake_render = true }),
        BigFloat(.{ .Significand = f32, .Exponent = i96, .bake_render = true }),
        BigFloat(.{ .Significand = f64, .Exponent = i64, .bake_render = true }),
        BigFloat(.{ .Significand = f64, .Exponent = i128, .bake_render = true }),
    };
    var iter_counts: [types.len]u64 = undefined;
    var results: [types.len]Bench.Result = undefined;

    const InputSlice = @typeInfo(@TypeOf(run)).@"fn".params[1].type;
    inline for (types, 0..) |T, i| {
        const InputT = if (InputSlice) |IS| @typeInfo(IS).pointer.child else T;
        const alloc, const free = getAllocFree(InputT);

        iter_counts[i] = iterCount(T, InputT, run, args_per_run, io, 100 * std.time.ns_per_ms);
        const data = alloc(T, iter_counts[i] * args_per_run, allocator);
        defer free(T, allocator, data);
        var b: Bench = .init();

        run(T, data); // Warmup
        b.start(io);
        run(T, data); // Actual run
        results[i] = b.stop(io);
    }

    const base_flops = @max(
        results[0].flops(iter_counts[0], cpu_info.max_hz),
        results[1].flops(iter_counts[1], cpu_info.max_hz),
    );
    inline for (types, 0..) |T, i| {
        const flops = results[i].flops(iter_counts[i], cpu_info.max_hz);
        var flops_buf: [9]u8 = undefined;
        const flops_str = std.fmt.bufPrint(&flops_buf, "{B:.3}", .{flops}) catch unreachable;

        try w.print("{s:<19} {s:>8}FLOP/s | {d:>6.3}x\n", .{
            typeName(T),
            flops_str[0 .. flops_str.len - 1],
            @as(f64, @floatFromInt(base_flops)) / @as(f64, @floatFromInt(flops)),
        });
    }

    try w.print("\n{s}\n", .{typeName(types[1])});
    try results[1].prettyPrint(w, iter_counts[1], cpu_info.max_hz);
    try w.print("{s}\n", .{typeName(types[5])});
    try results[5].prettyPrint(w, iter_counts[5], cpu_info.max_hz);
}

fn isFloat(T: type) bool {
    return @typeInfo(T) == .float;
}

/// Returns a random float evenly distributed in the range [1, 2) or (-2, -1].
fn randomSignificand(T: type, rng: std.Random) T {
    const C = @Int(.unsigned, @typeInfo(T).float.bits);

    // Mantissa
    var repr: C = rng.int(@Int(.unsigned, math.floatMantissaBits(T)));
    // Explicit bit is always 1
    if (math.floatMantissaBits(T) != math.floatFractionalBits(T)) {
        repr |= @as(C, 1) << math.floatFractionalBits(T);
    }
    // Exponent is always 0
    repr |= math.floatExponentMax(T) << math.floatMantissaBits(T);
    // Sign
    repr |= @as(C, rng.int(u1)) << (@typeInfo(T).float.bits - 1);

    return @bitCast(repr);
}

fn randomFloat(T: type, rng: std.Random) T {
    if (comptime isFloat(T)) {
        var f: T = undefined;
        while (true) {
            rng.bytes(std.mem.asBytes(&f));
            if (math.isFinite(f)) return f;
        }
    } else {
        return .init(randomFloat(@FieldType(T, "significand"), rng));
    }
}

fn allocFloats(T: type, n: usize, allocator: std.mem.Allocator) []T {
    const floats = allocator.alloc(T, n) catch @panic("OOM");
    var rng: std.Random.Xoshiro256 = .init(123456789_850_907);
    for (floats) |*f| {
        f.* = randomFloat(T, rng.random());
    }
    return floats;
}

fn allocStrings(T: type, n: usize, allocator: std.mem.Allocator) [][]const u8 {
    const chars_per_float = @bitSizeOf(T);
    const strings = allocator.alloc([]const u8, n) catch @panic("OOM");
    var buf = std.ArrayList(u8).initCapacity(allocator, n * chars_per_float) catch @panic("OOM");

    var rng: std.Random.Xoshiro256 = .init(123456789_850_907);
    for (strings) |*s| {
        const f = randomFloat(T, rng.random());

        const start = buf.unusedCapacitySlice().ptr;
        buf.print(allocator, "{e}", .{f}) catch @panic("failed to print float");
        const len = buf.unusedCapacitySlice().ptr - start;
        s.* = start[0..len];
    }

    return strings;
}

fn freeFloats(T: type, allocator: std.mem.Allocator, arr: []T) void {
    allocator.free(arr);
}

fn freeStrings(T: type, allocator: std.mem.Allocator, arr: [][]const u8) void {
    var buf = arr[0];
    buf.len = arr.len * @bitSizeOf(T);
    allocator.free(buf);
    allocator.free(arr);
}

inline fn batchRun(
    comptime runOne: anytype,
    comptime args_per_run: usize,
    comptime batch_size: usize,
    data: anytype,
) void {
    comptime std.debug.assert(batch_size % args_per_run == 0);
    var args = data;

    while (args.len >= batch_size) {
        inline for (0..batch_size / args_per_run) |i| {
            const f = runOne(args[i * args_per_run ..][0..args_per_run]);
            std.mem.doNotOptimizeAway(f);
        }
        args = args[batch_size..];
    }

    // Remainder
    for (0..args.len / args_per_run) |i| {
        const f = runOne(args[i * args_per_run ..][0..args_per_run]);
        std.mem.doNotOptimizeAway(f);
    }
}

fn runAdd(T: type, data: []const T) void {
    const runOne = (struct {
        inline fn runOne(args: *const [2]T) T {
            return if (comptime isFloat(T))
                args[0] + args[1]
            else
                args[0].add(args[1]);
        }
    }).runOne;
    batchRun(runOne, 2, 256, data);
}

fn runMul(T: type, data: []const T) void {
    const runOne = (struct {
        inline fn runOne(args: *const [2]T) T {
            return if (comptime isFloat(T))
                args[0] * args[1]
            else
                args[0].mul(args[1]);
        }
    }).runOne;
    batchRun(runOne, 2, 256, data);
}

fn runDiv(T: type, data: []const T) void {
    const runOne = (struct {
        inline fn runOne(args: *const [2]T) T {
            return if (comptime isFloat(T))
                args[0] / args[1]
            else
                args[0].div(args[1]);
        }
    }).runOne;
    batchRun(runOne, 2, 256, data);
}

fn runInv(T: type, data: []const T) void {
    const runOne = (struct {
        inline fn runOne(args: *const [1]T) T {
            return if (comptime isFloat(T))
                1.0 / args[0]
            else
                args[0].inv();
        }
    }).runOne;
    batchRun(runOne, 1, 256, data);
}

fn runPow(T: type, data: []const T) void {
    const runOne = (struct {
        inline fn runOne(args: *const [2]T) T {
            if (comptime isFloat(T)) {
                // TODO: change this out when std.math.pow is implemented for f16/f80/f128
                const F = switch (T) {
                    f16, f32 => f32,
                    f64, f80, f128 => f64,
                    else => unreachable,
                };
                return math.pow(F, @floatCast(args[0]), @floatCast(args[1]));
            } else {
                return args[0].pow(args[1]);
            }
        }
    }).runOne;
    batchRun(runOne, 2, 2, data);
}

fn runPowi(T: type, data: []const T) void {
    const powi = (struct {
        inline fn powi(base: T, power: i32) T {
            if (comptime isFloat(T)) {
                // TODO: change this out when std.math.pow is implemented for f16/f80/f128
                const F = switch (T) {
                    f16, f32 => f32,
                    f64, f80, f128 => f64,
                    else => unreachable,
                };
                return math.pow(F, @floatCast(base), @floatFromInt(power));
            } else {
                return base.powi(power);
            }
        }
    }).powi;

    const powers = comptime blk: {
        var ps: [256]i32 = undefined;
        @setEvalBranchQuota(100 * ps.len);
        var rng: std.Random.Xoshiro256 = .init(123);
        for (&ps) |*p| {
            const power = rng.random().floatNorm(f64) * 1_000 + 0.5;
            p.* = @intFromFloat(power);
        }
        break :blk ps;
    };

    var args = data;
    while (args.len >= powers.len) {
        inline for (0..powers.len) |i| {
            const f = powi(args[i], powers[i]);
            std.mem.doNotOptimizeAway(f);
        }
        args = args[powers.len..];
    }

    // Remainder
    for (0..args.len) |i| {
        const f = powi(args[i], powers[i]);
        std.mem.doNotOptimizeAway(f);
    }
}

fn runExp2(T: type, data: []const T) void {
    const runOne = (struct {
        inline fn runOne(args: *const [1]T) T {
            return if (comptime isFloat(T))
                @exp2(args[0])
            else
                args[0].exp2();
        }
    }).runOne;
    batchRun(runOne, 1, 256, data);
}

fn runLog2(T: type, data: []const T) void {
    const runOne = (struct {
        inline fn runOne(args: *const [1]T) T {
            return if (comptime isFloat(T))
                @log2(args[0])
            else
                args[0].log2();
        }
    }).runOne;
    batchRun(runOne, 1, 256, data);
}

fn runFmt(T: type, data: []const T) void {
    const runOne = (struct {
        inline fn runOne(args: *const [1]T) u64 {
            var w: Io.Writer.Discarding = .init(&.{});
            w.writer.print("{e}", .{args[0]}) catch unreachable;
            return w.count;
        }
    }).runOne;
    batchRun(runOne, 1, 1, data);
}

fn runParse(T: type, data: []const []const u8) void {
    const runOne = (struct {
        inline fn runOne(args: *const [1][]const u8) T {
            const f = if (comptime isFloat(T))
                std.fmt.parseFloat(T, args[0])
            else
                T.parse(args[0]);
            return f catch {
                // Using the unreachable keyword would tell the compiler that parsing never fails,
                // but we don't want any optimizations based on that assumption.
                @branchHint(.cold);
                @panic("unreachable");
            };
        }
    }).runOne;
    batchRun(runOne, 1, 1, data);
}
