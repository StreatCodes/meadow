const std = @import("std");

//TODO potentially backwards
const Coverage = packed struct {
    subtable_type: u8, // bits 0-7: subtable type
    reserved: u20, // bits 8-27: reserved (0x0FFFFF00 >> 8)
    logical_order: u1, // bit 28 (0x10000000): logical order processing
    both_orientations: u1, // bit 29 (0x20000000): apply to both horizontal and vertical
    descending_order: u1, // bit 30 (0x40000000): descending glyph order
    vertical_text: u1, // bit 31 (0x80000000): vertical text only
};

const MetaMetamorphosisTable = struct {
    length: u32, //Total subtable length, including this header.
    coverage: Coverage, //Coverage flags and subtable type.
    sub_feature_flags: u32, //The 32-bit mask identifying which subtable this is

    pub fn parse(reader: std.io.AnyReader) !MetaMetamorphosisTable {
        var table: MetaMetamorphosisTable = undefined;
        table.length = try reader.readInt(u32, .big);

        var coverage_data: [4]u8 = undefined;
        _ = try reader.readAll(&coverage_data);
        table.coverage = std.mem.bytesToValue(Coverage, &coverage_data);
        table.sub_feature_flags = try reader.readInt(u32, .big);

        std.debug.print("table type: {d}\n", .{table.coverage.subtable_type});
        _ = try reader.skipBytes(table.length - 12, .{});

        // if (table.coverage.subtable_type == 1) {
        //     //TODO REMOVE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        //     _ = try reader.skipBytes(table.length - 12, .{});
        //     std.debug.print("FOUND CONTEXT SUB TABLE\n", .{});
        // } else {
        //     std.debug.print("FOUND UNKNOWN TABLE: {d}\n", .{table.coverage.subtable_type});
        //     //Unsupported, skip reader past content
        //     _ = try reader.skipBytes(table.length - 12, .{});
        // }

        return table;
    }
};

const Feature = struct {
    feature_type: u16, // The type of feature.
    feature_setting: u16, // The feature's setting (aka selector)
    enable_flags: u32, // Flags for the settings that this feature and setting enables.
    disable_flags: u32, // Complement of flags for the settings that this feature and setting disable.

    pub fn parse(reader: std.io.AnyReader) !Feature {
        return Feature{
            .feature_type = try reader.readInt(u16, .big),
            .feature_setting = try reader.readInt(u16, .big),
            .enable_flags = try reader.readInt(u32, .big),
            .disable_flags = try reader.readInt(u32, .big),
        };
    }
};

const Chain = struct {
    default_flags: u32, // The default specification for subtables.
    chain_length: u32, // Total byte count, including this header; must be a multiple of 4.
    num_feature_entries: u32, // Number of feature subtable entries.
    num_subtables: u32, // The number of subtables in the chain.

    features: []Feature,
    meta_subtables: []MetaMetamorphosisTable,

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader) !Chain {
        var chain: Chain = undefined;

        chain.default_flags = try reader.readInt(u32, .big);
        chain.chain_length = try reader.readInt(u32, .big);
        chain.num_feature_entries = try reader.readInt(u32, .big);
        chain.num_subtables = try reader.readInt(u32, .big);

        chain.features = try allocator.alloc(Feature, chain.num_feature_entries);

        for (0..chain.num_feature_entries) |i| {
            const feature = try Feature.parse(reader);
            chain.features[i] = feature;
            std.debug.print("Feature {any}\n", .{feature});
        }

        chain.meta_subtables = try allocator.alloc(MetaMetamorphosisTable, chain.num_subtables);

        for (0..chain.num_subtables) |i| {
            const subtable = try MetaMetamorphosisTable.parse(reader);
            chain.meta_subtables[i] = subtable;
            std.debug.print("Subtable {any}\n", .{subtable});
        }

        return chain;
    }

    pub fn deinit(self: Chain, allocator: std.mem.Allocator) void {
        allocator.free(self.features);
        allocator.free(self.meta_subtables);
    }
};

pub const MorxTable = struct {
    version: u16, //Version number of the extended glyph metamorphosis table (either 2 or 3)
    num_chains: u32, //Number of metamorphosis chains contained in this table

    chains: []Chain,

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader) !MorxTable {
        var morx_table: MorxTable = undefined;

        morx_table.version = try reader.readInt(u16, .big);
        try reader.skipBytes(2, .{}); //Unused data
        morx_table.num_chains = try reader.readInt(u32, .big);

        morx_table.chains = try allocator.alloc(Chain, morx_table.num_chains);

        for (0..morx_table.num_chains) |i| {
            const chain = try Chain.parse(allocator, reader);
            morx_table.chains[i] = chain;
            // try reader.skipBytes(chain.chain_length - @sizeOf(Chain), .{}); //TODO wrong
            std.debug.print("Chain features {d} subtables {d}\n", .{ chain.num_feature_entries, chain.num_subtables });
        }

        return morx_table;
    }

    pub fn deinit(self: MorxTable, allocator: std.mem.Allocator) void {
        for (self.chains) |chain| {
            chain.deinit(allocator);
        }
        allocator.free(self.chains);
    }
};
