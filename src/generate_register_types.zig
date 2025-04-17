const std = @import("std");
const rd = @import("generate_register_types/register_defs.zig");

pub fn DefinitionWriter(comptime Writer: type) type {
    return struct {
        writer: Writer,
        name: []const u8,

        const Self = @This();

        pub fn startRootStruct(self: Self) !void {
            try self.writer.print(
                \\pub const {0s} = struct {{
                \\    reg: *volatile u32,
                \\
                \\
                \\    pub fn init(reg: usize) {0s} {{
                \\        return .{{
                \\            .reg = @ptrFromInt(reg),
                \\        }};
                \\    }}
                \\
                \\    pub fn read(self: {0s}) Value {{
                \\        return @bitCast(self.reg.*);
                \\    }}
                \\
                \\    pub fn write(self: {0s}, val: Value) void {{
                \\        self.reg.* = @bitCast(val);
                \\    }}
                \\
                \\    pub inline fn modify(self: {0s}, params: WriteParams) void {{
                \\        helpers.modifyRegister(self.reg, params.mask, params.val);
                \\    }}
                \\
                \\    pub inline fn atomicClear(self: {0s}, params: WriteMask) void {{
                \\        helpers.atomicClearRegister(self.reg).* = params.mask;
                \\    }}
                \\
                \\
            , .{self.name});
        }

        pub fn endRootStruct(self: Self) !void {
            try self.writer.writeAll("};\n");
        }

        pub fn startWriteParams(self: Self) !void {
            // FIXME: all() should probably be defined in a way where runtime field
            // values can be passed
            //
            // FIXME: AtomicClear/AtomicSet should use a WriteParams that only has mask
            try self.writer.writeAll(
                \\pub const WriteParams = struct {
                \\    mask: u32,
                \\    val: u32,
                \\
                \\    pub fn all(comptime vals: All) WriteParams {
                \\         return comptime blk: {
                \\             const fields = std.meta.fields(All);
                \\             var params: [fields.len]WriteParams = undefined;
                \\             for (fields, 0..) |field, i| {
                \\                 params[i] = @field(WriteParams, field.name)(@field(vals, field.name));
                \\             }
                \\             break :blk helpers.combineWriteParams(WriteParams, &params);
                \\         };
                \\    }
                \\
                \\    pub fn combine(params: []const WriteParams) WriteParams {
                \\         return helpers.combineWriteParams(WriteParams, params);
                \\    }
            );
        }

        pub fn endWriteParams(self: Self) !void {
            try self.writer.writeAll("};\n");
        }

        pub fn writeWriteParamsFns(self: Self, fba_const: std.heap.FixedBufferAllocator, fields: std.json.ArrayHashMap(std.json.Value)) !void {
            var fba = fba_const;
            var it = fields.map.iterator();

            while (it.next()) |field| {
                const checkpoint = fba.end_index;
                defer fba.end_index = checkpoint;

                const register_field = try rd.RegisterField.fromJson(field.value_ptr.*);

                try self.writer.print(
                    \\
                    \\    pub fn {0s}(val: {1s}) WriteParams {{
                    \\        return .{{
                    \\            .mask = helpers.generateMask({2d}, {3d}),
                    \\            .val = @as(u32, helpers.toIntType(val)) << {2d},
                    \\        }};
                    \\    }}
                    \\
                ,
                    .{
                        field.key_ptr.*,
                        try register_field.typeName(fba.allocator()),
                        register_field.start(),
                        register_field.end(),
                    },
                );
            }
        }

        pub fn startWriteMask(self: Self) !void {
            try self.writer.writeAll(
                \\pub const WriteMask = struct {
                \\    mask: u32,
                \\
                \\    pub fn combine(params: []const WriteMask) WriteMask {
                \\         return helpers.combineWriteMasks(WriteMask, params);
                \\    }
            );
        }

        pub fn writeWriteMaskFns(self: Self, fba_const: std.heap.FixedBufferAllocator, fields: std.json.ArrayHashMap(std.json.Value)) !void {
            var fba = fba_const;
            var it = fields.map.iterator();

            while (it.next()) |field| {
                const checkpoint = fba.end_index;
                defer fba.end_index = checkpoint;

                const register_field = try rd.RegisterField.fromJson(field.value_ptr.*);

                try self.writer.print(
                    \\    pub const {0s} = WriteMask{{ .mask =  helpers.generateMask({1d}, {2d})}};
                ,
                    .{
                        field.key_ptr.*,
                        register_field.start(),
                        register_field.end(),
                    },
                );
            }
        }

        pub fn endWriteMask(self: Self) !void {
            try self.writer.writeAll("};\n");
        }

        pub fn startAll(self: Self) !void {
            try self.writer.writeAll("const All = struct {\n");
        }

        pub fn endAll(self: Self) !void {
            try self.writer.writeAll("};\n");
        }

        pub fn writeAllFields(self: Self, fba_const: std.heap.FixedBufferAllocator, fields: std.json.ArrayHashMap(std.json.Value)) !void {
            var fba = fba_const;
            var it = fields.map.iterator();
            while (it.next()) |field| {
                const checkpoint = fba.end_index;
                defer fba.end_index = checkpoint;

                const register_field = try rd.RegisterField.fromJson(field.value_ptr.*);
                try self.writer.print(
                    "{s}: {s},\n",
                    .{
                        field.key_ptr.*,
                        try register_field.typeName(fba.allocator()),
                    },
                );
            }
        }

        pub fn startEnum(self: Self, name: []const u8, bit_size: u8) !void {
            try self.writer.print("pub const {s} = enum(u{d}) {{\n", .{
                name,
                bit_size,
            });
        }

        pub fn writeEnumFields(self: Self, definition: rd.EnumDefinition) !void {
            var it = definition.fields.map.iterator();
            while (it.next()) |field| {
                try self.writer.print("{s} = {d},\n", .{
                    field.key_ptr.*,
                    field.value_ptr.*,
                });
            }

            const max_elems = @as(u32, 1) << @intCast(definition.bit_size);
            if (definition.fields.map.count() < max_elems) {
                try self.writer.writeAll("_");
            }
        }

        pub fn endEnum(self: Self) !void {
            try self.writer.writeAll("};\n");
        }

        pub fn startValue(self: Self) !void {
            try self.writer.writeAll(
                \\pub const Value = packed struct(u32) {
                \\    val: u32,
                \\
                \\    fn modify(self: *Value, params: WriteParams) void {
                \\        self.val &= ~params.mask;
                \\        self.val |= params.val;
                \\    }
            );
        }

        pub fn endValue(self: Self) !void {
            try self.writer.writeAll("};\n");
        }

        pub fn writeValueGetters(self: Self, linear_alloc: std.heap.FixedBufferAllocator, fields: std.StringArrayHashMapUnmanaged(std.json.Value)) !void {
            var linear_alloc_mut = linear_alloc;
            var it = fields.iterator();
            while (it.next()) |field| {
                const checkpoint = linear_alloc_mut.end_index;
                defer linear_alloc_mut.end_index = checkpoint;

                const register_field = try rd.RegisterField.fromJson(field.value_ptr.*);
                try self.writer.print(
                    \\
                    \\    pub fn {0s}(self: Value) {1s} {{
                    \\        return helpers.getVal({1s}, {2d}, {3d}, self.val);
                    \\    }}
                    \\
                ,
                    .{
                        field.key_ptr.*,
                        try register_field.typeName(linear_alloc_mut.allocator()),
                        register_field.start(),
                        register_field.end(),
                    },
                );
            }
        }
    };
}

fn definitionWriter(writer: anytype, name: []const u8) DefinitionWriter(@TypeOf(writer)) {
    return .{
        .writer = writer,
        .name = name,
    };
}

fn loadFile(linear_alloc: *std.heap.FixedBufferAllocator, path: []const u8) ![]u8 {
    // readToEndAlloc will over-allocate with an ArrayList, allocate max size
    // off rip, and then dial it back after

    const f = try std.fs.cwd().openFile(path, .{});

    const buf = try linear_alloc.allocator().alloc(u8, linear_alloc.buffer.len - linear_alloc.end_index);
    const size = try f.readAll(buf);
    linear_alloc.end_index = buf.ptr + size - linear_alloc.buffer.ptr;
    return buf[0..size];
}

fn loadRegisterDefinition(linear_alloc: *std.heap.FixedBufferAllocator, path: []const u8) !std.json.ArrayHashMap(rd.RegisterDefinition) {
    const file_content = try loadFile(linear_alloc, path);
    return try std.json.parseFromSliceLeaky(
        std.json.ArrayHashMap(rd.RegisterDefinition),
        linear_alloc.allocator(),
        file_content,
        .{},
    );
}

pub fn main() !void {
    var linear_alloc = std.heap.FixedBufferAllocator.init(try std.heap.page_allocator.alloc(u8, 10 * 1024 * 1024));
    const alloc = linear_alloc.allocator();

    const args = try std.process.argsAlloc(alloc);
    const register_def_path = args[1];
    const output_file_path = args[2];

    const parsed = try loadRegisterDefinition(&linear_alloc, register_def_path);
    var it = parsed.map.iterator();

    const out_buf = try alloc.alloc(u8, 1 * 1024 * 1024);

    var buf_fbs = std.io.fixedBufferStream(out_buf);
    const output = buf_fbs.writer();

    try output.writeAll(
        \\const std = @import("std");
        \\const helpers = @import("helpers");
        \\
        \\
    );

    while (it.next()) |definition| {
        const checkpoint = linear_alloc.end_index;
        defer linear_alloc.end_index = checkpoint;

        const definition_writer = definitionWriter(output, definition.key_ptr.*);
        try definition_writer.startRootStruct();

        {
            try definition_writer.startWriteParams();
            try definition_writer.writeWriteParamsFns(linear_alloc, definition.value_ptr.fields);
            try definition_writer.endWriteParams();

            try definition_writer.startWriteMask();
            try definition_writer.writeWriteMaskFns(linear_alloc, definition.value_ptr.fields);
            try definition_writer.endWriteMask();

            try definition_writer.startAll();
            try definition_writer.writeAllFields(linear_alloc, definition.value_ptr.fields);
            try definition_writer.endAll();
        }

        var enums = definition.value_ptr.enums.map.iterator();
        while (enums.next()) |e| {
            try definition_writer.startEnum(e.key_ptr.*, e.value_ptr.bit_size);
            try definition_writer.writeEnumFields(e.value_ptr.*);
            try definition_writer.endEnum();
        }

        try definition_writer.startValue();
        try definition_writer.writeValueGetters(linear_alloc, definition.value_ptr.fields.map);
        try definition_writer.endValue();

        try definition_writer.endRootStruct();
    }

    // Null terminate
    out_buf[buf_fbs.pos] = 0;
    const ast = try std.zig.Ast.parse(alloc, out_buf[0..buf_fbs.pos :0], .zig);
    // We aren't allowed to render if there's a syntax error, so fall back on
    // what we tried to format so we can get proper compile errors later
    const formatted = if (ast.errors.len > 0) buf_fbs.getWritten() else try ast.render(alloc);

    const out_f = try std.fs.cwd().createFile(output_file_path, .{});
    try out_f.writeAll(formatted);
}
