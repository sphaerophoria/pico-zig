const std = @import("std");

const BitOffset = u5;
// Inclusive range
const BitRange = struct {
    start: BitOffset,
    end: BitOffset,

    fn len(self: BitRange) usize {
        return self.end - self.start + 1;
    }
};

fn parseBitRange(val: std.json.Value) !BitRange {
    const arr = switch (val) {
        .array => |a| a,
        .integer => |i| {
            const offs = std.math.cast(BitOffset, i) orelse return error.OutOfRange;
            return .{
                .start = offs,
                .end = offs,
            };
        },
        else => return error.InvalidRange,
    };

    if (arr.items.len != 2 or
        arr.items[0] != .integer or
        arr.items[1] != .integer)
    {
        return error.InvalidRange;
    }

    const a = std.math.cast(BitOffset, arr.items[0].integer) orelse return error.OutOfRange;
    const b = std.math.cast(BitOffset, arr.items[1].integer) orelse return error.OutOfRange;

    return .{
        .start = @min(a, b),
        .end = @max(a, b),
    };
}

pub const RegisterField = union(enum) {
    untyped: BitRange,
    typed: struct {
        enum_name: []const u8,
        offset: BitRange,
    },

    pub fn typeName(self: RegisterField, alloc: std.mem.Allocator) ![]const u8 {
        switch (self) {
            .untyped => |range| {
                return try std.fmt.allocPrint(alloc, "u{d}", .{range.len()});
            },
            .typed => |t| {
                return t.enum_name;
            },
        }
    }

    pub fn start(self: RegisterField) BitOffset {
        switch (self) {
            .untyped => |range| {
                return range.start;
            },
            .typed => |t| {
                return t.offset.start;
            },
        }
    }

    pub fn end(self: RegisterField) BitOffset {
        switch (self) {
            .untyped => |range| {
                return range.end;
            },
            .typed => |t| {
                return t.offset.end;
            },
        }
    }

    // FIXME: Conform to JSON parser api
    pub fn fromJson(val: std.json.Value) !RegisterField {
        switch (val) {
            .array, .integer => {
                return .{ .untyped = try parseBitRange(val) };
            },
            .object => |o| {
                const typ = o.get("type") orelse return error.NoType;
                const offset = o.get("offset") orelse return error.NoOffset;
                const typ_name = switch (typ) {
                    .string => |s| s,
                    else => return error.InvalidTypeName,
                };
                const range = try parseBitRange(offset);
                return .{
                    .typed = .{
                        .enum_name = typ_name,
                        .offset = range,
                    },
                };
            },
            else => return error.InvalidFieldtype,
        }
    }
};

pub const EnumDefinition = struct {
    bit_size: u8,
    fields: std.json.ArrayHashMap(u32),
};

pub const RegisterDefinition = struct {
    fields: std.json.ArrayHashMap(std.json.Value),
    enums: std.json.ArrayHashMap(EnumDefinition) = .{},
};
