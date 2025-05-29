const std = @import("std");

pub const LocaTable = struct {
    offsets: []u32,

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader, num_glyphs: u16, loca_format: i16) !LocaTable {
        var offsets = try allocator.alloc(u32, num_glyphs + 1);
        if (loca_format == 1) {
            var i: usize = 0;
            while (i < offsets.len) : (i += 1) {
                offsets[i] = try reader.readInt(u32, .big);
            }
        } else {
            //Short format, normalize this whacky alternative
            var i: usize = 0;
            while (i < offsets.len) : (i += 1) {
                const offset = try reader.readInt(u16, .big);
                offsets[i] = @as(u32, @intCast(offset)) * 2;
            }
        }

        return LocaTable{ .offsets = offsets };
    }

    pub fn deinit(self: LocaTable, allocator: std.mem.Allocator) void {
        allocator.free(self.offsets);
    }
};
