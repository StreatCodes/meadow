const std = @import("std");

pub const OffsetTable = struct {
    scaler_type: u32, // 0x00010000 for TTF
    num_tables: u16, // Number of tables
    search_range: u16, // Optimization for binary search
    entry_selector: u16, // log₂(maxPowerOf2 ≤ numTables)
    range_shift: u16, // Adjustment for binary search

    pub fn parse(reader: std.io.AnyReader) !OffsetTable {
        return OffsetTable{
            .scaler_type = try reader.readInt(u32, .big),
            .num_tables = try reader.readInt(u16, .big),
            .search_range = try reader.readInt(u16, .big),
            .entry_selector = try reader.readInt(u16, .big),
            .range_shift = try reader.readInt(u16, .big),
        };
    }
};

pub const TableDirectory = struct {
    tag: [4]u8, //identifies the table (e.g., 'cmap', 'glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp', 'name', 'post')
    checksum: u32, //checksum for the table
    offset: u32, //byte offset from beginning of file to the table
    length: u32, //length of the table in bytes

    pub fn parse(reader: std.io.AnyReader) !TableDirectory {
        var dir = TableDirectory{
            .tag = .{ 0, 0, 0, 0 },
            .checksum = 0,
            .offset = 0,
            .length = 0,
        };

        _ = try reader.readAll(&dir.tag);
        dir.checksum = try reader.readInt(u32, .big);
        dir.offset = try reader.readInt(u32, .big);
        dir.length = try reader.readInt(u32, .big);
        return dir;
    }
};
