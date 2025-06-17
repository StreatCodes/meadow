const std = @import("std");

const GlyphType = enum { simple, compound, empty };
pub const Glyph = union(GlyphType) {
    simple: SimpleGlyph,
    compound: CompoundGlyph,
    empty: void,
};

pub const SimpleGlyphFlag = packed struct {
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

pub const SimpleGlyph = struct {
    x_min: i16, // Minimum x for coordinate data
    y_min: i16, // Minimum y for coordinate data
    x_max: i16, // Maximum x for coordinate data
    y_max: i16, // Maximum y for coordinate data

    contour_end_points: []u16,
    instructions: []u8,

    flags: []SimpleGlyphFlag,
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
        glyph.flags = try allocator.alloc(SimpleGlyphFlag, coordinate_count);
        var i: usize = 0;
        while (i < coordinate_count) : (i += 1) {
            var data: [1]u8 = undefined;
            _ = try reader.readAll(&data);
            const value = std.mem.bytesToValue(SimpleGlyphFlag, &data);
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
            const prev = if (j == 0) 0 else glyph.x_coordinate[j - 1];

            if (short) {
                const data = try reader.readInt(u8, .big);
                var value: i16 = @intCast(data);
                if (!same) value = -value;
                glyph.x_coordinate[j] = prev + value;
            } else if (same) {
                glyph.x_coordinate[j] = prev;
            } else {
                glyph.x_coordinate[j] = prev + try reader.readInt(i16, .big);
            }
        }

        // Read Y coordinates
        glyph.y_coordinate = try allocator.alloc(i16, coordinate_count);
        for (0..coordinate_count) |j| {
            const short = glyph.flags[j].y_short_vector == 1;
            const same = glyph.flags[j].y_is_same == 1;
            const prev = if (j == 0) 0 else glyph.y_coordinate[j - 1];

            if (short) {
                const data = try reader.readInt(u8, .big);
                var value: i16 = @intCast(data);
                if (!same) value = -value;
                glyph.y_coordinate[j] = prev + value;
            } else if (same) {
                glyph.y_coordinate[j] = prev;
            } else {
                glyph.y_coordinate[j] = prev + try reader.readInt(i16, .big);
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

const CompoundGlyphTransformation = struct {
    xscale: f32,
    yscale: f32,
    scale01: f32,
    scale10: f32,
};

const CompoundGlyphFlags = packed struct {
    args_are_words: u1, //If set, the arguments are words; If not set, they are bytes.
    args_are_xy_values: u1, //If set, the arguments are xy values; If not set, they are points.
    round_xy: u1, //If set, round the xy values to grid; if not set do not round xy values to grid (relevant only to bit 1 is set)
    is_scaled: u1, //If set, there is a simple scale for the component. If not set, scale is 1.0.
    obsolete: u1, //obsolete; set to zero
    more_components: u1, //If set, at least one additional glyph follows this one.
    we_have_an_x_and_y_scale: u1, //If set the x direction will use a different scale than the y direction.
    we_have_a_two_by_two: u1, //If set there is a 2-by-2 transformation that will be used to scale the component.
    we_have_instructions: u1, //If set, instructions for the component character follow the last component.
    use_my_metrics: u1, //Use metrics from this component for the compound glyph.
    overlap_compound: u1, //If set, the components of this compound glyph overlap.
    padding: u5,
};

const CompoundGlyphComponent = struct {
    flags: CompoundGlyphFlags,
    glyph_index: u16,
    arg1: i32,
    arg2: i32,

    pub fn parse(reader: std.io.AnyReader) !CompoundGlyphComponent {
        var component: CompoundGlyphComponent = undefined;
        var data: [2]u8 = undefined;
        _ = try reader.readAll(&data);
        const flags = std.mem.bytesToValue(CompoundGlyphFlags, &data);

        component.flags = flags;
        component.glyph_index = try reader.readInt(u16, .big);

        if (flags.args_are_words == 1 and flags.args_are_xy_values == 1) {
            component.arg1 = @intCast(try reader.readInt(i16, .big));
            component.arg2 = @intCast(try reader.readInt(i16, .big));
        } else if (flags.args_are_words == 0 and flags.args_are_xy_values == 1) {
            component.arg1 = @intCast(try reader.readInt(i8, .big));
            component.arg2 = @intCast(try reader.readInt(i8, .big));
        } else if (flags.args_are_words == 1 and flags.args_are_xy_values == 0) {
            component.arg1 = @intCast(try reader.readInt(u16, .big));
            component.arg2 = @intCast(try reader.readInt(u16, .big));
        } else {
            component.arg1 = @intCast(try reader.readInt(u8, .big));
            component.arg2 = @intCast(try reader.readInt(u8, .big));
        }

        return component;
    }
};

const CompoundGlyph = struct {
    x_min: i16, // Minimum x for coordinate data
    y_min: i16, // Minimum y for coordinate data
    x_max: i16, // Maximum x for coordinate data
    y_max: i16, // Maximum y for coordinate data

    components: []CompoundGlyphComponent,

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader) !CompoundGlyph {
        var glyph: CompoundGlyph = undefined;

        glyph.x_min = try reader.readInt(i16, .big);
        glyph.y_min = try reader.readInt(i16, .big);
        glyph.x_max = try reader.readInt(i16, .big);
        glyph.y_max = try reader.readInt(i16, .big);

        var components = std.ArrayList(CompoundGlyphComponent).init(allocator);
        while (true) {
            const component = try CompoundGlyphComponent.parse(reader);
            try components.append(component);
            if (component.flags.more_components == 0) break;
        }
        glyph.components = try components.toOwnedSlice();

        return glyph;
    }

    pub fn deinit(self: CompoundGlyph, allocator: std.mem.Allocator) void {
        allocator.free(self.components);
    }
};

pub const GlyfTable = struct {
    glyphs: []Glyph,

    pub fn parse(allocator: std.mem.Allocator, glyf_table_data: []u8, glyph_offsets: []u32) !GlyfTable {
        const num_glyphs = glyph_offsets.len - 1;
        var glyphs = try std.ArrayList(Glyph).initCapacity(allocator, num_glyphs);

        for (0..num_glyphs) |i| {
            const start = glyph_offsets[i];
            const end = glyph_offsets[i + 1];
            const glyph_data = glyf_table_data[start..end];
            var stream = std.io.fixedBufferStream(glyph_data);
            const reader = stream.reader().any();

            if (start == end) {
                try glyphs.append(Glyph{ .empty = void{} });
                continue;
            }

            const contour_count = try reader.readInt(i16, .big);
            if (contour_count < 0) {
                const glyph = try CompoundGlyph.parse(allocator, reader);
                try glyphs.append(Glyph{ .compound = glyph });
            } else {
                const glyph = try SimpleGlyph.parse(allocator, reader, @intCast(contour_count));
                try glyphs.append(Glyph{ .simple = glyph });
            }
        }

        return GlyfTable{ .glyphs = try glyphs.toOwnedSlice() };
    }

    pub fn deinit(self: GlyfTable, allocator: std.mem.Allocator) void {
        for (self.glyphs) |entry| {
            switch (entry) {
                .simple => |glyph| glyph.deinit(allocator),
                .compound => |glyph| glyph.deinit(allocator),
                .empty => {},
            }
        }
        allocator.free(self.glyphs);
    }
};
