const std = @import("std");
const Font = @import("./ttf/Font.zig");
const sdl = @import("sdl3");
const Atlas = @import("./Atlas.zig");

const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 720;

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

    const atlas = Atlas.init(allocator, font);
    atlas.deinit();

    defer sdl.init.shutdown();

    const init_flags = sdl.init.Flags{ .video = true };
    try sdl.init.init(init_flags);
    defer sdl.init.quit(init_flags);

    const window = try sdl.video.Window.init("Meadow", SCREEN_WIDTH, SCREEN_HEIGHT, .{});
    defer window.deinit();

    const surface = try window.getSurface();
    try surface.fillRect(null, surface.mapRgb(50, 50, 50));

    try atlas.render(surface, .{ .x = 10, .y = 100 }, "Hello, world", 100);
    // try surface.fillRect(.{ .x = 10, .y = 100, .h = 1, .w = 600 }, surface.mapRgb(255, 50, 255));

    try window.updateSurface();
    while (true) {
        switch ((try sdl.events.wait(true)).?) {
            .quit => break,
            .terminating => break,
            .key_down => |key| {
                _ = key;
            },
            else => {},
        }
    }
}

const text_renderer = @import("./text_renderer/fill.zig");

test {
    std.testing.refAllDecls(@This());
}
