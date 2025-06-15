const std = @import("std");

pub const HheaTable = struct {
    version: u16, // 0x00010000 (1.0) //TODO SHOULD BE f16
    ascent: i16, // Distance from baseline of highest ascender
    descent: i16, // Distance from baseline of lowest descender
    line_gap: i16, // typographic line gap
    advance_width_max: u16, // must be consistent with horizontal metrics
    min_left_side_bearing: i16, // must be consistent with horizontal metrics
    min_right_side_bearing: i16, // must be consistent with horizontal metrics
    x_max_extent: i16, // max(lsb + (xMax-xMin))
    caret_slope_rise: i16, // used to calculate the slope of the caret (rise/run) set to 1 for vertical caret
    caret_slope_run: i16, // 0 for vertical
    caret_offset: i16, // set value to 0 for non-slanted fonts
    reserved: i64, // set value to 0
    metric_data_format: i16, // 0 for current format
    num_of_long_hor_metrics: u16, // number of advance widths in metrics table

    pub fn parse(reader: std.io.AnyReader) !HheaTable {
        return HheaTable{
            .version = try reader.readInt(u16, .big),
            .ascent = try reader.readInt(i16, .big),
            .descent = try reader.readInt(i16, .big),
            .line_gap = try reader.readInt(i16, .big),
            .advance_width_max = try reader.readInt(u16, .big),
            .min_left_side_bearing = try reader.readInt(i16, .big),
            .min_right_side_bearing = try reader.readInt(i16, .big),
            .x_max_extent = try reader.readInt(i16, .big),
            .caret_slope_rise = try reader.readInt(i16, .big),
            .caret_slope_run = try reader.readInt(i16, .big),
            .caret_offset = try reader.readInt(i16, .big),
            .reserved = try reader.readInt(i64, .big),
            .metric_data_format = try reader.readInt(i16, .big),
            .num_of_long_hor_metrics = try reader.readInt(u16, .big),
        };
    }
};
