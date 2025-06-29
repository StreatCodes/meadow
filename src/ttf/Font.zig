const std = @import("std");
const headers = @import("./headers.zig");
const HeadTable = @import("./tables/head.zig").HeadTable;
const MaxpTable = @import("./tables/maxp.zig").MaxpTable;
const LocaTable = @import("./tables/loca.zig").LocaTable;
const GlyfTable = @import("./tables/glyf.zig").GlyfTable;
const CMapTable = @import("./tables/cmap.zig").CMapTable;
const HheaTable = @import("./tables/hhea.zig").HheaTable;
const HmtxTable = @import("./tables/hmtx.zig").HmtxTable;
// const MorxTable = @import("./tables/morx.zig").MorxTable;

const Glyph = @import("./tables/glyf.zig").Glyph;
const TableDirectory = headers.TableDirectory;
const OffsetTable = headers.OffsetTable;
const Font = @This();

head_table: HeadTable,
loca_table: LocaTable,
maxp_table: MaxpTable,
glyf_table: GlyfTable,
cmap_table: CMapTable,
hhea_table: HheaTable,
hmtx_table: HmtxTable,
// morx_table: MorxTable,

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

    const cmap_data = getTableData(table_directories, table_data, "cmap");
    var cmap_stream = std.io.fixedBufferStream(cmap_data);
    const cmap_reader = cmap_stream.reader().any();
    const cmap_table = try CMapTable.parse(allocator, cmap_reader);

    const hhea_data = getTableData(table_directories, table_data, "hhea");
    var hhea_stream = std.io.fixedBufferStream(hhea_data);
    const hhea_reader = hhea_stream.reader().any();
    const hhea_table = try HheaTable.parse(hhea_reader);

    const hmtx_data = getTableData(table_directories, table_data, "hmtx");
    var hmtx_stream = std.io.fixedBufferStream(hmtx_data);
    const hmtx_reader = hmtx_stream.reader().any();
    const hmtx_table = try HmtxTable.parse(allocator, hmtx_reader, hhea_table.num_of_long_hor_metrics, glyf_table.glyphs.len);

    // Didn't end up needing this
    // Apple's advanced positional and ligature information
    // const morx_data = getTableData(table_directories, table_data, "morx");
    // var morx_stream = std.io.fixedBufferStream(morx_data);
    // const morx_reader = morx_stream.reader().any();
    // const morx_table = try MorxTable.parse(allocator, morx_reader);

    return Font{
        .head_table = head_table,
        .loca_table = loca_table,
        .maxp_table = maxp_table,
        .glyf_table = glyf_table,
        .cmap_table = cmap_table,
        .hhea_table = hhea_table,
        .hmtx_table = hmtx_table,
        // .morx_table = morx_table,
    };
}

pub fn deinit(font: Font, allocator: std.mem.Allocator) void {
    font.glyf_table.deinit(allocator);
    font.loca_table.deinit(allocator);
    font.cmap_table.deinit(allocator);
    font.hmtx_table.deinit(allocator);
    // font.morx_table.deinit(allocator);
}

/// Returns the ID of the glyph for the given unicode character
pub fn getGlyphId(self: Font, char_code: u21) usize {
    const unicode_table = self.cmap_table.unicode_table;
    var segment: usize = undefined;
    for (0..unicode_table.end_code.len) |i| {
        if (char_code <= unicode_table.end_code[i]) {
            segment = i;
            break;
        }
    }

    //No glyph for character code
    if (char_code < unicode_table.start_code[segment]) {
        return 0;
    }

    const u16_modulo = 65536; // u16 max + 1
    if (unicode_table.id_range_offset[segment] == 0) {
        const result: usize = @as(usize, @intCast(char_code)) + @as(usize, @intCast(unicode_table.id_delta[segment]));
        return result % u16_modulo;
    }

    const index = unicode_table.id_range_offset[segment] / 2 + (char_code - unicode_table.start_code[segment]) + segment;
    const glyph_id = unicode_table.glyph_index_array[index];
    if (glyph_id == 0) {
        return glyph_id;
    }

    const result: usize = @as(usize, @intCast(glyph_id)) + @as(usize, @intCast(unicode_table.id_delta[segment]));
    return result % u16_modulo;
}

pub fn getGlyph(self: Font, glyph_id: usize) Glyph {
    return self.glyf_table.glyphs[glyph_id];
}
