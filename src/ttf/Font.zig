const std = @import("std");
const headers = @import("./headers.zig");
const HeadTable = @import("./tables/head.zig").HeadTable;
const MaxpTable = @import("./tables/maxp.zig").MaxpTable;
const LocaTable = @import("./tables/loca.zig").LocaTable;
const GlyfTable = @import("./tables/glyf.zig").GlyfTable;

const TableDirectory = headers.TableDirectory;
const OffsetTable = headers.OffsetTable;
const Font = @This();

head_table: HeadTable,
loca_table: LocaTable,
maxp_table: MaxpTable,
glyf_table: GlyfTable,

fn getTableData(directory: []TableDirectory, table_data: []u8, tag: []const u8) []u8 {
    const headers_length = @sizeOf(OffsetTable) + (@sizeOf(TableDirectory) * directory.len);
    for (directory) |table_info| {
        if (std.mem.eql(u8, &table_info.tag, tag)) {
            const start = table_info.offset - headers_length;
            const end = start + table_info.length;
            std.debug.print("{s} at {d}-{d}\n", .{ tag, start, end });
            return table_data[start..end];
        }
    }

    unreachable; //TODO return error, required table not found
}

pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader) !Font {
    const offset_table = try OffsetTable.parse(reader);
    const table_directories = try allocator.alloc(TableDirectory, offset_table.num_tables);
    defer allocator.free(table_directories);

    std.debug.print("Found {d} tables:\n", .{table_directories.len});

    const std_out = std.io.getStdOut();
    var i: usize = 0;
    while (i < table_directories.len) : (i += 1) {
        const table = try TableDirectory.parse(reader);
        table_directories[i] = table;
        try std_out.writeAll(&table.tag);
        if (i != table_directories.len - 1) {
            try std_out.writeAll(", ");
        } else {
            try std_out.writeAll("\n");
        }
    }

    const table_data = try reader.readAllAlloc(allocator, 50 * 1000 * 1024);
    defer allocator.free(table_data);

    const head_data = getTableData(table_directories, table_data, "head");
    var head_stream = std.io.fixedBufferStream(head_data);
    const head_reader = head_stream.reader().any();
    const head_table = try HeadTable.parse(head_reader);
    std.debug.print("Units per em: {d}\n", .{head_table.units_per_em});
    std.debug.print("Location format {d}\n", .{head_table.index_to_loc_format});

    const maxp_data = getTableData(table_directories, table_data, "maxp");
    var maxp_stream = std.io.fixedBufferStream(maxp_data);
    const maxp_reader = maxp_stream.reader().any();
    const maxp_table = try MaxpTable.parse(maxp_reader);
    std.debug.print("Number of glyphs: {d}\n", .{maxp_table.num_glyphs});

    const loca_data = getTableData(table_directories, table_data, "loca");
    var loca_stream = std.io.fixedBufferStream(loca_data);
    const loca_reader = loca_stream.reader().any();
    const loca_table = try LocaTable.parse(allocator, loca_reader, maxp_table.num_glyphs, head_table.index_to_loc_format);
    std.debug.print("offsets: {d}\n", .{loca_table.offsets.len});

    const glyf_data = getTableData(table_directories, table_data, "glyf");
    const glyf_table = try GlyfTable.parse(allocator, glyf_data, loca_table.offsets);
    std.debug.print("Glyphs: {d}\n", .{glyf_table.glyphs.len});

    return Font{
        .head_table = head_table,
        .loca_table = loca_table,
        .maxp_table = maxp_table,
        .glyf_table = glyf_table,
    };
}

pub fn deinit(font: Font, allocator: std.mem.Allocator) void {
    defer font.glyf_table.deinit(allocator);
    defer font.loca_table.deinit(allocator);
}
