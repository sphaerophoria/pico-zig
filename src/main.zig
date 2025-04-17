const std = @import("std");
const registers = @import("registers");

pub const std_options = std.Options{
    .logFn = uartLog,
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

const Clocks = struct {
    const base = 0x40008000;
    const peri_ctrl = registers.ClkPeriCtrl.init(base + 0x48);
};

const IoBank0 = struct {
    const base = 0x40014000;

    fn gpioCtrl(num: u32) registers.GpioCtrl {
        return .init(base + 4 + 8 * num);
    }
};

const RingOscillator = struct {
    const base = 0x40060000;
    const count: *volatile u32 = @ptrFromInt(base + 0x20);
};

const Reset = struct {
    const base = 0x4000c000;
    const reset = registers.Reset.init(base + 0);

    const ResetMask = struct {
        pub const io_bank0 = 1 << 5;
        pub const uart0 = 1 << 22;
    };
};

const Sio = struct {
    const base = 0xd0000000;
    const gpio_oe_set: *volatile u32 = @ptrFromInt(base + 0x024);
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

fn atomicClearRegister(in: *volatile u32) *volatile u32 {
    return @ptrFromInt(@as(u32, @intFromPtr(in)) + 0x3000);
}

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

pub fn main() !void {
    Reset.reset.atomicClear(.io_bank0);

    Xosc.init();

    Clocks.peri_ctrl.modify(comptime .combine(&.{
        .auxSrc(.xosc),
        .kill(0),
        .enable(1),
    }));

    uartInit();

    initLed();

    var i: u32 = 0;
    while (true) {
        i +%= 1;
        std.log.debug("hello {d}", .{i});
        setLed(true);
        doWait();
        setLed(false);
        doWait();
    }
}
