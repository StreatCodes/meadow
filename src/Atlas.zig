const std = @import("std");
const sdl = @import("sdl3");
const Font = @import("./ttf/Font.zig");
const glyf = @import("./ttf/tables/glyf.zig");
const fill = @import("./text_renderer/fill.zig");

const FPoint = sdl.rect.FPoint;
const Atlas = @This();

allocator: std.mem.Allocator,
font: Font,

pub fn init(allocator: std.mem.Allocator, font: Font) Atlas {
    return Atlas{
        .allocator = allocator,
        .font = font,
    };
}

pub fn deinit(self: Atlas) void {
    _ = self;
}

fn midpoint_i16(a: i16, b: i16) i16 {
    return @intCast(@divTrunc((@as(i32, a) + @as(i32, b)), 2));
}

// A temporary format that's easier to consume
const GlyphPoint = struct {
    x: f32,
    y: f32,
    on_curve: bool,
};

/// Normalize all points on a contour from their compressed format to
/// a fully expanded list of points, including converting the curves to
/// a list of lines.
/// Additionally, this resolves some of the subtleties of TTF fonts:
/// - Ensure first point is on_curve
/// - Ensure last point is on_curve and matches the first point
/// - Expand consecutive off_curve points so that it has a real on_curve point between them
fn normalize(allocator: std.mem.Allocator, glyph_properties: GlyphProperties, flags: []glyf.GlyphFlag, x_coords: []i16, y_coords: []i16) ![]GlyphPoint {
    var points = try std.ArrayList(GlyphPoint).initCapacity(allocator, flags.len);

    //Handle instance where the first value is a curve
    if (flags[0].on_curve == 0) {
        const last_idx = flags.len - 1;
        const last_flag = flags[last_idx];
        if (last_flag.on_curve == 1) {
            try points.append(GlyphPoint{
                .x = @floatFromInt(x_coords[last_idx] + glyph_properties.offset_x),
                .y = @floatFromInt(y_coords[last_idx] + glyph_properties.offset_y),
                .on_curve = true,
            });
        } else {
            //Create implicit midpoint
            const x = midpoint_i16(x_coords[0], x_coords[last_idx]);
            const y = midpoint_i16(y_coords[0], y_coords[last_idx]);
            try points.append(GlyphPoint{
                .x = @floatFromInt(x + glyph_properties.offset_x),
                .y = @floatFromInt(y + glyph_properties.offset_y),
                .on_curve = true,
            });
        }
    }

    //Add all the points including any implicit points between curves
    for (0..flags.len) |i| {
        const on_curve = flags[i].on_curve == 1;
        try points.append(GlyphPoint{
            .x = @floatFromInt(x_coords[i] + glyph_properties.offset_x),
            .y = @floatFromInt(y_coords[i] + glyph_properties.offset_y),
            .on_curve = on_curve,
        });

        //Add implicit midpoint when two consecutive off_curve points
        if (!on_curve) {
            if (i == flags.len - 1) break;
            if (flags[i + 1].on_curve == 0) {
                const x = midpoint_i16(x_coords[i], x_coords[i + 1]);
                const y = midpoint_i16(y_coords[i], y_coords[i + 1]);
                try points.append(GlyphPoint{
                    .x = @floatFromInt(x + glyph_properties.offset_x),
                    .y = @floatFromInt(y + glyph_properties.offset_y),
                    .on_curve = true,
                });
            }
        }
    }

    //Append the first point to the end so the contour closes
    try points.append(GlyphPoint{
        .x = points.items[0].x,
        .y = points.items[0].y,
        .on_curve = true,
    });

    //Flip Y axis so it matches SDL 0,0 being top left rather than TTF's bottom left and scale the glyph
    for (points.items) |*point| {
        point.*.y = glyph_properties.max_y - point.*.y;
        point.*.x *= glyph_properties.scale;
        point.*.y *= glyph_properties.scale;
    }

    return points.toOwnedSlice();
}

pub fn expandBezier(points: *Points, start: FPoint, control: FPoint, end: FPoint) !void {
    // Calculate approximate curve length to determine step count
    // const d1x = control.x - start.x;
    // const d1y = control.y - start.y;
    // const d2x = end.x - control.x;
    // const d2y = end.y - control.y;
    // const approx_length = @sqrt(d1x * d1x + d1y * d1y) + @sqrt(d2x * d2x + d2y * d2y);
    // const steps = @max(10, @min(1000, @as(usize, @intFromFloat(approx_length * 2))));
    const steps: usize = 20; // this should be the absolute max iterations, i can barely percieve 10 at 800pt

    //Do not add the last step, it will get added later
    for (0..steps - 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps - 1));
        const inv_t = 1.0 - t;

        // Quadratic Bézier formula: B(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
        const x = inv_t * inv_t * start.x +
            2.0 * inv_t * t * control.x +
            t * t * end.x;
        const y = inv_t * inv_t * start.y +
            2.0 * inv_t * t * control.y +
            t * t * end.y;

        try points.append(FPoint{ .x = x, .y = y });
    }
}

const Points = std.ArrayList(FPoint);
fn contourToLinePoints(allocator: std.mem.Allocator, glyph_points: []GlyphPoint) ![]FPoint {
    var line_points = Points.init(allocator);

    for (0..glyph_points.len - 1) |i| {
        const point = glyph_points[i];
        const next_point = glyph_points[i + 1];

        //Draw straight line
        if (point.on_curve and next_point.on_curve) {
            try line_points.append(FPoint{ .x = point.x, .y = point.y });
            continue;
        }

        //This curve will get handled in the next iteration
        if (point.on_curve and !next_point.on_curve) {
            continue;
        }

        //Draw curve
        if (!point.on_curve and next_point.on_curve) {
            const prev_point = glyph_points[i - 1];
            try expandBezier(
                &line_points,
                FPoint{ .x = prev_point.x, .y = prev_point.y },
                FPoint{ .x = point.x, .y = point.y },
                FPoint{ .x = next_point.x, .y = next_point.y },
            );
            continue;
        }

        //All scenarios should have been handled. The normalize function should have ensured this.
        std.debug.print("Unexpected point on_curve {any} ({d}, {d})\n", .{ point.on_curve, point.x, point.y });
        std.debug.print("Next point on_curve {any} ({d}, {d})\n", .{ next_point.on_curve, next_point.x, next_point.y });
        unreachable;
    }

    //The final point for a straight needs to be added. Bezier is already handled
    const last_point = glyph_points[glyph_points.len - 1];
    if (last_point.on_curve) {
        try line_points.append(FPoint{ .x = last_point.x, .y = last_point.y });
    }

    return line_points.toOwnedSlice();
}

const GlyphProperties = struct {
    offset_x: i16, //Shift the x so it starts at 0
    offset_y: i16, //Shift the y so it starts at 0
    max_y: f32,
    scale: f32,
};

/// Render a glyph to a new surface. It is the callers responsibility to destroy the returned surface.
fn renderSimpleGylph(self: Atlas, glyph: glyf.SimpleGlyph, scale: f32) !sdl.surface.Surface {
    const glyph_properties = GlyphProperties{
        .offset_x = -glyph.x_min,
        .offset_y = -glyph.y_min,
        .max_y = @floatFromInt(glyph.y_max + -glyph.y_min),
        .scale = scale,
    };

    const max_x_offset: f32 = @floatFromInt(glyph.x_max + glyph_properties.offset_x);
    const max_y_offset: f32 = @floatFromInt(glyph.y_max + glyph_properties.offset_y);
    const surface = try sdl.surface.Surface.init(
        @intFromFloat(@ceil(max_x_offset * scale)),
        @intFromFloat(@ceil(max_y_offset * scale)),
        sdl.pixels.Format.array_rgba_32,
    );
    std.debug.print("Surface: {d} {d}\n", .{ surface.getWidth(), surface.getHeight() });

    const contours = try self.allocator.alloc([]FPoint, glyph.contour_end_points.len);
    defer {
        for (contours) |contour| self.allocator.free(contour);
        self.allocator.free(contours);
    }

    var start: usize = 0;
    for (glyph.contour_end_points, 0..) |_end, i| {
        const end: usize = @intCast(_end);
        const flags = glyph.flags[start .. end + 1];
        const x_coords = glyph.x_coordinate[start .. end + 1];
        const y_coords = glyph.y_coordinate[start .. end + 1];

        std.debug.print("Expanding contour {d}-{d}\n", .{ start, end });
        const _points = try normalize(self.allocator, glyph_properties, flags, x_coords, y_coords);
        defer self.allocator.free(_points);

        const points = try contourToLinePoints(self.allocator, _points);
        contours[i] = points;

        start = end + 1;
    }

    std.debug.print("Drawing {} contours\n", .{contours.len});
    for (contours) |contour| {
        std.debug.print("Contour points {d}\n", .{contour.len});
    }
    try fill.fillOutline(surface, contours);

    return surface;
}

pub fn render(self: Atlas, dest_surface: sdl.surface.Surface, dest_point: sdl.rect.IPoint, text: []const u8, point_size: f32) !void {
    const units_per_em = self.font.head_table.units_per_em;
    const scale = point_size / @as(f32, @floatFromInt(units_per_em));

    var cursor = dest_point.x;
    for (text) |c| {
        const _glyph = self.font.map_character(c);
        switch (_glyph) {
            .simple => |glyph| {
                std.debug.print("remove offset {d},{d}\n", .{ glyph.x_min, glyph.y_min });
                const surface = try self.renderSimpleGylph(glyph, scale);
                defer surface.deinit(); //TODO cache on the atlas

                const x_dest = cursor;
                const y_offset: i32 = @intFromFloat(@as(f32, @floatFromInt(glyph.y_min)) * scale);
                const y_dest = dest_point.y - @as(i32, @intCast(surface.getHeight())) - y_offset;

                try surface.blit(null, dest_surface, sdl.rect.IPoint{ .x = x_dest, .y = y_dest });
                cursor += @intCast(surface.getWidth());
            },
            .compound => unreachable,
            .empty => cursor += 18,
        }
    }
}
