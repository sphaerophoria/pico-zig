const std = @import("std");

pub fn build(b: *std.Build) !void {
    const host = b.resolveTargetQuery(.{});

    const gen_registers = b.addExecutable(.{
        .name = "gen_registers",
        .root_source_file = b.path("src/generate_register_types.zig"),
        .target = host,
        .optimize = .Debug,
    });

    const run_gen_registers = b.addRunArtifact(gen_registers);
    run_gen_registers.addFileArg(b.path("registers.json"));

    const registers_zig = run_gen_registers.addOutputFileArg("registers.zig");
    const patch_elf = b.addExecutable(.{
        .name = "patch_elf",
        .root_source_file = b.path("build/patch_elf.zig"),
        .target = host,
        .optimize = .Debug,
    });

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    const registers_helpers = b.addModule("helpers", .{
        .root_source_file = b.path("src/generate_register_types/helpers.zig"),

    });

    const registers_mod = b.addModule("registers", .{
        .root_source_file = registers_zig,
    });
    registers_mod.addImport("helpers", registers_helpers);

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "test",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addAssemblyFile(b.path("src/functions.S"));
    exe.root_module.addImport("registers", registers_mod);
    exe.bundle_ubsan_rt = false;
    exe.root_module.link_libc = false;
    exe.addIncludePath(b.path("."));
    exe.link_gc_sections = true;
    exe.addAssemblyFile(b.path("src/boot2.S"));
    exe.setLinkerScript(b.path("src/link.ld"));

    const run_patch_elf = b.addRunArtifact(patch_elf);
    run_patch_elf.addFileArg(exe.getEmittedBin());
    const final_artifact = run_patch_elf.addOutputFileArg("test");
    const install_final_artifact = b.addInstallBinFile(final_artifact, "test");
    b.getInstallStep().dependOn(&install_final_artifact.step);
}
