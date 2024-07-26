const std = @import("std");
const microzig = @import("microzig");
const peri = microzig.chip.peripherals;
const cpu = microzig.cpu.peripherals;

fn compute_divider(baud: u32) u32 {
    return (baud * 16);
}

fn compute_ibrd(clock: u32, baud: u32) u32 {
    const divider = compute_divider(baud);
    return (clock / divider);
}

fn compute_fbrd(clock: u32, baud: u32) u32 {
    const divider = compute_divider(baud);

    const fclock: f32 = @floatFromInt(clock);
    const fdivider: f32 = @floatFromInt(divider);

    var fbrd: f32 = (fclock / fdivider);
    fbrd = fbrd - @as(f32, @floatFromInt(clock / divider));
    fbrd = fbrd * 64 + 0.5;
    return @intFromFloat(fbrd);
}

pub const Config = struct {
    pub const Word = enum {
        five,
        six,
        seven,
        eight,
    };

    pub const Stop = enum {
        one,
        two,
    };

    pub const Parity = enum {
        none,
        even,
        odd,
    };

    pub const Bits = struct {
        word: Word,
        stop: Stop,
    };

    baud: u32 = 115200,
    clock: u32,
    bits: Bits = .{ .word = .eight, .stop = .one },
    parity: Parity = .none,
};

const UART = peri.UART;

pub fn init(comptime config: Config) void {
    const fbrd = compute_fbrd(config.clock, config.baud);
    const ibrd = compute_ibrd(config.clock, config.baud);

    // Disable
    UART.CR.write_raw(0);
    UART.LCR_H.write_raw(0);

    peri.MISC.LOCK_KEY_CTRL.write_raw(0x1ACCE551);

    const txPin = &peri.IOMUX.PAD_CTRL[44];

    txPin.write(.{
        .FUNC_SEL = .alternative_3, // PAD44_FUNC_SEL_UART_TXD
        .CTRL_SEL = .a0_registers,
        .OEN = .normal_operation,
        .P = .z,
        .E = .current_4ma,
        .SR = .slow,
        .REN = .disable_receive,
        .SMT = .disable_trigger,
        .padding = 0,
        .reserved3 = 0,
    });

    const rxPin = &peri.IOMUX.PAD_CTRL[45];

    rxPin.write(.{
        .FUNC_SEL = .alternative_0, // PAD44_FUNC_SEL_UART_TXD
        .CTRL_SEL = .a0_registers,
        .OEN = .normal_operation,
        .P = .z,
        .E = .current_4ma,
        .SR = .slow,
        .REN = .enable_receive,
        .SMT = .disable_trigger,
        .padding = 0,
        .reserved3 = 0,
    });

    peri.IOMUX.UART_rxd_SEL.modify(.{ .SEL = .pad_45 });

    //     { // setup UART TX
    //     .ucPin = PAD_44,
    //     .ucFunc = PAD44_FUNC_SEL_UART_TXD,
    //     .ucCtrl = PAD_CTRL_SRC_A0,
    //     .ucMode = PAD_MODE_OUTPUT_EN,
    //     .ucPull = PAD_NOPULL,
    //     .ucDrv = PAD_DRV_STRENGHT_4MA,
    //     .ucSpeed = PAD_SLEW_RATE_SLOW,
    //     .ucSmtTrg = PAD_SMT_TRIG_DIS,
    //   },
    //   { // setup UART RX
    //     .ucPin = PAD_45,                     // Options: 14, 16, 25, or 45
    //     .ucFunc = PAD45_FUNC_SEL_UART_RXD,
    //     .ucCtrl = PAD_CTRL_SRC_A0,
    //     .ucMode = PAD_MODE_INPUT_EN,
    //     .ucPull = PAD_NOPULL,
    //     .ucDrv = PAD_DRV_STRENGHT_4MA,
    //     .ucSpeed = PAD_SLEW_RATE_SLOW,
    //     .ucSmtTrg = PAD_SMT_TRIG_DIS,
    //   },

    // Set baud
    UART.IBRD.write_raw(ibrd);
    UART.FBRD.write_raw(fbrd);

    UART.LCR_H.modify(.{
        .FEN = .enable_fifos,
        .WLEN = .use_8_bit_word,
    });
    //.enable_fifos } });
    UART.IMSC.write_raw(0);
    UART.IFLS.modify(.{
        .TXIFLSEL = .one_half,
        .RXIFLSEL = .one_eight,
    });

    UART.CR.modify(.{
        .UARTEN = .uart_enable,
        .TXE = 1,
        .RXE = 1,
        .RTSEn = 0,
        .CTSEn = 0,
    });

    logger = writer();
    logger.?.writeAll("\r\n================= UART Logger Started ==========================\r\n") catch {};
}

pub fn write(context: u32, data: []const u8) WriteError!usize {
    _ = context;
    for (data) |byte| {
        var tfr = UART.TFR.read();
        while (tfr.TXFF == 1) {
            tfr = UART.TFR.read();
        }
        UART.DR.write(.{
            .DATA = byte,
            .FE = 0,
            .PE = 0,
            .BE = 0,
            .OE = 0,
        });
    }
    return data.len;
}

pub fn read(context: u32, data: []const u8) ReadError!usize {
    _ = context;
    for (data) |*byte| {
        while (UART.TFR.read().RXFE == 0) {}
        byte.* = UART.DR.read().DATA;
    }
    return data.len;
}

const WriteError = error{};
const ReadError = error{};
pub const Writer = std.io.Writer(u32, WriteError, write);
pub const Reader = std.io.Reader(u32, ReadError, read);

pub fn writer() Writer {
    return .{ .context = 0 };
}

pub fn reader() Reader {
    return .{ .context = 0 };
}

var logger: ?Writer = null;

pub fn log(comptime format: []const u8, args: anytype) void {
    if (logger) |uart| {
        uart.print(format ++ "\r\n", args) catch {};
    }
}
