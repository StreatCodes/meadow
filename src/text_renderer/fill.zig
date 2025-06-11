const std = @import("std");
const sdl = @import("sdl3");

const FPoint = sdl.rect.FPoint;

pub fn fillOutline(surface: sdl.surface.Surface, contours: [][]FPoint) !void {
    const width = surface.getWidth();
    const height = surface.getHeight();

    for (0..height) |y| {
        for (0..width) |x| {
            const pixel = FPoint{ .x = @floatFromInt(x), .y = @floatFromInt(y) };

            //Handle the scenario where one or more contours pass through the pixel
            const brightness = try contourIntersectsPixel(pixel, contours);
            if (brightness > 0) {
                const color: u8 = @intFromFloat(@ceil(255 * brightness));
                try surface.writePixel(x, y, sdl.pixels.Color{ .r = color, .g = color, .b = color, .a = 255 });
                continue;
            }

            //No contours intersect this pixel, color white if inside outline.
            const in_outline = pointInOutline(contours, pixel);
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

fn contourIntersectsPixel(pixel: FPoint, contours: [][]FPoint) !f32 {
    const pixel_tr = FPoint{ .x = pixel.x + 1.0, .y = pixel.y };
    const pixel_bl = FPoint{ .x = pixel.x, .y = pixel.y + 1.0 };
    const pixel_br = FPoint{ .x = pixel.x + 1.0, .y = pixel.y + 1.0 };

    var buffer: [8192]u8 = undefined; //TODO there is an issue, perhaps with the starting point looping the entire contour
    var _allocator = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = _allocator.allocator();
    var intersect_points = std.ArrayList(FPoint).init(allocator);

    //Find the points within the pixel and where they intersected the edge of the pixel
    outer: for (contours) |points| {
        var i: isize = 0;
        while (i < points.len - 1) : (i += 1) {
            const line_from = points[@intCast(i)];
            const line_to = points[@intCast(i + 1)];

            //Skip if the line starts inside point
            if (intersect_points.items.len == 0 and line_from.x >= pixel.x and line_from.x <= pixel.x + 1 and line_from.y >= pixel.y and line_from.y <= pixel.y + 1) {
                continue;
            }

            //Add any point that comes after the first intersect
            if (intersect_points.items.len != 0) {
                try intersect_points.append(line_from);
            }

            //Check for intersect, if it's the second then it's exiting the pixel; so break
            const top_intersects = lineIntersectsLine(pixel, pixel_tr, line_from, line_to);
            if (top_intersects) |intersect| {
                try intersect_points.append(intersect);
                if (intersect_points.items.len > 1) break :outer;
            }
            const right_intersects = lineIntersectsLine(pixel_tr, pixel_br, line_from, line_to);
            if (right_intersects) |intersect| {
                try intersect_points.append(intersect);
                if (intersect_points.items.len > 1) break :outer;
            }
            const bottom_intersects = lineIntersectsLine(pixel_bl, pixel_br, line_from, line_to);
            if (bottom_intersects) |intersect| {
                try intersect_points.append(intersect);
                if (intersect_points.items.len > 1) break :outer;
            }
            const left_intersects = lineIntersectsLine(pixel_bl, pixel, line_from, line_to);
            if (left_intersects) |intersect| {
                try intersect_points.append(intersect);
                if (intersect_points.items.len > 1) break :outer;
            }

            //Edge case where last element intersects, we need to loop back to the beginning to find exit intersect
            if (i == points.len - 2 and intersect_points.items.len > 0) {
                std.debug.print("Last intersect, looping\n", .{});
                i = -1;
            }
        }
    }

    //TODO not sure if we should just do what's outside the function here
    if (intersect_points.items.len == 0) return 0;
    if (intersect_points.items.len == 1) unreachable;

    // Normalize the points between 0 - 1
    for (intersect_points.items) |*point| {
        point.*.x -= pixel.x;
        point.*.y -= pixel.y;
    }

    //The line has split the pixel in two, find the two shapes created from the split
    try fillIntersectCorners(&intersect_points);
    const area = polygonArea(intersect_points.items);

    //TODO UNNORMALIZE this is DUMB; do one or the other not both
    for (intersect_points.items) |*point| {
        point.*.x += pixel.x;
        point.*.y += pixel.y;
    }

    const shape_center = polygonCenter(intersect_points.items);
    const should_fill = pointInOutline(contours, shape_center);

    if (should_fill) {
        return area;
    }

    return 1.0 - area;
}

const corners = [_]FPoint{
    .{ .x = 0, .y = 0 }, // bottom-left
    .{ .x = 1, .y = 0 }, // bottom-right
    .{ .x = 1, .y = 1 }, // top-right
    .{ .x = 0, .y = 1 }, // top-left
};

fn findEdgeIndex(point: FPoint) usize {
    if (point.y == 0) return 0; // bottom
    if (point.x == 1) return 1; // right
    if (point.y == 1) return 2; // top
    if (point.x == 0) return 3; // left
    unreachable;
}

fn fillIntersectCorners(points: *std.ArrayList(FPoint)) !void {
    const entry_edge = findEdgeIndex(points.items[0]);
    const exit_edge = findEdgeIndex(points.items[points.items.len - 1]);

    // If entry and exit are on the same edge, no corners need to be added
    if (entry_edge == exit_edge) return;

    var current_edge = exit_edge;
    while (true) {
        // Move to next edge clockwise
        current_edge = (current_edge + 1) % 4;

        // Add the corner at this edge
        try points.append(corners[current_edge]);

        // Stop when we reach the exit edge
        if (current_edge == entry_edge) break;
    }
}

fn polygonCenter(points: []FPoint) FPoint {
    var sum_x: f32 = 0;
    var sum_y: f32 = 0;

    for (points) |point| {
        sum_x += point.x;
        sum_y += point.y;
    }

    return FPoint{
        .x = sum_x / @as(f32, @floatFromInt(points.len)),
        .y = sum_y / @as(f32, @floatFromInt(points.len)),
    };
}

fn polygonArea(points: []FPoint) f32 {
    var sum: f32 = 0;
    for (0..points.len - 1) |i| {
        const point = points[i];
        const next_point = points[i + 1];
        sum += (point.x * next_point.y) - (next_point.x * point.y);
    }
    return @abs(sum) / 2;
}

test "polygonArea finds the area of the given points" {
    var points = [_]FPoint{
        .{ .x = 0, .y = 0 },
        .{ .x = 4, .y = 0 },
        .{ .x = 4, .y = 3 },
        .{ .x = 0, .y = 3 },
    };
    const area = polygonArea(&points);

    std.debug.assert(area == 12);
}

/// Determines if two lines intersect, if so return the intersect point
fn lineIntersectsLine(a_from: FPoint, a_to: FPoint, b_from: FPoint, b_to: FPoint) ?FPoint {
    // Calculate direction vectors
    const a_dx = a_to.x - a_from.x;
    const a_dy = a_to.y - a_from.y;
    const b_dx = b_to.x - b_from.x;
    const b_dy = b_to.y - b_from.y;

    // Calculate the denominator for the intersection formula
    const denominator = a_dx * b_dy - a_dy * b_dx;

    // Check if lines are parallel or collinear (denominator is 0)
    if (@abs(denominator) < 1e-10) {
        // Lines are parallel or on top of each other - no intersection
        return null;
    }

    // Calculate the difference in starting points
    const dx = b_from.x - a_from.x;
    const dy = b_from.y - a_from.y;

    // Calculate parameters t and u for both lines
    const t = (dx * b_dy - dy * b_dx) / denominator;
    const u = (dx * a_dy - dy * a_dx) / denominator;

    // Check if intersection point lies within both line segments
    if (t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0) {
        // Calculate intersection point
        const intersection_x = a_from.x + t * a_dx;
        const intersection_y = a_from.y + t * a_dy;

        return FPoint{ .x = intersection_x, .y = intersection_y };
    }

    // Intersection point is outside one or both line segments
    return null;
}

/// Determines if a line was intersected from a ray emitted horizontally to the right
fn rayIntersects(ray_origin: FPoint, line_from: FPoint, line_to: FPoint) bool {
    const min_y = @min(line_from.y, line_to.y);
    const max_y = @max(line_from.y, line_to.y);

    // Ray doesn't cross the segment's Y range
    if (ray_origin.y < min_y or ray_origin.y >= max_y) return false;

    // Calculate X intersection point
    const t = (ray_origin.y - line_from.y) / (line_to.y - line_from.y);
    const intersection_x = line_from.x + t * (line_to.x - line_from.x);

    // Ray goes right, so intersection must be to the right of ray start
    return intersection_x >= ray_origin.x;
}
