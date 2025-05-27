const std = @import("std");
const Font = @import("./ttf/Font.zig");

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
    _ = try Font.parse(allocator, reader);
}
