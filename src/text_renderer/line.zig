const std = @import("std");
const sdl = @import("sdl3");

// Main function to draw an anti-aliased line
pub fn drawLine(surface: sdl.surface.Surface, from: sdl.rect.FPoint, to: sdl.rect.FPoint, line_width: f32) !void {
    const start_x: usize = @intFromFloat(@floor(@min(from.x, to.x)));
    const start_y: usize = @intFromFloat(@floor(@min(from.y, to.y)));
    const end_x: usize = @intFromFloat(@ceil(@max(from.x, to.x)));
    const end_y: usize = @intFromFloat(@ceil(@max(from.y, to.y)));

    // Process each pixel in the bounding box
    for (start_y..end_y + 1) |y| {
        for (start_x..end_x + 1) |x| {
            // Calculate coverage for this pixel
            const coverage = calculatePixelCoverage(@floatFromInt(x), @floatFromInt(y), from, to, line_width);

            if (coverage > 0) {
                const int_coverage: u8 = @intFromFloat(@floor(255 * coverage));
                const pixel = try surface.readPixel(x, y);
                if (pixel.r < int_coverage) {
                    try surface.writePixel(x, y, sdl.pixels.Color{ .r = int_coverage, .g = int_coverage, .b = int_coverage, .a = 255 });
                }
            }
        }
    }
}

// Calculate how much of a pixel is covered by the line
fn calculatePixelCoverage(pixel_x: f32, pixel_y: f32, from: sdl.rect.FPoint, to: sdl.rect.FPoint, line_width: f32) f32 {
    // Get pixel center
    const px = pixel_x + 0.5;
    const py = pixel_y + 0.5;

    // Calculate distance from pixel center to line segment
    const distance = pointToLineSegmentDistance(px, py, from, to);

    // Convert distance to coverage (0 = no coverage, 1 = full coverage)
    const halfWidth = line_width * 0.5;

    if (distance > halfWidth + 0.5) {
        return 0; // Too far from line
    }

    // Linear falloff from line center to edge
    // You can experiment with different falloff functions here
    const coverage = @max(0, 1 - (distance - halfWidth) / 0.5);
    return @min(1, coverage);
}

// Calculate perpendicular distance from point to line segment
fn pointToLineSegmentDistance(px: f32, py: f32, from: sdl.rect.FPoint, to: sdl.rect.FPoint) f32 {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const length_squared = dx * dx + dy * dy;

    if (length_squared == 0) {
        // Degenerate case: line is a point
        return @sqrt((px - from.x) * (px - from.x) + (py - from.y) * (py - from.y));
    }

    // Calculate parameter t for closest point on line segment
    // t = 0 means closest point is at (from.x, from.y)
    // t = 1 means closest point is at (to.x, to.y)
    var t = ((px - from.x) * dx + (py - from.y) * dy) / length_squared;

    // Clamp t to [0, 1] to stay within line segment
    t = @max(0, @min(1, t));

    // Find closest point on line segment
    const closest_x = from.x + t * dx;
    const closest_y = from.y + t * dy;

    // Return distance from point to closest point on segment
    const dist_x = px - closest_x;
    const dist_y = py - closest_y;
    return @sqrt(dist_x * dist_x + dist_y * dist_y);
}

/// Draws a bezier curve - vibe coded from claude
pub fn drawBezier(surface: sdl.surface.Surface, start: sdl.rect.FPoint, control: sdl.rect.FPoint, end: sdl.rect.FPoint) !void {
    // Calculate approximate curve length to determine step count
    const d1x = control.x - start.x;
    const d1y = control.y - start.y;
    const d2x = end.x - control.x;
    const d2y = end.y - control.y;
    const approx_length = @sqrt(d1x * d1x + d1y * d1y) + @sqrt(d2x * d2x + d2y * d2y);
    const steps = @max(10, @min(1000, @as(usize, @intFromFloat(approx_length))));

    var points: [1000]sdl.rect.FPoint = undefined;

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

        points[i] = sdl.rect.FPoint{ .x = x, .y = y };
    }

    for (0..steps - 1) |i| {
        try drawLine(surface, points[i], points[i + 1], 1.0);
    }
}
