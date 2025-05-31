const std = @import("std");
const Font = @import("./ttf/Font.zig");
const sdl = @import("sdl3");
const Atlas = @import("./Atlas.zig");

const SCREEN_WIDTH = 1920;
const SCREEN_HEIGHT = 1080;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    //Get args
    const args = std.os.argv;
    if (args.len < 1) {
        std.debug.print("Show help\n", .{});
    }

    //Read file
    const font_path = args[1];
    std.debug.print("Opening file {s}\n", .{font_path});
    var font_file = try std.fs.openFileAbsoluteZ(font_path, .{});
    defer font_file.close();

    //Parse font
    const reader = font_file.reader().any();
    const font = try Font.parse(allocator, reader);
    defer font.deinit(allocator);

    defer sdl.init.shutdown();

    const init_flags = sdl.init.Flags{ .video = true };
    try sdl.init.init(init_flags);
    defer sdl.init.quit(init_flags);

    const window = try sdl.video.Window.init("Meadow", SCREEN_WIDTH, SCREEN_HEIGHT, .{});
    defer window.deinit();

    const surface = try window.getSurface();
    try surface.fillRect(null, surface.mapRgb(50, 50, 50));

    const glyph = font.glyf_table.glyphs[9];
    const glyph_surface = try Atlas.render_gylph(allocator, glyph);
    defer glyph_surface.deinit();
    try glyph_surface.blit(null, surface, null);

    try window.updateSurface();
    while (true) {
        switch ((try sdl.events.wait(true)).?) {
            .quit => break,
            .terminating => break,
            else => {},
        }
    }
}
