const std = @import("std");

pub const MaxpTable = struct {
    version: u32,
    num_glyphs: u16, // the number of glyphs in the font
    max_points: u16, // points in non-compound glyph
    max_contours: u16, // contours in non-compound glyph
    max_component_points: u16, // points in compound glyph
    max_component_contours: u16, // contours in compound glyph
    max_zones: u16, // set to 2
    max_twilight_points: u16, // points used in Twilight Zone (Z0)
    max_storage: u16, // number of Storage Area locations
    max_function_defs: u16, // number of FDEFs
    max_instruction_defs: u16, // number of IDEFs
    max_stack_elements: u16, // maximum stack depth
    max_size_of_instructions: u16, // byte count for glyph instructions
    max_component_elements: u16, // number of glyphs referenced at top level
    max_component_depth: u16, // levels of recursion, set to 0 if font has only simple glyphs

    pub fn parse(reader: std.io.AnyReader) !MaxpTable {
        return MaxpTable{
            .version = try reader.readInt(u32, .big),
            .num_glyphs = try reader.readInt(u16, .big),
            .max_points = try reader.readInt(u16, .big),
            .max_contours = try reader.readInt(u16, .big),
            .max_component_points = try reader.readInt(u16, .big),
            .max_component_contours = try reader.readInt(u16, .big),
            .max_zones = try reader.readInt(u16, .big),
            .max_twilight_points = try reader.readInt(u16, .big),
            .max_storage = try reader.readInt(u16, .big),
            .max_function_defs = try reader.readInt(u16, .big),
            .max_instruction_defs = try reader.readInt(u16, .big),
            .max_stack_elements = try reader.readInt(u16, .big),
            .max_size_of_instructions = try reader.readInt(u16, .big),
            .max_component_elements = try reader.readInt(u16, .big),
            .max_component_depth = try reader.readInt(u16, .big),
        };
    }
};
