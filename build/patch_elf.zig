const std = @import("std");
const Allocator = std.mem.Allocator;

const Crc = std.hash.crc.Crc(u32, .{
        .polynomial = 0x04c11db7,
        .initial = 0xffffffff,
        .reflect_input = false,
        .reflect_output = false,
        .xor_output = 0,
});


fn getStringTable(alloc: Allocator, header: std.elf.Header, f: std.fs.File) ![]const u8 {
    const string_table_index = header.shstrndx;
    var sections = header.section_header_iterator(f);
    for (0..string_table_index) |_| _ = try sections.next();
    const string_table = try sections.next() orelse unreachable;

    const strings_start = string_table.sh_offset;
    const strings_len = string_table.sh_size;

    const strings_buf = try alloc.alloc(u8, strings_len);
    try f.seekTo(strings_start);
    const strings_read_len = try f.readAll(strings_buf);
    std.debug.assert(strings_read_len == strings_buf.len);

    return strings_buf;
}

fn findBoot2Offs(alloc: Allocator, f: std.fs.File) !usize {
    const header = try std.elf.Header.read(f);
    const strings = try getStringTable(alloc, header, f);

    var sections = header.section_header_iterator(f);
    while (try sections.next()) |section| {
        const name_start = section.sh_name;
        const name_len = std.mem.indexOfScalar(u8, strings[name_start..], 0) orelse unreachable;
        const name_end = name_start + name_len;
        const name = strings[name_start..name_end];
        if (std.mem.eql(u8, ".boot2", name) ) {
            return section.sh_offset;
        }
    }
    unreachable;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const args = try std.process.argsAlloc(alloc);
    const in_path = args[1];
    const out_path = args[2];

    try std.fs.cwd().copyFile(in_path, std.fs.cwd(), out_path, .{});

    const f = try std.fs.cwd().openFile(out_path, .{
        .mode = .read_write,
    });

    const boot2_offs = try findBoot2Offs(alloc, f);
    try f.seekTo(boot2_offs);

    var boot2_buf: [256]u8 = undefined;
    _ = try f.readAll(&boot2_buf);

    var hasher = Crc.init();
    hasher.update(boot2_buf[0..252]);
    const crc = hasher.final();

    try f.seekTo(boot2_offs + 252);
    try f.writer().writeInt(u32, crc, .little);
}
