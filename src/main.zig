const std = @import("std");
const registers = @import("registers");

pub const std_options = std.Options{
    .logFn = uartLog,
};

extern fn crashMe() void;

const syscfg_nmi_mask: *volatile u32 = @ptrFromInt(0x40004000);

const CortexM0Plus = struct {
    const base = 0xe0000000;
    const vtor = registers.CortexM0PlusVtor.init(base + 0xed08);
    const nvic_icer: *volatile u32 = @ptrFromInt(base + 0xe100);
    const nvic_iser: *volatile u32 = @ptrFromInt(base + 0xe100);
    const nvic_icpr: *volatile u32 = @ptrFromInt(base + 0xe280);
};

pub fn Uart(comptime base: comptime_int) type {
    return struct {
        const periph_id_0: *volatile u32 = @ptrFromInt(base + 0xfe0);
        const ctrl = registers.UartCr.init(base + 0x030);

        const data = registers.UartData.init(base + 0);

        const ibrd: *volatile u32 = @ptrFromInt(base + 0x24);
        const fbrd: *volatile u32 = @ptrFromInt(base + 0x28);

        const flag = registers.UartFr.init(base + 0x018);
        const line_ctrl = registers.UartLcrH.init(base + 0x02c);
    };
}

const Uart0 = Uart(0x40034000);

pub fn I2c(comptime base: comptime_int) type {
    return struct {
        const con = registers.IcCon.init(base + 0x00);
        const tar = registers.IcTar.init(base + 0x04);
        const data_cmd = registers.IcDataCmd.init(base + 0x10);
        const enable = registers.IcEnable.init(base + 0x6c);
        const comp_version: *volatile u32 = @ptrFromInt(base + 0xf8);
        const ss_scl_lcnt = registers.IcSsSclLCnt.init(base + 0x18);
        const ss_scl_hcnt = registers.IcSsSclHCnt.init(base + 0x14);
        const fs_spklen = registers.IcFsSpkLen.init(base + 0xa0);
        const tx_tl = registers.IcTxTl.init(base + 0x3c);
        const raw_inter_stat = registers.IcRawIntrStat.init(base + 0x34);
    };
}

const I2c0 = I2c(0x40044000);

const Clocks = struct {
    const base = 0x40008000;
    const sys_ctrl = registers.ClkSysCtrl.init(base + 0x3c);
    const sys_selected = registers.ClkSysSelected.init(base + 0x44);
    const peri_ctrl = registers.ClkPeriCtrl.init(base + 0x48);
};

const IoBank0 = struct {
    const base = 0x40014000;

    const intr0 = registers.GpioInterruptMask0.init(base + 0xf0);
    const proc0_interrupt_enable0 = registers.GpioInterruptMask0.init(base + 0x100);
    const proc0_interrupt_force0 = registers.GpioInterruptMask0.init(base + 0x110);
    const proc0_interrupt_status0 = registers.GpioInterruptMask0.init(base + 0x120);

    fn gpioCtrl(num: u32) registers.GpioBankCtrl {
        return .init(base + 4 + 8 * num);
    }
};

const PadsBank0 = struct {
    const base = 0x4001c000;

    fn gpio(num: u32) registers.GpioPadCtrl {
        return .init(base + 4 + 4 * num);
    }
};

const RingOscillator = struct {
    const base = 0x40060000;
    const count: *volatile u32 = @ptrFromInt(base + 0x20);
};

const Reset = struct {
    const base = 0x4000c000;
    const reset = registers.Reset.init(base + 0);
    const done = registers.Reset.init(base + 8);

    const ResetMask = struct {
        pub const io_bank0 = 1 << 5;
        pub const uart0 = 1 << 22;
    };
};

const Sio = struct {
    const base = 0xd0000000;
    const gpio_in: *volatile u32 = @ptrFromInt(base + 0x004);
    const gpio_oe_set: *volatile u32 = @ptrFromInt(base + 0x024);
    const gpio_oe_clr: *volatile u32 = @ptrFromInt(base + 0x028);
    const gpio_set: *volatile u32 = @ptrFromInt(base + 0x014);
    const gpio_clr: *volatile u32 = @ptrFromInt(base + 0x018);
};

const Xosc = struct {
    const base = 0x40024000;

    const ctrl = registers.XoscCtrl.init(base + 0x00);
    const status = registers.XoscStatus.init(base + 0x04);
    const startup = registers.XoscStartup.init(base + 0x0c);

    const count: *volatile u32 = @ptrFromInt(base + 0x1c);

    fn init() void {
        startup.modify(.all(.{
            .x4 = 0,
            .delay = 47, // ~1ms, taken from 2.16.3 of rp2040 datasheet
        }));

        ctrl.modify(.all(.{
            .freq_range = .mhz_1_15,
            .enable = .enabled,
        }));

        while (status.read().stable() == 0) {}
    }
};

fn doWait() void {
    for (0..5000) |_| {
        Xosc.count.* = 0xff;
        while (Xosc.count.* > 0) {}
    }
}

// RPI pico design file schematic
const pico_default_led_pin = 25;

fn regFromAddress(addy: u32) *volatile u32 {
    return @ptrFromInt(addy);
}

fn initGpioInput(gpio: u5) void {
    // Set led pin as input
    Sio.gpio_oe_clr.* = @as(u32, 1) << gpio;

    const pad_ctrl = PadsBank0.gpio(gpio);
    pad_ctrl.modify(comptime .combine(&.{
        .od(0),
        .ie(1),
        .pue(1),
        .pde(0),
        .schmitt(0),
        .slewfast(0),
    }));

    IoBank0.gpioCtrl(gpio).modify(.funcsel(.sio));
}

fn initLed() void {
    // Set led pin as output
    Sio.gpio_oe_set.* = 1 << pico_default_led_pin;

    // Set initial output to 1
    Sio.gpio_set.* = 1 << pico_default_led_pin;

    IoBank0.gpioCtrl(pico_default_led_pin).modify(.funcsel(.sio));
}

fn setLed(on: bool) void {
    if (on) {
        Sio.gpio_set.* = 1 << pico_default_led_pin;
    } else {
        Sio.gpio_clr.* = 1 << pico_default_led_pin;
    }
}

export fn _start() void {
    main() catch {
        unreachable;
    };
}

pub fn uartLog(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = message_level;
    _ = scope;

    var buf: [4096]u8 = undefined;
    const to_print = std.fmt.bufPrint(&buf, format, args) catch &buf;
    uartWrite(to_print);
    uartWrite("\r\n");
}

fn uartWrite(buf: []const u8) void {
    for (buf) |b| {
        while (Uart0.flag.read().txff() != 0) {}
        // Bypass setData() api which does a read/modify/write
        Uart0.data.reg.* = b;
    }
}

fn uartInit() void {
    Reset.reset.atomicClear(.uart0);

    IoBank0.gpioCtrl(0).modify(.funcsel(.uart));
    IoBank0.gpioCtrl(1).modify(.funcsel(.uart));

    Uart0.ctrl.modify(
        comptime .combine(&.{
            .txe(1),
            .uarten(1),
        }),
    );

    // 12Mhz/(16 * 9600) = 78.125
    // FIXME: Technically overwriting reserved
    Uart0.ibrd.* = 78;
    // FIXME: Technically overwriting reserved
    Uart0.fbrd.* = @intFromFloat(0.125 * 64);

    Uart0.line_ctrl.modify(
        .all(.{ .sps = 0, .wlen = .eight, .fen = 0, .stp2 = 0, .eps = 0, .pen = 0, .brk = 0 }),
    );
}

fn initClkSys() void {
    Clocks.sys_ctrl.modify(.auxSrc(.xosc));
    Clocks.sys_ctrl.modify(.src(.aux));
    while (true) {
        const selected = Clocks.sys_selected.read();
        if (selected.aux() == 1 and selected.ref() == 0) {
            break;
        }
    }
}

fn initI2cMasterMode() void {

    // 4.3.10.2.1 in rp2040 datasheet, don't ask me why

    var enable_val = I2c0.enable.read();
    // 1. Disable DW_awp_i2c
    enable_val.modify(.all(.{
        .enable = 0,
        // While we're here, init register in general
        .tx_cmd_block = 0,
        .abort = 0,
    }));
    I2c0.enable.write(enable_val);

    // 2. Init IC_CON
    I2c0.con.modify(comptime .combine(&.{
        .ic_slave_disable(1),
        .ic_10bitaddr_master(0),
        .speed(.standard),
        .master_mode(1),
        // While we're here, init other fields that sound interesting
        .tx_empty_ctrl(0),
        .ic_restart_en(1),
    }));

    // Maybe set tx/rx interrupt fifo watermarks
    // Maybe set dma

    I2c0.tx_tl.modify(.value(0));

    // 3. Set target address
    // Hardcode to EEPROM addy, bottom three bits should be grounded in hw
    const address: u7 = 0b1010000;
    I2c0.tar.modify(comptime .combine(&.{
        .ic_tar(address),
        // While we're here, init other fields that sound interesting
        .special(0),
    }));


    // Initialize clock parameters. This is not specified in the init master
    // mode chapter, however some (maybe all, i didn't check) parameters only
    // are writable when the enable bit is 0, so we might as well do it now
    //
    // Values stolen from table 450, but multiplied by 4.4 for 12Mhz/2.7Mhz in
    // table reference values
    const spike_len = 4;
    I2c0.fs_spklen.modify(.value(spike_len));
    // See bullets under table 450 for formulas
    I2c0.ss_scl_lcnt.modify(.value(13 * 4 - 1));
    I2c0.ss_scl_hcnt.modify(.value(13 * 4 - (spike_len + 7)));

    // 4. re-enable
    enable_val.modify(.enable(1));
    I2c0.enable.write(enable_val);


    // 5. Send data
    var data = I2c0.data_cmd.read();
    data.modify(comptime .combine(&.{
        .restart(0),
        .stop(1),
        .cmd(.write),
        .data('a')
    }));
    // Intentionally bypass our rmw helpers to just slam a raw value in there
    I2c0.data_cmd.reg.* = data.val;
}

fn initI2c() void {
    // Take in and out of reset to reset everything :)
    Reset.reset.atomicSet(.i2c0);
    Reset.reset.atomicClear(.i2c0);
    while (Reset.done.read().i2c0() != 1) {}

    const clock_pin = 17;
    const data_pin = 16;


    for (&[_]u8{data_pin, clock_pin}) |pin| {
        const pad_ctrl = PadsBank0.gpio(pin);
        pad_ctrl.modify(comptime .combine(&.{
            .od(0),
            .ie(1),
            .pue(1),
            .pde(0),
            .schmitt(1),
            .slewfast(0),
        }));

        const bank_ctrl = IoBank0.gpioCtrl(pin);
        bank_ctrl.modify(.funcsel(.i2c));
    }

    while (true){
        initI2cMasterMode();
    }
}


// End of ram
const interrupt_stack = 0x20040000;

const InterruptTable = [42]u32;
var interrupt_vector_table: InterruptTable align(256) = @splat(0xffffffff);

fn initInterruptTable() void {
    interrupt_vector_table[0] = interrupt_stack;
    interrupt_vector_table[11] = @intFromPtr(&svcHandler);
}

export fn someOtherFn() void {
    var x: u32 = 4;
    x += 11;
    const y = x + 5;
    _ = y;
    @breakpoint();
}

fn svcHandler() void {
    var x: u32 = 4;
    x += 11;
    const y = x + 5;
    _ = y;
    someOtherFn();
}

pub fn main() !void {
    initInterruptTable();
    CortexM0Plus.vtor.reg.* = @intFromPtr(&interrupt_vector_table);

    initGpioInput(2);
    const gpio_val = Sio.gpio_in.*;
    _ = gpio_val;

    syscfg_nmi_mask.* = 0;
    IoBank0.intr0.reg.* = 0xffffffff;
    IoBank0.proc0_interrupt_enable0.modify(.gpio4_edge_low(1));

    var intr_status = IoBank0.intr0.reg.*;
    var icpr_status = CortexM0Plus.nvic_icpr.*;
    CortexM0Plus.nvic_iser.* = 1 << (13);
    CortexM0Plus.nvic_icpr.* = 1 << (13);
    const nvic_en_mask = CortexM0Plus.nvic_iser.*;
    _ = nvic_en_mask;

    @breakpoint();
    //crashMe();

    Reset.reset.atomicClear(.io_bank0);

    Xosc.init();

    initClkSys();

    Clocks.peri_ctrl.modify(comptime .combine(&.{
        .auxSrc(.xosc),
        .kill(0),
        .enable(1),
    }));

    uartInit();

    //initI2c();
    initLed();

    var i: u32 = 0;
    while (true) {
        intr_status = IoBank0.intr0.reg.*;
        icpr_status = CortexM0Plus.nvic_icpr.*;
        i +%= 1;
        std.log.debug("hello {d}", .{i});
        setLed(true);
        doWait();
        setLed(false);
        doWait();
    }
}
