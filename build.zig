const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("BFP", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    testStep(b, target, optimize);
    testCrossStep(b);
    benchStep(b, target);
    generateListsStep(b, optimize);
}

fn testStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    b.enable_qemu = true;
    b.enable_wasmtime = true;

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn testCrossStep(b: *std.Build) void {
    b.enable_qemu = true;
    b.enable_wasmtime = true;

    const test_step = b.step("test-cross", "Run tests on multiple architectures");
    for ([_]std.Target.Query{
        .{ .cpu_arch = .arm, .cpu_model = .baseline },
        .{ .cpu_arch = .aarch64, .cpu_model = .baseline },
        .{ .cpu_arch = .riscv32, .cpu_model = .baseline },
        .{ .cpu_arch = .riscv64, .cpu_model = .baseline },
        .{ .cpu_arch = .wasm32, .cpu_model = .baseline, .os_tag = .wasi },
        // TODO
        // Disable due to weird type mismatch error
        // .{ .cpu_arch = .wasm64, .cpu_model = .baseline, .os_tag = .wasi },
        .{ .cpu_arch = .x86, .cpu_model = .baseline },
        .{ .cpu_arch = .x86_64, .cpu_model = .baseline },

        // Apple
        .{ .cpu_arch = .aarch64, .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.apple_m1 } },
        .{ .cpu_arch = .aarch64, .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.apple_m4 } },
        .{ .cpu_arch = .aarch64, .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.apple_s4 } },
        .{ .cpu_arch = .aarch64, .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.apple_s5 } },
        // Snapdragon
        .{ .cpu_arch = .aarch64, .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.kryo } },
        .{ .cpu_arch = .aarch64, .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.oryon_1 } },

        // Intel
        .{ .cpu_arch = .x86, .cpu_model = .{ .explicit = &std.Target.x86.cpu.pentium_m } },
        .{ .cpu_arch = .x86_64, .cpu_model = .{ .explicit = &std.Target.x86.cpu.sandybridge } },
        .{ .cpu_arch = .x86_64, .cpu_model = .{ .explicit = &std.Target.x86.cpu.skylake_avx512 } },
        .{ .cpu_arch = .x86_64, .cpu_model = .{ .explicit = &std.Target.x86.cpu.arrowlake } },
        // AMD
        .{ .cpu_arch = .x86_64, .cpu_model = .{ .explicit = &std.Target.x86.cpu.znver1 } },
        .{ .cpu_arch = .x86_64, .cpu_model = .{ .explicit = &std.Target.x86.cpu.znver3 } },
        // Generic
        .{ .cpu_arch = .x86_64, .cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v2 } },
        .{ .cpu_arch = .x86_64, .cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v4 } },
    }) |_tq| {
        var tq = _tq;
        if (tq.os_tag == null) {
            tq.os_tag = .linux;
        }
        const target = b.resolveTargetQuery(tq);
        const is_compile_slow = target.result.cpu.arch == .x86 or target.result.os.tag == .wasi;

        const unit_tests = b.addTest(.{
            .name = b.fmt("unit {s}", .{target.result.cpu.model.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = target,
                .optimize = if (is_compile_slow) .ReleaseSafe else .Debug,
            }),
        });
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);

        const lists_tests = b.addTest(.{
            .name = b.fmt("consistency {s}", .{target.result.cpu.model.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("scripts/test_lists.zig"),
                .target = target,
                .optimize = if (is_compile_slow) .ReleaseSafe else .Debug,
                .imports = &.{.{ .name = "BFP", .module = b.modules.get("BFP").? }},
            }),
        });
        const run_lists_tests = b.addRunArtifact(lists_tests);
        test_step.dependOn(&run_lists_tests.step);
    }
}

fn benchStep(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "BFP", .module = b.modules.get("BFP").? }},
        }),
    });

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&b.addInstallArtifact(bench_exe, .{}).step);
    bench_step.dependOn(&b.addRunArtifact(bench_exe).step);

    if (b.option(bool, "emit-asm", "Emit generated assembly") orelse false) {
        const bench_asm = bench_exe.getEmittedAsm();
        const install_asm = b.addInstallFile(bench_asm, "bench.S");
        bench_step.dependOn(&install_asm.step);
    }
}

fn generateListsStep(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const gen_lists_exe = b.addExecutable(.{
        .name = "generate_lists",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/generate_lists.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = optimize,
            .imports = &.{.{ .name = "BFP", .module = b.modules.get("BFP").? }},
        }),
    });
    const run_gen_lists = b.addRunArtifact(gen_lists_exe);
    run_gen_lists.addDirectoryArg(b.path("scripts/test-lists"));

    const gen_lists_step = b.step("gen-lists", "Generate float lists for testing");
    gen_lists_step.dependOn(&run_gen_lists.step);
}
