const std = @import("std");

const GlyphType = enum { simple, compound, empty };
const GlyphEntry = union(GlyphType) {
    simple: SimpleGlyph,
    compound: CompoundGlyph,
    empty: void,
};

const GlyphFlag = packed struct {
    on_curve: u1, // If set, the point is on the curve; Otherwise, it is off the curve.
    x_short_vector: u1, // If set, the corresponding x-coordinate is 1 byte long; Otherwise, the corresponding x-coordinate is 2 bytes long
    y_short_vector: u1, // If set, the corresponding y-coordinate is 1 byte long; Otherwise, the corresponding y-coordinate is 2 bytes long
    repeat: u1, // If set, the next byte specifies the number of additional times this set of flags is to be repeated. In this way, the number of flags listed can be smaller than the number of points in a character.

    // This flag has one of two meanings, depending on how the x-Short Vector flag is set.
    // If the x-Short Vector bit is set, this bit describes the sign of the value, with a value of 1 equalling positive and a zero value negative.
    // If the x-short Vector bit is not set, and this bit is set, then the current x-coordinate is the same as the previous x-coordinate.
    // If the x-short Vector bit is not set, and this bit is not set, the current x-coordinate is a signed 16-bit delta vector. In this case, the delta vector is the change in x
    x_is_same: u1,
    // This flag has one of two meanings, depending on how the y-Short Vector flag is set.
    // If the y-Short Vector bit is set, this bit describes the sign of the value, with a value of 1 equalling positive and a zero value negative.
    // If the y-short Vector bit is not set, and this bit is set, then the current y-coordinate is the same as the previous y-coordinate.
    // If the y-short Vector bit is not set, and this bit is not set, the current y-coordinate is a signed 16-bit delta vector. In this case, the delta vector is the change in y
    y_is_same: u1,
    padding: u2,
};

const SimpleGlyph = struct {
    x_min: i16, // Minimum x for coordinate data
    y_min: i16, // Minimum y for coordinate data
    x_max: i16, // Maximum x for coordinate data
    y_max: i16, // Maximum y for coordinate data

    contour_end_points: []u16,
    instructions: []u8,

    flags: []GlyphFlag,
    x_coordinate: []i16,
    y_coordinate: []i16,

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader, contour_count: usize) !SimpleGlyph {
        var glyph: SimpleGlyph = undefined;

        glyph.x_min = try reader.readInt(i16, .big);
        glyph.y_min = try reader.readInt(i16, .big);
        glyph.x_max = try reader.readInt(i16, .big);
        glyph.y_max = try reader.readInt(i16, .big);

        glyph.contour_end_points = try allocator.alloc(u16, contour_count);
        for (0..contour_count) |i| {
            glyph.contour_end_points[i] = try reader.readInt(u16, .big);
        }

        const instruction_len = try reader.readInt(u16, .big);
        glyph.instructions = try allocator.alloc(u8, instruction_len);
        _ = try reader.readAll(glyph.instructions);

        const last_end_point = glyph.contour_end_points[contour_count - 1];
        const coordinate_count = last_end_point + 1;

        // Read flags
        glyph.flags = try allocator.alloc(GlyphFlag, coordinate_count);
        var i: usize = 0;
        while (i < coordinate_count) : (i += 1) {
            var data: [1]u8 = undefined;
            _ = try reader.readAll(&data);
            const value = std.mem.bytesToValue(GlyphFlag, &data);
            // if (value.padding != 0) unreachable;
            glyph.flags[i] = value;
            if (value.repeat == 1) {
                const repeat_count = try reader.readByte();
                for (0..repeat_count) |_| {
                    i += 1;
                    glyph.flags[i] = value;
                }
            }
        }

        // Read X coordinates
        glyph.x_coordinate = try allocator.alloc(i16, coordinate_count);
        for (0..coordinate_count) |j| {
            const short = glyph.flags[j].x_short_vector == 1;
            const same = glyph.flags[j].x_is_same == 1;

            if (short) {
                const data = try reader.readInt(u8, .big);
                var value: i16 = @intCast(data);
                if (!same) value = -value;
                glyph.x_coordinate[j] = value;
            } else if (same) {
                if (j == 0) {
                    glyph.x_coordinate[j] = 0;
                    continue;
                }
                glyph.x_coordinate[j] = glyph.x_coordinate[j - 1];
            } else {
                glyph.x_coordinate[j] = try reader.readInt(i16, .big);
            }
        }

        // Read Y coordinates
        glyph.y_coordinate = try allocator.alloc(i16, coordinate_count);
        for (0..coordinate_count) |j| {
            const short = glyph.flags[j].y_short_vector == 1;
            const same = glyph.flags[j].y_is_same == 1;

            if (short) {
                const data = try reader.readInt(u8, .big);
                var value: i16 = @intCast(data);
                if (!same) value = -value;
                glyph.y_coordinate[j] = value;
            } else if (same) {
                if (j == 0) {
                    glyph.y_coordinate[j] = 0;
                    continue;
                }
                glyph.y_coordinate[j] = glyph.y_coordinate[j - 1];
            } else {
                glyph.y_coordinate[j] = try reader.readInt(i16, .big);
            }
        }

        return glyph;
    }

    pub fn deinit(self: SimpleGlyph, allocator: std.mem.Allocator) void {
        allocator.free(self.y_coordinate);
        allocator.free(self.x_coordinate);
        allocator.free(self.flags);
        allocator.free(self.contour_end_points);
        allocator.free(self.instructions);
    }
};

const CompoundGlyph = struct {};

pub const GlyfTable = struct {
    glyphs: []GlyphEntry,

    pub fn parse(allocator: std.mem.Allocator, glyf_table_data: []u8, glyph_offsets: []u32) !GlyfTable {
        const num_glyphs = glyph_offsets.len - 1;
        var glyphs = try std.ArrayList(GlyphEntry).initCapacity(allocator, num_glyphs);

        for (0..num_glyphs) |i| {
            const start = glyph_offsets[i];
            const end = glyph_offsets[i + 1];
            const glyph_data = glyf_table_data[start..end];
            var stream = std.io.fixedBufferStream(glyph_data);
            const reader = stream.reader().any();

            if (start == end) {
                try glyphs.append(GlyphEntry{ .empty = void{} });
                continue;
            }

            const contour_count = try reader.readInt(i16, .big);
            if (contour_count < 0) {
                std.debug.print("Warning skipping compound glyph ({d}) TODO\n", .{i});
                try glyphs.append(GlyphEntry{ .compound = CompoundGlyph{} });
                continue;
            } else {
                const glyph = try SimpleGlyph.parse(allocator, reader, @intCast(contour_count));
                try glyphs.append(GlyphEntry{ .simple = glyph });
            }
        }

        return GlyfTable{ .glyphs = try glyphs.toOwnedSlice() };
    }

    pub fn deinit(self: GlyfTable, allocator: std.mem.Allocator) void {
        for (self.glyphs) |entry| {
            switch (entry) {
                .simple => |glyph| glyph.deinit(allocator),
                .compound => {},
                .empty => {},
            }
        }
        allocator.free(self.glyphs);
    }
};
