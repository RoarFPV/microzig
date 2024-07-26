const std = @import("std");

const microzig = @import("microzig");
const hw = microzig.hal;
const cpu = microzig.cpu;
const regs = microzig.chip.peripherals;
const cm4 = cpu.peripherals;
const uart = hw.uart;
//const time = eos_s3.time;

fn initLeds() void {
    // #if (FPGA_DIS_PAD26_CFG == 0)
    // 	IO_MUX->PAD_26_CTRL = 0x103;
    // #endif
    // 00   | 00   | 01   | 03
    // 0000 | 0000 | 0001 | 0011

    const led_out_4ma = .{
        .FUNC_SEL = .alternative_3,
        .OEN = .normal_operation,
        .E = .current_4ma,
    };

    regs.IOMUX.PAD_CTRL[22].modify(led_out_4ma);

    regs.IOMUX.PAD_CTRL[18].modify(led_out_4ma);
    regs.IOMUX.PAD_CTRL[21].modify(led_out_4ma);
}

fn turnOnLeds(on: bool) void {
    if (on) {
        //const output: u8 = @as(u8, on) << 4;
        //regs.MISC.IO_OUTPUT.write_raw(output);
        regs.MISC.IO_OUTPUT.modify(.{
            .IO_1 = 1,
            //.IO_4 = 1, // BLUE
            .IO_5 = 1, // GREEN
            //.IO_6 = 1, // RED
        });
    } else {
        regs.MISC.IO_OUTPUT.write_raw(0x0);
    }
}

pub fn main() !void {
    uart.init(.{ .clock = 2_000_000 }); // 72_000_000 / 36

    initLeds();

    const fabricId = regs.MISC.FB_DEVICE_ID.read();
    uart.log("{x}", .{fabricId.ID});

    var on = false;
    while (true) {
        const start = hw.sysTicks();
        on = !on;
        turnOnLeds(on);
        uart.log("leds: {}, sysTicks: {}", .{ @intFromBool(on), start });

        const current = hw.sysTicks();
        const deltaTicks = current - @min(current, start);
        const deltaMs = hw.sysTicksToMillis(deltaTicks);
        // this needs to account for time taken
        hw.spinForMillis(1000 - deltaMs);
    }
}
