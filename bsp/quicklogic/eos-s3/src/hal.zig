const std = @import("std");
const microzig = @import("microzig");
const regs = microzig.chip.peripherals;
const cm4 = microzig.cpu.peripherals;
const cpu = microzig.cpu;

pub const uart = @import("hal/uart.zig");

pub const ClockHz = 72_000_000;
pub const SysTicksPerSecond = 1_000_000;

var systemTicks: u32 = 0;

pub const microzig_options = struct {
    pub const interrupts = struct {
        pub fn HardFault() void {
            @panic("Hard fault");
        }

        pub fn SysTick() void {
            cpu.disable_interrupts();
            systemTicks += 1;
            cpu.enable_interrupts();
        }

        // pub fn UART() void {
        //     @panic("UART");
        // }

        // pub fn NMI() void {
        //     @panic("NMI");
        // }

        // pub fn MemManageFault() void {
        //     @panic("MemManageFault");
        // }

        // pub fn BusFault() void {
        //     @panic("BusFault");
        // }

        // pub fn UsageFault() void {
        //     @panic("UsageFault");
        // }

        // pub fn SVCall() void {
        //     @panic("SVCall");
        // }

        // pub fn PendSV() void {
        //     @panic("PendSV");
        // }

        // pub fn Software_Interrupt_2() void {
        //     @panic("Software_Interrupt_2");
        // }

        // pub fn Software_Interrupt_1() void {
        //     @panic("Software_Interrupt_1");
        // }

        // pub fn FFE0_Message() void {
        //     @panic("FFE0_Message");
        // }
        // pub fn Fabric_Message() void {
        //     @panic("Fabric_Message");
        // }

        // pub fn Sensor_GPIO() void {
        //     @panic("Sensor_GPIO");
        // }
        // pub fn TIMER() void {
        //     @panic("TIMER");
        // }
        // pub fn CPU_WDOG_INTR() void {
        //     @panic("CPU_WDOG_INTR");
        // }
        // pub fn FPU() void {
        //     @panic("FPU");
        // }
        // pub fn CPU_WDOG_RST() void {
        //     @panic("CPU_WDOG_RST");
        // }

        // TIMER: Handler = unhandled,
        // CPU_WDOG_INTR: Handler = unhandled,
        // CPU_WDOG_RST: Handler = unhandled,
        // BUS_Timeout: Handler = unhandled,
        // FPU: Handler = unhandled,
        // PKFB: Handler = unhandled,
        // I2S: Handler = unhandled,
        // Audio: Handler = unhandled,
        // SPI_MS: Handler = unhandled,
        // CFG_DMA: Handler = unhandled,
        // PMU_TIMER: Handler = unhandled,
        // ///  ADC Done interrupt
        // ADC_DONE: Handler = unhandled,
        // RTC_Alarm: Handler = unhandled,
        // Reset_Interrupt: Handler = unhandled,
        // FFE0_Combined: Handler = unhandled,
        // FFE_WDT: Handler = unhandled,
        // AP_Boot: Handler = unhandled,
        // LDO30_PG_INTR: Handler = unhandled,
        // LDO50_PG_INTR: Handler = unhandled,
        // SRAM_128_TIMEOUT: Handler = unhandled,
        // LPSD_Voice_Det: Handler = unhandled,
        // DMIC_Voice_Det: Handler = unhandled,
        // reserved44: [1]u32 = undefined,
        // SDMA_DONE_1: Handler = unhandled,
        // SDMA_DONE_2: Handler = unhandled,
        // SDMA_DONE_3: Handler = unhandled,
        // SDMA_DONE_4: Handler = unhandled,
        // SDMA_DONE_5: Handler = unhandled,
        // SDMA_DONE_6: Handler = unhandled,
        // SDMA_DONE_7: Handler = unhandled,
        // SDMA_DONE_8: Handler = unhandled,
        // SDMA_DONE_9: Handler = unhandled,
        // SDMA_DONE_10: Handler = unhandled,
        // SDMA_DONE_11: Handler = unhandled,
        // AP_PDM_CLK_ON: Handler = unhandled,
        // AP_PDM_CLK_OFF: Handler = unhandled,
        // DMAC0_BLK_DONE: Handler = unhandled,
        // DMAC0_BUF_DONE: Handler = unhandled,
        // DMAC1_BLK_DONE: Handler = unhandled,
        // DMAC1_BUF_DONE: Handler = unhandled,
        // SDMA_DONE_0: Handler = unhandled,
        // SDMA_ERR: Handler = unhandled,
        // I2SSLV_M4_tx_or_intr: Handler = unhandled,
        // LPSD_VOICE_OFF: Handler = unhandled,
        // DMIC_VOICE_OFF: Handler = unhandled,
    };
};

// copied from: qorc-sdk\BSP\quickfeather\src\qf_baremetalsetup.c
pub fn init() void {
    systemTicks = 0;
    regs.SCB_ACTRL.ACTRL.modify(.{ .DISDEFWBUF = 1 });

    // Initialize AIP registers (HSOSC)
    regs.AIP.OSC_CTRL_1.modify(.{ .prog = ClockHz / 32768 - 3 }); // (72,000,000/32,768) - 3

    // Initialize power registers
    regs.PMU.FB_STATUS.modify(.{ .FB_Active = 1 });

    regs.PMU.A1_PWR_MODE_CFG.modify(.{ .A1_Power_Mode_Cfg = .shut_down_mode });
    regs.PMU.MISC_STATUS.modify(.{ .I2S = 1 });
    regs.PMU.AUDIO_STATUS.modify(.{
        .AD0 = 1,
        .AD1 = 1,
        .AD2 = 1,
        .AD3 = 1,
        .AD4 = 1,
        .AD5 = 1,
    }); // = 0x03F; // Power up all audio domains

    // Configure Memory to support light sleep and retention mode */
    regs.PMU.M4SRAM_SSW_LPMF.write_raw(0xFFFF);
    regs.PMU.M4SRAM_SSW_LPMH_MASK_N.write_raw(0xFFFF);

    // Initialize clock registers
    // For Clock 10 (SYNC Up on A0 and AHB Interface of Batching Memory, AUDIO DMA, M4 SRAMs,M4 Bus Matrix and Trace block)
    regs.CRU.CLK_CTRL_A_0.write_raw(0);

    //  For Clock 2 (FB, A1 (Including CFGSM))
    regs.CRU.CLK_CTRL_B_0.write(.{
        .Clock_Divider_Ratio = 0x46,
        .Enable_Clock_Divider = 1,
    }); //(0x246);

    //  For Clock 8 X4 (FFE X4 clk)
    regs.CRU.CLK_CTRL_C_0.write(.{
        .Clock_Divider_Ratio = 0x22,
        .Enable_Clock_Divider = 1,
    }); // 0x222);
    // For Clock 11 (To M4 peripherals - AHB/APB bridge, UART, WDT and TIMER)
    regs.CRU.CLK_CTRL_D_0.write(.{
        .Clock_Divider_Ratio = 0x22,
        .Enable_Clock_Divider = 1,
    }); // 0x222);
    //  For Clock 16 (FB)
    regs.CRU.CLK_CTRL_F_0.write(.{
        .Clock_Divider_Ratio = 0x04,
        .Enable_Clock_Divider = 1,
    }); // 0x204);
    //  For Clock 30 (PDM LEFT/RIGHT clk, I2S Master clk)
    regs.CRU.CLK_CTRL_G_0.write(.{
        .Clock_Divider_Ratio = 0x21,
        .Enable_Clock_Divider = 1,
    }); //0x221);
    // ADC
    regs.CRU.CLK_CTRL_H_0.write(.{
        .Clock_Divider_Ratio = 0x1FE,
        .Enable_Clock_Divider = 1,
    }); // 0x3FE);
    regs.CRU.CLK_CTRL_I_0.write_raw(0x200);
    regs.CRU.C01_CLK_GATE.write_raw(0x011);
    regs.CRU.C02_CLK_GATE.write_raw(0x001);
    regs.CRU.C10_FCLK_GATE.write_raw(0x05F);

    regs.MISC.LOCK_KEY_CTRL.write_raw(0x1ACCE551);

    regs.CRU.C11_CLK_GATE.write_raw(0x001);
    regs.CRU.C16_CLK_GATE.write_raw(0x001);
    regs.CRU.C21_CLK_GATE.write_raw(0x001);
    regs.CRU.C01_CLK_DIV.write_raw(0x017);
    regs.CRU.C09_CLK_DIV.write_raw(0x01B);
    regs.CRU.C31_CLK_DIV.write_raw(0x003);
    regs.CRU.CLK_DIVIDER_CLK_GATING.write_raw(0x33B);

    // /* set CP10 and CP11 Full Access */
    // SCB->CPACR |= ((3UL << 10*2)|(3UL << 11*2));
    cpu.scb.CPACR |= ((3 << 10 * 2) | (3 << 11 * 2));

    regs.INTR_CTRL.OTHER_INTR.write_raw(0xffffff);

    regs.DMA.DMA_CTRL.modify(.{ .dma_stop = 1 });

    // /* LDO Settings */
    regs.AIP.LDO_30_CTRL_0.write_raw(0x1ac); // LDO Enable       /* 0x1ac -> Vo =1.01V, imax = 7.2mA, LDO enabled. */
    regs.AIP.LDO_50_CTRL_0.write_raw(0x1ac); // LDO Enable
    regs.AIP.LDO_30_CTRL_0.write_raw(0x28c); // LDO Enable       /* 0x28c -> Vo =1.15V, imax = 7.2mA, LDO enabled. */
    regs.AIP.LDO_50_CTRL_0.write_raw(0x28c); // LDO Enable

    cm4.SysTick.LOAD.modify(.{ .RELOAD = ClockHz / SysTicksPerSecond });
    cm4.SysTick.VAL.modify(.{ .CURRENT = 0 });
    cm4.SysTick.CTRL.modify(.{
        .CLKSOURCE = 1,
        .TICKINT = 1,
        .ENABLE = 1,
    });
}

pub fn millisToSysTicks(ms: u32) u32 {
    return ms * (SysTicksPerSecond / 1000);
}

pub fn sysTicksToMillis(ticks: u32) u32 {
    return ticks / 1000;
}

pub fn spinForMillis(ms: u32) void {
    spinForMicros(ms * 1000);
}

pub fn spinForMicros(us: u32) void {
    var a: u32 = 0;
    // systick is micro seconds
    const ticks = systemTicks;

    while (systemTicks - ticks < us) {
        a += 1;
        std.mem.doNotOptimizeAway(u32);
    }
}

pub fn sysTicks() u32 {
    return systemTicks;
}
