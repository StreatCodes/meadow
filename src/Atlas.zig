const std = @import("std");
const sdl = @import("sdl3");
const Font = @import("./ttf/Font.zig");
const Glyph = @import("./ttf/tables/glyf.zig").Glyph;

pub fn render_gylph(_glyph: Glyph) !sdl.surface.Surface {
    const glyph = _glyph.simple; //TODO remove this eventually
    const surface = try sdl.surface.Surface.init(1200, 1200, sdl.pixels.Format.array_rgb_24);

    std.debug.print("Rendering glyph with {d} points\n", .{glyph.flags.len});
    for (glyph.flags, 0..) |flag, i| {
        const x = glyph.x_coordinate[i];
        const y = glyph.y_coordinate[i];
        _ = flag;
        const x_adder: i16 = @intCast(@abs(glyph.x_min) + 100);
        const y_adder: i16 = @intCast(@abs(glyph.y_min) + 100);

        const x_pos: usize = @intCast(@divTrunc(x + x_adder, 2));
        const y_pos: usize = @intCast(@divTrunc(y + y_adder, 2));

        // std.debug.print("Minimuns {d} {d}\n", .{ glyph.x_min, glyph.y_min });
        std.debug.print("Writing pixel {d} {d}\n", .{ x + x_adder, y + y_adder });
        // std.debug.print("Writing pixel {d} {d}\n", .{ x, y });

        try surface.writePixel(x_pos, y_pos, sdl.pixels.Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        try surface.writePixel(x_pos + 1, y_pos, sdl.pixels.Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        try surface.writePixel(x_pos, y_pos + 1, sdl.pixels.Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        try surface.writePixel(x_pos + 1, y_pos + 1, sdl.pixels.Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
    }

    return surface;
}
