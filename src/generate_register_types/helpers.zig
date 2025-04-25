const std = @import("std");

pub fn ToIntType(comptime T: type) type {
    const ti = @typeInfo(T);
    switch (ti) {
        .@"enum" => |ei| {
            return ei.tag_type;
        },
        .int => return T,
        else => @compileError("Unhandled field type"),
    }
}

pub fn toIntType(val: anytype) ToIntType(@TypeOf(val)) {
    switch (@typeInfo(@TypeOf(val))) {
        .@"enum" => return @intFromEnum(val),
        .int => return val,
        else => @compileError("Unhandled field type"),
    }
}

pub fn fromIntType(comptime T: type, val: u32) T {
    switch (@typeInfo(T)) {
        .@"enum" => return @enumFromInt(val),
        .int => return @intCast(val),
        else => @compileError("Unhandled field type"),
    }
}

pub fn generateMask(start: u5, end: u5) u32 {
    if (start == 0 and end == 31) return 0xffffffff;

    const mask_aligned_right = (@as(u32, 1) << (end - start + 1)) - 1;
    return mask_aligned_right << start;
}

pub fn getVal(comptime T: type, comptime start: u5, comptime end: u5, val: anytype) T {
    const mask = comptime generateMask(start, end);
    return fromIntType(T, (val & mask) >> start);
}

pub fn combineWriteParams(comptime T: type, params: []const T) T {
    var mask: u32 = 0;
    var val: u32 = 0;
    for (params) |param| {
        std.debug.assert(mask & param.mask == 0);
        mask |= param.mask;
        val |= param.val;
    }
    return .{
        .mask = mask,
        .val = val,
    };
}

pub fn combineWriteMasks(comptime T: type, params: []const T) T {
    var mask: u32 = 0;
    for (params) |param| {
        std.debug.assert(mask & param.mask == 0);
        mask |= param.mask;
    }
    return .{
        .mask = mask,
    };
}

pub inline fn modifyRegister(reg: *volatile u32, mask: u32, val: u32) void {
    var content = reg.*;
    content &= ~mask;
    content |= val;
    reg.* = content;
}

pub fn atomicSetRegister(in: *volatile u32) *volatile u32 {
    return @ptrFromInt(@as(u32, @intFromPtr(in)) + 0x2000);
}

pub fn atomicClearRegister(in: *volatile u32) *volatile u32 {
    return @ptrFromInt(@as(u32, @intFromPtr(in)) + 0x3000);
}
