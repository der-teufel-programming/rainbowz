const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Color = @import("VM.zig").Color;

/// For terminal purposes Black is displayed as white
pub fn colorize(source: [:0]const u8, output_stream: anytype) !void {
    var toks = Tokenizer.init(source);
    var colors: Color.Colors = .{};
    while (true) {
        const tok = toks.next();
        if (tok.tag == .eof) break;

        try changeColor(output_stream, tok.color, colors);
        colors = tok.color;

        if (tok.tag == .invalid) continue;
        switch (tok.tag) {
            .eof, .invalid => {},
            .at => {
                const tok_cont = toks.token(tok);
                try output_stream.writeAll(tok_cont[1..]);
            },
            .asterisk => {
                const tok_cont = toks.token(tok);
                try output_stream.print("\x1b[4m{s}\x1b[24m", .{tok_cont[1..]});
            },
            else => try output_stream.writeAll(tok.tag.lexeme().?),
        }
    }
    try output_stream.writeAll("\x1b[0m");
}

fn changeColor(writer: anytype, new_colors: Color.Colors, old_colors: Color.Colors) !void {
    const switch_fg = new_colors.fg != old_colors.fg;
    const switch_bg = new_colors.bg != old_colors.bg;
    const same_color = new_colors.fg == new_colors.bg;
    const change: u3 = @as(u3, @intFromBool(same_color)) << 2 | @as(u3, @intFromBool(switch_bg)) << 1 | @as(u3, @intFromBool(switch_fg));
    // std.debug.print("> {b:0>3}\n", .{change});
    switch (change) {
        0b000 => {},
        0b010 => try ansiBgSeq(writer, new_colors.bg),
        0b001 => try ansiFgSeq(writer, new_colors.fg),
        0b011 => try ansiBothSeq(writer, new_colors.fg, new_colors.bg),
        0b100,
        0b101,
        0b110,
        0b111,
        => try ansiEmptyBgFgSeq(writer, new_colors.fg),
    }
}

fn printWithColour(writer: anytype, colors: Color.Colors, text: []const u8) !void {
    const fg_code = if (colors.fg != .Black) colors.fg.xtermNumber() else 15;
    const bg_code = if (colors.bg != .Black) colors.bg.xtermNumber() else 15;
    try writer.print("\x1b[48;5;{};m\x1b[38;5;{}", .{ bg_code, fg_code, text });
}

fn setColor(writer: anytype, colors: Color.Colors) !void {
    if (colors.fg == colors.bg) {
        try ansiEmptyBgFgSeq(writer, colors.fg);
    } else {
        try ansiBothSeq(writer, colors.fg, colors.bg);
    }
}

fn ansiFgSeq(writer: anytype, color: Color) !void {
    const code = if (color != .Black) color.xtermNumber() else 255;
    try writer.print("\x1b[38;5;{}m", .{code});
}

fn ansiBgSeq(writer: anytype, color: Color) !void {
    const code = if (color != .Black) color.xtermNumber() else 255;
    try writer.print("\x1b[48;5;{}m", .{code});
}

fn ansiBothSeq(writer: anytype, fg: Color, bg: Color) !void {
    const fg_code = if (fg != .Black) fg.xtermNumber() else 255;
    const bg_code = if (bg != .Black) bg.xtermNumber() else 255;
    try writer.print("\x1b[48;5;{}m\x1b[38;5;{}m", .{ bg_code, fg_code });
}

fn ansiEmptyBgFgSeq(writer: anytype, fg: Color) !void {
    const code = if (fg != .Black) fg.xtermNumber() else 255;
    try writer.print("\x1b[48;5;232;m\x1b[38;5;{}m", .{code});
}
