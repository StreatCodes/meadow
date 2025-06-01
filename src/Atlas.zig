const std = @import("std");
const sdl = @import("sdl3");
const Font = @import("./ttf/Font.zig");
const glyf = @import("./ttf/tables/glyf.zig");

/// Draws a line between two points - vibe coded from claude
fn draw_line(surface: sdl.surface.Surface, from: sdl.rect.IPoint, to: sdl.rect.IPoint) !void {
    const dx: i16 = @intCast(@abs(to.x - from.x));
    const dy: i16 = @intCast(@abs(to.y - from.y));
    const sx: i16 = if (from.x < to.x) 1 else -1;
    const sy: i16 = if (from.y < to.y) 1 else -1;
    var err = dx - dy;

    var x = from.x;
    var y = from.y;

    while (true) {
        try surface.writePixel(@intCast(x), @intCast(y), sdl.pixels.Color{ .r = 255, .g = 255, .b = 255, .a = 255 });

        if (x == to.x and y == to.y) break;

        const e2 = 2 * err;
        if (e2 > -dy) {
            err -= dy;
            x += sx;
        }
        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
}

/// Draws a bezier curve - vibe coded from claude
fn draw_curve(surface: sdl.surface.Surface, start: sdl.rect.IPoint, control: sdl.rect.IPoint, end: sdl.rect.IPoint) !void {
    // Calculate approximate curve length to determine step count
    const d1x = control.x - start.x;
    const d1y = control.y - start.y;
    const d2x = end.x - control.x;
    const d2y = end.y - control.y;
    const approx_length = @sqrt(@as(f32, @floatFromInt(d1x * d1x + d1y * d1y))) +
        @sqrt(@as(f32, @floatFromInt(d2x * d2x + d2y * d2y)));
    const steps = @max(10, @min(100, @as(usize, @intFromFloat(approx_length / 2))));

    for (0..steps) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps - 1));
        const inv_t = 1.0 - t;

        // Quadratic Bézier formula: B(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
        const x = inv_t * inv_t * @as(f32, @floatFromInt(start.x)) +
            2.0 * inv_t * t * @as(f32, @floatFromInt(control.x)) +
            t * t * @as(f32, @floatFromInt(end.x));
        const y = inv_t * inv_t * @as(f32, @floatFromInt(start.y)) +
            2.0 * inv_t * t * @as(f32, @floatFromInt(control.y)) +
            t * t * @as(f32, @floatFromInt(end.y));

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
    x: i16,
    y: i16,
    on_curve: bool,
};

/// Normalize all the points on a contour to a format that's easier to consume.
/// Additionally, this helps with some of the subtleties of TTF fonts:
/// - Ensure first point is on_curve
/// - Ensure last point is on_curve and matches the first point
/// - Expand consecutive off_curve points so that it has a real on_curve point between them
fn normalize(allocator: std.mem.Allocator, offset: GlyphOffset, flags: []glyf.GlyphFlag, x_coords: []i16, y_coords: []i16) ![]GlyphPoint {
    var points = try std.ArrayList(GlyphPoint).initCapacity(allocator, flags.len);

    //Handle instance where the first value is a curve
    if (flags[0].on_curve == 0) {
        const last_idx = flags.len - 1;
        const last_flag = flags[last_idx];
        if (last_flag.on_curve == 1) {
            try points.append(GlyphPoint{
                .x = x_coords[last_idx] + offset.x,
                .y = y_coords[last_idx] + offset.y,
                .on_curve = true,
            });
        } else {
            //Create implicit midpoint
            const x = midpoint_i16(x_coords[0], x_coords[last_idx]);
            const y = midpoint_i16(y_coords[0], y_coords[last_idx]);
            try points.append(GlyphPoint{
                .x = x + offset.x,
                .y = y + offset.y,
                .on_curve = true,
            });
        }
    }

    //Add all the points including any implicit points between curves
    for (0..flags.len) |i| {
        const on_curve = flags[i].on_curve == 1;
        try points.append(GlyphPoint{
            .x = x_coords[i] + offset.x,
            .y = y_coords[i] + offset.y,
            .on_curve = on_curve,
        });

        //Add implicit midpoint when two consecutive off_curve points
        if (!on_curve) {
            if (i == flags.len - 1) break;
            if (flags[i + 1].on_curve == 0) {
                const x = midpoint_i16(x_coords[i], x_coords[i + 1]);
                const y = midpoint_i16(y_coords[i], y_coords[i + 1]);
                try points.append(GlyphPoint{
                    .x = x + offset.x,
                    .y = y + offset.y,
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
    return points.toOwnedSlice();
}

fn render_contour(surface: sdl.surface.Surface, points: []GlyphPoint) !void {
    for (0..points.len - 1) |i| {
        const point = points[i];
        const next_point = points[i + 1];

        //Draw straight line
        if (point.on_curve and next_point.on_curve) {
            try draw_line(
                surface,
                sdl.rect.IPoint{ .x = point.x, .y = point.y },
                sdl.rect.IPoint{ .x = next_point.x, .y = next_point.y },
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
            try draw_curve(
                surface,
                sdl.rect.IPoint{ .x = prev_point.x, .y = prev_point.y },
                sdl.rect.IPoint{ .x = point.x, .y = point.y },
                sdl.rect.IPoint{ .x = next_point.x, .y = next_point.y },
            );
            continue;
        }

        //All scenarios should have been handled. The normalize function should have ensured this.
        std.debug.print("Unexpected point on_curve {any} ({d}, {d})\n", .{ point.on_curve, point.x, point.y });
        std.debug.print("Next point on_curve {any} ({d}, {d})\n", .{ next_point.on_curve, next_point.x, next_point.y });
        unreachable;
    }
}

//Shift the glyph so that it starts at 0,0. TTFs can start in the negative.
const GlyphOffset = struct {
    x: i16,
    y: i16,
};

/// Render a glyph to a new surface. It is the callers responsibility to destroy the returned surface.
pub fn render_gylph(allocator: std.mem.Allocator, _glyph: glyf.Glyph, size: u32) !sdl.surface.Surface {
    _ = size;
    const glyph = _glyph.simple; //TODO remove this eventually
    const offset = GlyphOffset{
        .x = -glyph.x_min,
        .y = -glyph.y_min,
    };
    const surface = try sdl.surface.Surface.init(@intCast(glyph.x_max + offset.x + 1), @intCast(glyph.y_max + offset.y + 1), sdl.pixels.Format.array_rgb_24);
    std.debug.print("Surface: {d} {d}\n", .{ surface.getWidth(), surface.getHeight() });

    var start: usize = 0;
    for (glyph.contour_end_points) |_end| {
        const end: usize = @intCast(_end);
        const flags = glyph.flags[start .. end + 1]; //Why is this + 1???
        const x_coords = glyph.x_coordinate[start .. end + 1];
        const y_coords = glyph.y_coordinate[start .. end + 1];

        const points = try normalize(allocator, offset, flags, x_coords, y_coords);
        defer allocator.free(points);

        //Flip Y axis so it matches SDL 0,0 being top left rather than TTF's bottom left
        for (0..points.len) |i| points[i].y = glyph.y_max + offset.y - points[i].y;

        std.debug.print("Rendering contour {d}-{d}\n", .{ start, end });
        try render_contour(surface, points);
        start = end + 1;
    }

    return surface;
}
