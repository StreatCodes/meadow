const std = @import("std");

const TableError = error{
    UnsupportedVersion,
};

const Unicode4 = struct {
    length: u16, // Length of subtable in bytes
    language: u16, // Language code (see above)
    seg_count_x2: u16, // 2 * segCount
    search_range: u16, // 2 * (2**FLOOR(log2(segCount)))
    entry_selector: u16, // log2(searchRange/2)
    range_shift: u16, // (2 * segCount) - searchRange
    end_code: []u16, //[segCount] Ending character code for each segment, last = 0xFFFF.
    reserved_pad: u16, // This value should be zero
    start_code: []u16, //[segCount] Starting character code for each segment
    id_delta: []u16, //[segCount] Delta for all character codes in segment
    id_range_offset: []u16, //[segCount] Offset in bytes to glyph indexArray, or 0
    glyph_index_array: []u16, //[variable] Glyph index array

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader) !Unicode4 {
        var unicode4 = Unicode4{
            .length = try reader.readInt(u16, .big),
            .language = try reader.readInt(u16, .big),
            .seg_count_x2 = try reader.readInt(u16, .big),
            .search_range = try reader.readInt(u16, .big),
            .entry_selector = try reader.readInt(u16, .big),
            .range_shift = try reader.readInt(u16, .big),
            .end_code = undefined,
            .reserved_pad = undefined,
            .start_code = undefined,
            .id_delta = undefined,
            .id_range_offset = undefined,
            .glyph_index_array = undefined,
        };

        const seg_count = unicode4.seg_count_x2 / 2;

        unicode4.end_code = try allocator.alloc(u16, seg_count);
        for (0..seg_count) |i| {
            unicode4.end_code[i] = try reader.readInt(u16, .big);
        }

        unicode4.reserved_pad = try reader.readInt(u16, .big);
        if (unicode4.reserved_pad != 0) unreachable;

        unicode4.start_code = try allocator.alloc(u16, seg_count);
        for (0..seg_count) |i| {
            unicode4.start_code[i] = try reader.readInt(u16, .big);
        }

        unicode4.id_delta = try allocator.alloc(u16, seg_count);
        for (0..seg_count) |i| {
            unicode4.id_delta[i] = try reader.readInt(u16, .big);
        }

        unicode4.id_range_offset = try allocator.alloc(u16, seg_count);
        for (0..seg_count) |i| {
            unicode4.id_range_offset[i] = try reader.readInt(u16, .big);
        }

        const bytes_read = 16 + (seg_count * 8);
        const remaining = unicode4.length - bytes_read;

        unicode4.glyph_index_array = try allocator.alloc(u16, remaining / 2);
        for (0..unicode4.glyph_index_array.len) |i| {
            unicode4.glyph_index_array[i] = try reader.readInt(u16, .big);
        }

        return unicode4;
    }

    pub fn deinit(self: Unicode4, allocator: std.mem.Allocator) void {
        allocator.free(self.end_code);
        allocator.free(self.start_code);
        allocator.free(self.id_delta);
        allocator.free(self.id_range_offset);
        allocator.free(self.glyph_index_array);
    }
};

const SubTable = struct {
    platform_id: u16, // Platform identifier
    platform_specific_id: u16, // Platform-specific encoding identifier
    offset: u32, // Offset of the mapping table

    pub fn parse(reader: std.io.AnyReader) !SubTable {
        return SubTable{
            .platform_id = try reader.readInt(u16, .big),
            .platform_specific_id = try reader.readInt(u16, .big),
            .offset = try reader.readInt(u32, .big),
        };
    }
};

pub const CMapTable = struct {
    unicode_table: Unicode4,

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader) !CMapTable {
        const version = try reader.readInt(u16, .big);
        if (version != 0) return TableError.UnsupportedVersion;

        const num_subtables = try reader.readInt(u16, .big);

        var sub_table: ?SubTable = null;
        for (0..num_subtables) |_| {
            const table = try SubTable.parse(reader);
            std.debug.print("CMap table {d}.{d} offset {d}\n", .{ table.platform_id, table.platform_specific_id, table.offset });
            if (table.platform_id == 0 and table.platform_specific_id == 3) {
                sub_table = table;
            }
        }

        if (sub_table == null) return TableError.UnsupportedVersion;
        const header_size = 4 + (num_subtables * @sizeOf(SubTable));
        _ = try reader.skipBytes(sub_table.?.offset - header_size, .{});

        const format = try reader.readInt(u16, .big);
        std.debug.print("Unicode table format {d}\n", .{format});

        const unicode_table = try switch (format) {
            4 => Unicode4.parse(allocator, reader),
            else => TableError.UnsupportedVersion,
        };
        defer std.debug.print("Unicode segment count {d}\n", .{unicode_table.seg_count_x2 / 2});

        return CMapTable{
            .unicode_table = unicode_table,
        };
    }

    pub fn deinit(self: CMapTable, allocator: std.mem.Allocator) void {
        self.unicode_table.deinit(allocator);
    }

    /// Maps the given unicode character code to the index of the glyph
    pub fn map_character(self: CMapTable, char_code: u16) usize {
        var segment: usize = undefined;
        for (0..self.unicode_table.end_code.len) |i| {
            if (char_code <= self.unicode_table.end_code[i]) {
                segment = i;
                break;
            }
        }

        //No glyph for character code
        if (char_code < self.unicode_table.start_code[segment]) {
            return 0;
        }

        const u16_modulo = 65536; // u16 max + 1
        if (self.unicode_table.id_range_offset[segment] == 0) {
            const result: usize = @as(usize, @intCast(char_code)) + @as(usize, @intCast(self.unicode_table.id_delta[segment]));
            return result % u16_modulo;
        }

        const index = self.unicode_table.id_range_offset[segment] / 2 + (char_code - self.unicode_table.start_code[segment]) + segment;
        const glyph_id = self.unicode_table.glyph_index_array[index];
        if (glyph_id == 0) return glyph_id;

        const result: usize = @as(usize, @intCast(glyph_id)) + @as(usize, @intCast(self.unicode_table.id_delta[segment]));
        return result % u16_modulo;
    }
};
