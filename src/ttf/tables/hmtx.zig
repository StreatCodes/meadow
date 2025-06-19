const std = @import("std");

const HorizontalMetric = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

pub const HmtxTable = struct {
    h_metrics: []HorizontalMetric,
    left_side_bearing: []i16,

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader, num_h_metrics: usize, num_glyphs: usize) !HmtxTable {
        var metrics = try allocator.alloc(HorizontalMetric, num_h_metrics);
        for (0..num_h_metrics) |i| {
            metrics[i] = HorizontalMetric{
                .advance_width = try reader.readInt(u16, .big),
                .left_side_bearing = try reader.readInt(i16, .big),
            };
        }

        const bearings = try allocator.alloc(i16, num_glyphs - num_h_metrics);
        for (0..bearings.len) |i| {
            bearings[i] = try reader.readInt(i16, .big);
        }

        return HmtxTable{
            .h_metrics = metrics,
            .left_side_bearing = bearings,
        };
    }

    pub fn deinit(self: HmtxTable, allocator: std.mem.Allocator) void {
        allocator.free(self.h_metrics);
        allocator.free(self.left_side_bearing);
    }

    pub fn getGlyphSpacing(self: HmtxTable, glyph_id: usize) HorizontalMetric {
        //Use the last h_metric advance width glyph_id greater than number of horizontal metrics
        if (self.h_metrics.len > 0 and glyph_id >= self.h_metrics.len) {
            return HorizontalMetric{
                .advance_width = self.h_metrics[self.h_metrics.len - 1].advance_width,
                .left_side_bearing = self.left_side_bearing[glyph_id],
            };
        }

        return self.h_metrics[glyph_id];
    }
};
