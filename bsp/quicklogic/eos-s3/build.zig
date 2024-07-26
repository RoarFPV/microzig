const std = @import("std");
const MicroZig = @import("microzig/build");

fn root() []const u8 {
    return comptime (std.fs.path.dirname(@src().file) orelse ".");
}
const build_root = root();

const KiB = 1024;

pub fn build(b: *std.Build) !void {
    _ = b.step("test", "Run platform agnostic unit tests");
}

const linker_script = .{ .cwd_relative = build_root ++ "/src/boards/thingplus.ld" };
const hal = .{
    .root_source_file = .{ .cwd_relative = build_root ++ "/src/hal.zig" },
};

pub const chips = struct {
    pub const eos_s3 = MicroZig.Target{
        .preferred_format = .elf,
        .chip = .{
            .name = "EOS-S3",
            .cpu = MicroZig.cpus.cortex_m4,
            .memory_regions = &.{
                .{ .offset = 0x00000000, .length = 0x00027000, .kind = .flash },
                .{ .offset = 0x20027000, .length = 0x0003c800, .kind = .ram },
                .{ .offset = 0x20063800, .length = 0x0000800, .kind = .ram },

                // rom (rx)  : ORIGIN = 0x00000000, LENGTH = 0x00027000
                // ram (rwx) : ORIGIN = 0x20027000, LENGTH = 0x0003c800
                // spiram (rw) : ORIGIN = 0x20063800, LENGTH = 0x0000800
                // HWA (rw)  : ORIGIN = 0x20064000, LENGTH = 0x00018000
                // shm       : ORIGIN = 0x2007C000, LENGTH = 0x00004000
            },
            .register_definition = .{
                .svd = .{ .cwd_relative = build_root ++ "/src/chips/eos-s3.svd" },
                // .json = .{ .cwd_relative = build_root ++ "/src/chips/eos-s3.json" },
            },
        },
        .hal = hal,
        // .linker_script = linker_script,
    };
};

pub const boards = struct {
    pub const thingplus = MicroZig.Target{
        .preferred_format = .elf,
        .chip = chips.eos_s3.chip,
        .board = .{
            .name = "Quicklogic Thing Plus",
            .root_source_file = .{ .cwd_relative = build_root ++ "/src/boards/thingplus.zig" },
        },
        .hal = hal,
        // .linker_script = linker_script,
    };
};
