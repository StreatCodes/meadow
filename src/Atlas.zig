const std = @import("std");
const sdl = @import("sdl3");
const Font = @import("./ttf/Font.zig");
const glyf = @import("./ttf/tables/glyf.zig");
const line = @import("./text_renderer/line.zig");

/// Draws a bezier curve - vibe coded from claude
fn drawCurve(surface: sdl.surface.Surface, start: sdl.rect.FPoint, control: sdl.rect.FPoint, end: sdl.rect.FPoint) !void {
    // Calculate approximate curve length to determine step count
    const d1x = control.x - start.x;
    const d1y = control.y - start.y;
    const d2x = end.x - control.x;
    const d2y = end.y - control.y;
    const approx_length = @sqrt(d1x * d1x + d1y * d1y) + @sqrt(d2x * d2x + d2y * d2y);
    const steps = @max(10, @min(1000, @as(usize, @intFromFloat(approx_length * 2))));

    for (0..steps) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps - 1));
        const inv_t = 1.0 - t;

        // Quadratic Bézier formula: B(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
        const x = inv_t * inv_t * start.x +
            2.0 * inv_t * t * control.x +
            t * t * end.x;
        const y = inv_t * inv_t * start.y +
            2.0 * inv_t * t * control.y +
            t * t * end.y;

        try surface.writePixel(
            @intCast(@as(i16, @intFromFloat(x))),
            @intCast(@as(i16, @intFromFloat(y))),
            sdl.pixels.Color{ .r = 255, .g = 255, .b = 255, .a = 255 },
        );
    }
}

fn midpoint_i16(a: i16, b: i16) i16 {
    return @intCast(@divTrunc((@as(i32, a) + @as(i32, b)), 2));
}

const GlyphPoint = struct {
    x: f32,
    y: f32,
    on_curve: bool,
};

/// Normalize all the points on a contour to a format that's easier to consume.
/// Additionally, this helps with some of the subtleties of TTF fonts:
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

fn renderContour(surface: sdl.surface.Surface, points: []GlyphPoint) !void {
    for (0..points.len - 1) |i| {
        const point = points[i];
        const next_point = points[i + 1];

        //Draw straight line
        if (point.on_curve and next_point.on_curve) {
            try line.drawLine(
                surface,
                sdl.rect.FPoint{ .x = point.x, .y = point.y },
                sdl.rect.FPoint{ .x = next_point.x, .y = next_point.y },
                1.0,
            );
            continue;
        }

        //This curve will get handled in the next iteration
        if (point.on_curve and !next_point.on_curve) {
            continue;
        }

        //Draw curve
        if (!point.on_curve and next_point.on_curve) {
            const prev_point = points[i - 1];
            try drawCurve(
                surface,
                sdl.rect.FPoint{ .x = prev_point.x, .y = prev_point.y },
                sdl.rect.FPoint{ .x = point.x, .y = point.y },
                sdl.rect.FPoint{ .x = next_point.x, .y = next_point.y },
            );
            continue;
        }

        //All scenarios should have been handled. The normalize function should have ensured this.
        std.debug.print("Unexpected point on_curve {any} ({d}, {d})\n", .{ point.on_curve, point.x, point.y });
        std.debug.print("Next point on_curve {any} ({d}, {d})\n", .{ next_point.on_curve, next_point.x, next_point.y });
        unreachable;
    }
}

const GlyphProperties = struct {
    offset_x: i16, //Shift the x so it starts at 0
    offset_y: i16, //Shift the y so it starts at 0
    max_y: f32,
    scale: f32,
};

/// Render a glyph to a new surface. It is the callers responsibility to destroy the returned surface.
pub fn renderGylph(allocator: std.mem.Allocator, _glyph: glyf.Glyph, units_per_em: u116, point_size: f32) !sdl.surface.Surface {
    const scale = point_size / @as(f32, @floatFromInt(units_per_em));
    std.debug.print("Rendering glyph {d}pt (scale {d})\n", .{ point_size, scale });

    const glyph = _glyph.simple; //TODO remove this eventually
    const glyph_properties = GlyphProperties{
        .offset_x = -glyph.x_min,
        .offset_y = -glyph.y_min,
        .max_y = @floatFromInt(glyph.y_max + -glyph.y_min),
        .scale = scale,
    };
    const surface = try sdl.surface.Surface.init(
        @intCast(glyph.x_max + glyph_properties.offset_x + 1),
        @intCast(glyph.y_max + glyph_properties.offset_y + 1),
        sdl.pixels.Format.array_rgb_24,
    );
    std.debug.print("Surface: {d} {d}\n", .{ surface.getWidth(), surface.getHeight() });

    var start: usize = 0;
    for (glyph.contour_end_points) |_end| {
        const end: usize = @intCast(_end);
        const flags = glyph.flags[start .. end + 1]; //Why is this + 1???
        const x_coords = glyph.x_coordinate[start .. end + 1];
        const y_coords = glyph.y_coordinate[start .. end + 1];

        const points = try normalize(allocator, glyph_properties, flags, x_coords, y_coords);
        defer allocator.free(points);

        std.debug.print("Rendering contour {d}-{d}\n", .{ start, end });
        try renderContour(surface, points);
        start = end + 1;
    }

    return surface;
}
