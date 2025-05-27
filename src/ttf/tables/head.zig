const std = @import("std");

const HeadTableFlags = packed struct { //2 bytes
    y: u1, //y value of 0 specifies baseline
    x: u1, //x position of left most black bit is LSB
    scale_differ: u1, //scaled point size and actual point size will differ (i.e. 24 point glyph differs from 12 point glyph scaled by factor of 2)
    use_int_scaling: u1, //use integer scaling instead of fractional
    microsoft: u1, //used by the Microsoft implementation of the TrueType scaler
    vertical: u1, //This bit should be set in fonts that are intended to e laid out vertically, and in which the glyphs have been drawn such that an x-coordinate of 0 corresponds to the desired vertical baseline.
    zero: u1, //This bit must be set to zero.
    linguistic_layout: u1, //This bit should be set if the font requires layout for correct linguistic rendering (e.g. Arabic fonts).
    aat_font: u1, //This bit should be set for an AAT font which has one or more metamorphosis effects designated as happening by default.
    strong_rtl: u1, //This bit should be set if the font contains any strong right-to-left glyphs.
    indic_style: u1, //This bit should be set if the font contains Indic-style rearrangement effects.
    adobe: u3, //Defined by Adobe.
    generic_symbols: u1, //This bit should be set if the glyphs in the font are simply generic symbols for code point ranges, such as for a last resort font.
    padding: u1,
};

const MacStyle = packed struct { //2 byte
    bold: u1,
    italic: u1,
    underline: u1,
    outline: u1,
    shadow: u1,
    condensed: u1, //narrow
    extended: u1,
    padding: u9,
};

pub const HeadTable = struct {
    version: u32,
    revision: u32,
    checksum_adjustment: u32,
    magic_number: u32, //0x5F0F3CF5
    flags: HeadTableFlags,
    units_per_em: u16,
    created: u64,
    modified: u64,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
    mac_style: MacStyle,
    lowest_rec_ppem: u16, //smallest readable size in pixels
    /// 0 Mixed directional glyphs
    /// 1 Only strongly left to right glyphs
    /// 2 Like 1 but also contains neutrals
    /// -1 Only strongly right to left glyphs
    /// -2 Like -1 but also contains neutrals
    font_direction_hint: i16,
    index_to_loc_format: i16, //0 for short offsets, 1 for long
    glyph_data_format: i16, //0 for current format

    pub fn parse(reader: std.io.AnyReader) !HeadTable {
        var table: HeadTable = undefined;
        table.version = try reader.readInt(u32, .big);
        table.revision = try reader.readInt(u32, .big);
        table.checksum_adjustment = try reader.readInt(u32, .big);
        table.magic_number = try reader.readInt(u32, .big);

        var flag_data = [2]u8{ 0, 0 };
        _ = try reader.readAll(&flag_data);
        table.flags = std.mem.bytesToValue(HeadTableFlags, &flag_data);

        table.units_per_em = try reader.readInt(u16, .big);
        table.created = try reader.readInt(u64, .big);
        table.modified = try reader.readInt(u64, .big);
        table.x_min = try reader.readInt(i16, .big);
        table.y_min = try reader.readInt(i16, .big);
        table.x_max = try reader.readInt(i16, .big);
        table.y_max = try reader.readInt(i16, .big);

        var style_data = [2]u8{ 0, 0 };
        _ = try reader.readAll(&style_data);
        table.mac_style = std.mem.bytesToValue(MacStyle, &style_data);

        table.lowest_rec_ppem = try reader.readInt(u16, .big);
        table.font_direction_hint = try reader.readInt(i16, .big);
        table.index_to_loc_format = try reader.readInt(i16, .big);
        table.glyph_data_format = try reader.readInt(i16, .big);

        return table;
    }
};
