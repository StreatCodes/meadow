const std = @import("std");
const sdl = @import("sdl3");

const FPoint = sdl.rect.FPoint;

pub fn fillOutline(surface: sdl.surface.Surface, contours: [][]FPoint) !void {
    const width = surface.getWidth();
    const height = surface.getHeight();

    for (0..height) |y| {
        for (0..width) |x| {
            const point = FPoint{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
            const in_outline = pointInOutline(contours, point);
            if (in_outline) {
                try surface.writePixel(x, y, sdl.pixels.Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
            }
        }
    }
}

/// Checks if the given x,y coordinate is inside an outline using the
/// Winding number algorithm.
fn pointInOutline(contours: [][]FPoint, point: FPoint) bool {
    var count: i32 = 0;
    for (contours) |points| {
        for (0..points.len - 1) |i| {
            const line_from = points[i];
            const line_to = points[i + 1];

            const intersects = rayIntersects(point, line_from, line_to);
            if (intersects) {
                if (line_from.y > line_to.y) {
                    count += 1;
                } else {
                    count -= 1;
                }
            }
        }
    }
    return count != 0;
}

/// Determines if a line was intersected from a ray emitted horizontally to the right
fn rayIntersects(ray_origin: FPoint, line_from: FPoint, line_to: FPoint) bool {
    // Simple horizontal ray from (rayStartX, rayY) going right
    const min_y = @min(line_from.y, line_to.y);
    const max_y = @max(line_from.y, line_to.y);

    // Ray doesn't cross the segment's Y range
    if (ray_origin.y < min_y or ray_origin.y > max_y) return false;

    // Calculate X intersection point
    const t = (ray_origin.y - line_from.y) / (line_to.y - line_from.y);
    const intersection_x = line_from.x + t * (line_to.x - line_from.x);

    // Ray goes right, so intersection must be to the right of ray start
    return intersection_x >= ray_origin.x;
}
