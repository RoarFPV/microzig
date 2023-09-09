const std = @import("std");
const microzig = @import("microzig");
const mmio = microzig.mmio;
const root = @import("root");

pub const regs = struct {
    // Interrupt Control and State Register
    pub const ICSR: *volatile mmio.Mmio(packed struct {
        VECTACTIVE: u9,
        reserved0: u2,
        RETTOBASE: u1,
        VECTPENDING: u9,
        reserved1: u1,
        ISRPENDING: u1,
        ISRPREEMPT: u1,
        reserved2: u1,
        PENDSTCLR: u1,
        PENDSTSET: u1,
        PENDSVCLR: u1,
        PENDSVSET: u1,
        reserved3: u2,
        NMIPENDSET: u1,
    }) = @ptrFromInt(0xE000ED04);
};

pub fn executing_isr() bool {
    return regs.ICSR.read().VECTACTIVE != 0;
}

pub fn enable_interrupts() void {
    asm volatile ("cpsie i");
}

pub fn disable_interrupts() void {
    asm volatile ("cpsid i");
}

pub fn enable_fault_irq() void {
    asm volatile ("cpsie f");
}
pub fn disable_fault_irq() void {
    asm volatile ("cpsid f");
}

pub fn nop() void {
    asm volatile ("nop");
}
pub fn wfi() void {
    asm volatile ("wfi");
}
pub fn wfe() void {
    asm volatile ("wfe");
}
pub fn sev() void {
    asm volatile ("sev");
}
pub fn isb() void {
    asm volatile ("isb");
}
pub fn dsb() void {
    asm volatile ("dsb");
}
pub fn dmb() void {
    asm volatile ("dmb");
}
pub fn clrex() void {
    asm volatile ("clrex");
}

pub const startup_logic = struct {
    extern fn microzig_main() noreturn;

    // it looks odd to just use a u8 here, but in C it's common to use a
    // char when linking these values from the linkerscript. What's
    // important is the addresses of these values.
    extern var microzig_data_start: u8;
    extern var microzig_data_end: u8;
    extern var microzig_bss_start: u8;
    extern var microzig_bss_end: u8;
    extern const microzig_data_load_start: u8;

    pub fn _start() callconv(.C) noreturn {

        // fill .bss with zeroes
        {
            const bss_start: [*]u8 = @ptrCast(&microzig_bss_start);
            const bss_end: [*]u8 = @ptrCast(&microzig_bss_end);
            const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);

            @memset(bss_start[0..bss_len], 0);
        }

        // load .data from flash
        {
            const data_start: [*]u8 = @ptrCast(&microzig_data_start);
            const data_end: [*]u8 = @ptrCast(&microzig_data_end);
            const data_len = @intFromPtr(data_end) - @intFromPtr(data_start);
            const data_src: [*]const u8 = @ptrCast(&microzig_data_load_start);

            @memcpy(data_start[0..data_len], data_src[0..data_len]);
        }

        microzig_main();
    }
};

fn is_valid_field(field_name: []const u8) bool {
    return !std.mem.startsWith(u8, field_name, "reserved") and
        !std.mem.eql(u8, field_name, "initial_stack_pointer") and
        !std.mem.eql(u8, field_name, "reset");
}

const VectorTable = if (@hasDecl(root, "microzig_options") and @hasDecl(root.microzig_options, "VectorTable"))
    root.microzig_options.VectorTable
else if (microzig.hal != void and @hasDecl(microzig.hal, "VectorTable"))
    microzig.hal.VectorTable
else
    microzig.chip.VectorTable;

// will be imported by microzig.zig to allow system startup.
pub var vector_table: VectorTable = blk: {
    var tmp: VectorTable = .{
        .initial_stack_pointer = microzig.config.end_of_stack,
        .Reset = .{ .C = microzig.cpu.startup_logic._start },
    };
    if (@hasDecl(root, "microzig_options") and @hasDecl(root.microzig_options, "interrupts")) {
        const interrupts = root.microzig_options.interrupts;
        if (@typeInfo(interrupts) != .Struct)
            @compileLog("root.interrupts must be a struct");

        inline for (@typeInfo(interrupts).Struct.decls) |decl| {
            const function = @field(interrupts, decl.name);

            if (!@hasField(VectorTable, decl.name)) {
                var msg: []const u8 = "There is no such interrupt as '" ++ decl.name ++ "'. Declarations in 'interrupts' must be one of:\n";
                inline for (std.meta.fields(VectorTable)) |field| {
                    if (is_valid_field(field.name)) {
                        msg = msg ++ "    " ++ field.name ++ "\n";
                    }
                }

                @compileError(msg);
            }

            if (!is_valid_field(decl.name))
                @compileError("You are not allowed to specify '" ++ decl.name ++ "' in the vector table, for your sins you must now pay a $5 fine to the ZSF: https://github.com/sponsors/ziglang");

            @field(tmp, decl.name) = create_interrupt_vector(function);
        }
    }
    break :blk tmp;
};

fn create_interrupt_vector(
    comptime function: anytype,
) microzig.interrupt.Handler {
    const calling_convention = @typeInfo(@TypeOf(function)).Fn.calling_convention;
    return switch (calling_convention) {
        .C => .{ .C = function },
        .Naked => .{ .Naked = function },
        // for unspecified calling convention we are going to generate small wrapper
        .Unspecified => .{
            .C = struct {
                fn wrapper() callconv(.C) void {
                    if (calling_convention == .Unspecified) // TODO: workaround for some weird stage1 bug
                        @call(.always_inline, function, .{});
                }
            }.wrapper,
        },

        else => |val| {
            const conv_name = inline for (std.meta.fields(std.builtin.CallingConvention)) |field| {
                if (val == @field(std.builtin.CallingConvention, field.name))
                    break field.name;
            } else unreachable;

            @compileError("unsupported calling convention for interrupt vector: " ++ conv_name);
        },
    };
}

pub const peripherals = struct {
    ///  System Tick Timer
    pub const SysTick = @as(*volatile types.peripherals.SysTick, @ptrFromInt(0xe000e010));

    ///  System Control Space
    pub const NVIC = @compileError("TODO"); // @ptrFromInt(*volatile types.peripherals.NVIC, 0xe000e100);

    ///  System Control Block
    pub const SCB = @as(*volatile types.peripherals.SCB, @ptrFromInt(0xe000ed00));
};

pub const types = struct {
    pub const peripherals = struct {
        ///  System Tick Timer
        pub const SysTick = extern struct {
            ///  SysTick Control and Status Register
            CTRL: mmio.Mmio(packed struct(u32) {
                ENABLE: u1,
                TICKINT: u1,
                CLKSOURCE: u1,
                reserved16: u13,
                COUNTFLAG: u1,
                padding: u15,
            }),
            ///  SysTick Reload Value Register
            LOAD: mmio.Mmio(packed struct(u32) {
                RELOAD: u24,
                padding: u8,
            }),
            ///  SysTick Current Value Register
            VAL: mmio.Mmio(packed struct(u32) {
                CURRENT: u24,
                padding: u8,
            }),
            ///  SysTick Calibration Register
            CALIB: mmio.Mmio(packed struct(u32) {
                TENMS: u24,
                reserved30: u6,
                SKEW: u1,
                NOREF: u1,
            }),
        };

        // typedef struct
        // {
        // __IM  uint32_t CPUID;                  /*!< Offset: 0x000 (R/ )  CPUID Base Register */
        // __IOM uint32_t ICSR;                   /*!< Offset: 0x004 (R/W)  Interrupt Control and State Register */
        // __IOM uint32_t VTOR;                   /*!< Offset: 0x008 (R/W)  Vector Table Offset Register */
        // __IOM uint32_t AIRCR;                  /*!< Offset: 0x00C (R/W)  Application Interrupt and Reset Control Register */
        // __IOM uint32_t SCR;                    /*!< Offset: 0x010 (R/W)  System Control Register */
        // __IOM uint32_t CCR;                    /*!< Offset: 0x014 (R/W)  Configuration Control Register */
        // __IOM uint8_t  SHP[12U];               /*!< Offset: 0x018 (R/W)  System Handlers Priority Registers (4-7, 8-11, 12-15) */
        // __IOM uint32_t SHCSR;                  /*!< Offset: 0x024 (R/W)  System Handler Control and State Register */
        // __IOM uint32_t CFSR;                   /*!< Offset: 0x028 (R/W)  Configurable Fault Status Register */
        // __IOM uint32_t HFSR;                   /*!< Offset: 0x02C (R/W)  HardFault Status Register */
        // __IOM uint32_t DFSR;                   /*!< Offset: 0x030 (R/W)  Debug Fault Status Register */
        // __IOM uint32_t MMFAR;                  /*!< Offset: 0x034 (R/W)  MemManage Fault Address Register */
        // __IOM uint32_t BFAR;                   /*!< Offset: 0x038 (R/W)  BusFault Address Register */
        // __IOM uint32_t AFSR;                   /*!< Offset: 0x03C (R/W)  Auxiliary Fault Status Register */
        // __IM  uint32_t PFR[2U];                /*!< Offset: 0x040 (R/ )  Processor Feature Register */
        // __IM  uint32_t DFR;                    /*!< Offset: 0x048 (R/ )  Debug Feature Register */
        // __IM  uint32_t ADR;                    /*!< Offset: 0x04C (R/ )  Auxiliary Feature Register */
        // __IM  uint32_t MMFR[4U];               /*!< Offset: 0x050 (R/ )  Memory Model Feature Register */
        // __IM  uint32_t ISAR[5U];               /*!< Offset: 0x060 (R/ )  Instruction Set Attributes Register */
        //         uint32_t RESERVED0[5U];
        // __IOM uint32_t CPACR;                  /*!< Offset: 0x088 (R/W)  Coprocessor Access Control Register */
        // } SCB_Type;

        ///  System Control Block
        pub const SCB = extern struct {
            /// /*!< Offset: 0x000 (R/ )  CPUID Base Register */
            CPUID: mmio.Mmio(packed struct(u32) {
                REVISION: u4,
                PARTNO: u12,
                ARCHITECTURE: u4,
                VARIANT: u4,
                IMPLEMENTER: u8,
            }),
            ///  Interrupt Control and State Register
            /// /*!< Offset: 0x004 (R/W)  Interrupt Control and State Register */
            ICSR: mmio.Mmio(packed struct(u32) {
                VECTACTIVE: u9,
                reserved12: u3,
                VECTPENDING: u9,
                reserved22: u1,
                ISRPENDING: u1,
                ISRPREEMPT: u1,
                reserved25: u1,
                PENDSTCLR: u1,
                PENDSTSET: u1,
                PENDSVCLR: u1,
                PENDSVSET: u1,
                reserved31: u2,
                NMIPENDSET: u1,
            }),
            ///  Vector Table Offset Register
            /// /*!< Offset: 0x008 (R/W)  Vector Table Offset Register */
            VTOR: mmio.Mmio(packed struct(u32) {
                reserved8: u8,
                TBLOFF: u24,
            }),
            ///  Application Interrupt and Reset Control Register
            /// /*!< Offset: 0x00C (R/W)  Application Interrupt and Reset Control Register */
            AIRCR: mmio.Mmio(packed struct(u32) {
                reserved1: u1,
                VECTCLRACTIVE: u1,
                SYSRESETREQ: u1,
                reserved15: u12,
                ENDIANESS: u1,
                VECTKEY: u16,
            }),
            ///  System Control Register
            /// /*!< Offset: 0x010 (R/W)  System Control Register */
            SCR: mmio.Mmio(packed struct(u32) {
                reserved1: u1,
                SLEEPONEXIT: u1,
                SLEEPDEEP: u1,
                reserved4: u1,
                SEVONPEND: u1,
                padding: u27,
            }),
            ///  Configuration Control Register
            /// /*!< Offset: 0x014 (R/W)  Configuration Control Register */
            CCR: mmio.Mmio(packed struct(u32) {
                reserved3: u3,
                UNALIGN_TRP: u1,
                reserved9: u5,
                STKALIGN: u1,
                padding: u22,
            }),
            reserved28: [4]u8,
            ///  System Handlers Priority Registers. [0] is RESERVED
            /// __IOM uint8_t  SHP[12U];               /*!< Offset: 0x018 (R/W)  System Handlers Priority Registers (4-7, 8-11, 12-15) */
            SHP: u32,
            reserved36: [4]u8,
            ///  System Handler Control and State Register
            /// /*!< Offset: 0x024 (R/W)  System Handler Control and State Register */
            SHCSR: mmio.Mmio(packed struct(u32) {
                reserved15: u15,
                SVCALLPENDED: u1,
                padding: u16,
            }),

            /// /*!< Offset: 0x028 (R/W)  Configurable Fault Status Register */
            CFSR: u32,
            HFSR: u32,
            DFSR: u32,
            MMFAR: u32,
            BFAR: u32,
            AFSR: u32,
            PFR: [2]u32,
            DFR: u32,
            ADR: u32,
            MMFR: [4]u32,
            ISAR: [5]u32,
            reserved37: [5]u32,

            CPACR: u32,
        };
    };
};
