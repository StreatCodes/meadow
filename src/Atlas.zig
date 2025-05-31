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

/// Normalize the glyph points to a format that's easier to consume.
/// Additionally, this helps with some of the subtleties of TTF fonts:
/// - Ensure first point is on_curve
/// - Ensure last point is on_curve and matches the first point
/// - Expand consecutive off_curve points so that it has a real on_curve point between them
fn normalize(allocator: std.mem.Allocator, simple_glyph: glyf.SimpleGlyph) ![]GlyphPoint {
    var points = try std.ArrayList(GlyphPoint).initCapacity(allocator, simple_glyph.flags.len);

    //Handle instance where the first value is a curve
    if (simple_glyph.flags[0].on_curve == 0) {
        const last_idx = simple_glyph.flags.len - 1;
        const last_flag = simple_glyph.flags[last_idx];
        if (last_flag.on_curve == 1) {
            try points.append(GlyphPoint{
                .x = simple_glyph.x_coordinate[last_idx],
                .y = simple_glyph.y_coordinate[last_idx],
                .on_curve = true,
            });
        } else {
            //Create implicit midpoint
            const x = midpoint_i16(simple_glyph.x_coordinate[0], simple_glyph.x_coordinate[last_idx]);
            const y = midpoint_i16(simple_glyph.y_coordinate[0], simple_glyph.y_coordinate[last_idx]);
            try points.append(GlyphPoint{ .x = x, .y = y, .on_curve = true });
        }
    }

    //Add all the points including any implicit points between curves
    for (0..simple_glyph.flags.len) |i| {
        const on_curve = simple_glyph.flags[i].on_curve == 1;
        try points.append(GlyphPoint{
            .x = simple_glyph.x_coordinate[i],
            .y = simple_glyph.y_coordinate[i],
            .on_curve = on_curve,
        });

        //Add implicit midpoint when two consecutive off_curve points
        if (!on_curve) {
            const is_last = i == simple_glyph.flags.len - 1;
            if (is_last) {
                try points.append(points.items[0]);
                break;
            }
            //This and the following point are off curve. This is shorthand for a point in between. Add the implicit point.
            if (simple_glyph.flags[i + 1].on_curve == 0) {
                const x = midpoint_i16(simple_glyph.x_coordinate[i], simple_glyph.x_coordinate[i + 1]);
                const y = midpoint_i16(simple_glyph.y_coordinate[i], simple_glyph.y_coordinate[i + 1]);
                try points.append(GlyphPoint{ .x = x, .y = y, .on_curve = true });
            }
        }
    }

    return points.toOwnedSlice();
}

/// Render a glyph to a new surface. It is the callers responsibility to destroy the returned surface.
pub fn render_gylph(allocator: std.mem.Allocator, _glyph: glyf.Glyph) !sdl.surface.Surface {
    const glyph = _glyph.simple; //TODO remove this eventually
    const surface = try sdl.surface.Surface.init(3000, 3000, sdl.pixels.Format.array_rgb_24);

    const points = try normalize(allocator, glyph);
    defer allocator.free(points);

    std.debug.print("Rendering glyph with {d} points\n", .{points.len});
    for (0..points.len - 1) |i| {
        const point = points[i];
        const next_point = points[i + 1];

        //Draw straight line
        if (point.on_curve and next_point.on_curve) {
            try draw_line(
                surface,
                sdl.rect.IPoint{ .x = @intCast(@divTrunc(point.x + 100, 2)), .y = @intCast(@divTrunc(point.y + 100, 2)) },
                sdl.rect.IPoint{ .x = @intCast(@divTrunc(next_point.x + 100, 2)), .y = @intCast(@divTrunc(next_point.y + 100, 2)) },
            );
            continue;
        }

        //This curve will get handled in the next iteration
        if (point.on_curve and !next_point.on_curve) {
            continue;
        }

        //Draw curve
        if (!point.on_curve and next_point.on_curve) {
            //Draw curve
            const prev_point = points[i - 1];
            try draw_curve(
                surface,
                sdl.rect.IPoint{ .x = @intCast(@divTrunc(prev_point.x + 100, 2)), .y = @intCast(@divTrunc(prev_point.y + 100, 2)) },
                sdl.rect.IPoint{ .x = @intCast(@divTrunc(point.x + 100, 2)), .y = @intCast(@divTrunc(point.y + 100, 2)) },
                sdl.rect.IPoint{ .x = @intCast(@divTrunc(next_point.x + 100, 2)), .y = @intCast(@divTrunc(next_point.y + 100, 2)) },
            );
            continue;
        }

        //All scenarios should have been handled. The normalize function should have ensured this.
        std.debug.print("Unexpected point on_curve {any} ({d}, {d})\n", .{ point.on_curve, point.x, point.y });
        std.debug.print("Next point on_curve {any} ({d}, {d})\n", .{ next_point.on_curve, next_point.x, next_point.y });
        unreachable;
    }

    return surface;
}
