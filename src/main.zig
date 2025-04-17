const std = @import("std");
const registers = @import("registers");




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

fn atomicClearRegister(in: *volatile u32) *volatile u32 {
    return @ptrFromInt(@as(u32, @intFromPtr(in)) + 0x3000);
}

fn doWait() void {
    for (0..10000) |_| {
        RingOscillator.count.* = 0xff;
        while (RingOscillator.count.* > 0) {}
    }
}

// RPI pico design file schematic
const pico_default_led_pin = 25;

fn regFromAddress(addy: u32) *volatile u32 {
    return @ptrFromInt(addy);
}

fn initLed() void {
    // Take sio out of reset
    Reset.reset.atomicClear(.io_bank0);

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

pub fn main() !void {
    initLed();

    while (true) {
        setLed(true);
        doWait();
        setLed(false);
        doWait();
    }
}
