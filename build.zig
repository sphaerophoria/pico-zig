const std = @import("std");

pub fn build(b: *std.Build) !void {
    const host = b.resolveTargetQuery(.{});

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

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "test",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
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
