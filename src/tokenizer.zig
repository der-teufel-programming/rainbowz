const std = @import("std");
const mem = std.mem;

const Color = @import("VM.zig").Color;

pub const Token = struct {
    tag: Tag,
    loc: Loc,
    color: Color.Colors,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum(u8) {
        eof = 0x00,
        double_plus = 'a',
        triple_plus = 'm',
        equivalent = 'd',
        plus = '+',
        minus = '-',
        equals = 's',
        left = '<',
        right = '>',
        lbracket = '[',
        rbracket = ']',
        dot = '.',
        comma = ',',
        ampersand = '&',
        pipe = '|',
        caret = '^',
        exclamation = '!',
        lbrace = '{',
        rbrace = '}',
        at = '@',
        hash = '#',
        asterisk = '*',
        invalid = 0xFF,

        pub fn lexeme(self: Tag) ?[]const u8 {
            return switch (self) {
                .eof => null,
                .double_plus => "‡",
                .triple_plus => "⹋",
                .equivalent => "≡",
                .plus => "+",
                .minus => "-",
                .equals => "=",
                .left => "<",
                .right => ">",
                .lbracket => "[",
                .rbracket => "]",
                .dot => ".",
                .comma => ",",
                .ampersand => "&",
                .pipe => "|",
                .caret => "^",
                .exclamation => "!",
                .lbrace => "{",
                .rbrace => "}",
                .at => "@",
                .hash => "#",
                .asterisk => "*",
                .invalid => null,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    current_color: Color.Colors = .{},
    index: usize = 0,

    pub fn init(source: [:0]const u8) Tokenizer {
        return .{ .buffer = source };
    }

    pub fn token(self: Tokenizer, tok: Token) []const u8 {
        return self.buffer[tok.loc.start..tok.loc.end];
    }

    const State = enum {
        start,
        at,
        star,
    };

    pub fn next(self: *Tokenizer) Token {
        var state: State = .start;
        var result = Token{
            .tag = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
            .color = self.current_color,
        };
        while (true) : (self.index += 1) {
            const c = self.buffer[self.index];
            switch (state) {
                .start => switch (c) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            result.tag = .invalid;
                            result.loc.start = self.index;
                            self.index += 1;
                            result.loc.end = self.index;
                            return result;
                        }
                        break;
                    },
                    '+',
                    '-',
                    '<',
                    '>',
                    '[',
                    ']',
                    '.',
                    ',',
                    // '=',
                    '{',
                    '}',
                    '!',
                    '&',
                    '^',
                    '#',
                    'a', // ‡
                    'm', // ⹋
                    's', // =
                    'd', // ≡
                    => {
                        result.tag = @enumFromInt(c);
                        self.index += 1;
                        break;
                    },
                    '@' => state = .at,
                    '*' => state = .star,

                    'r',
                    'o',
                    'y',
                    'g',
                    'b',
                    'v',
                    'p',
                    'c',
                    'w',
                    'k',
                    => {
                        self.current_color.bg = Color.fromChar(c).?;
                        result.loc.start = self.index + 1;
                    },

                    'R',
                    'O',
                    'Y',
                    'G',
                    'B',
                    'V',
                    'P',
                    'C',
                    'W',
                    'K',
                    => {
                        self.current_color.fg = Color.fromChar(c).?;
                        result.loc.start = self.index + 1;
                    },
                    ' ', '\n', '\t', '\r' => {
                        result.loc.start = self.index + 1;
                    },
                    else => {},
                },
                .at => switch (c) {
                    'a'...'z',
                    'A'...'Z',
                    => {
                        result.tag = .at;
                        self.index += 1;
                        break;
                        // result.color = .{};
                        // result.loc.end = self.index;
                        // return result;
                    },
                    '*' => {
                        result.tag = .at;
                        self.index += 1;
                        break;
                    },
                    else => break,
                },
                .star => switch (c) {
                    'a'...'z', 'A'...'Z' => {
                        result.tag = .asterisk;
                        self.index += 1;
                        break;
                        // result.color.fg = .Black;
                        // result.loc.end = self.index;
                        // return result;
                    },
                    else => break,
                },
            }
        }
        result.loc.end = self.index;
        result.color = self.current_color;
        return result;
    }
};

fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_token_tags) |expected_token_tag| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, token.tag);
    }
    const last_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.loc.start);
    try std.testing.expectEqual(source.len, last_token.loc.end);
}

fn testColors(source: [:0]const u8, expected_colors: []const Color.Colors) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_colors) |expected_color| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_color.fg, token.color.fg);
        try std.testing.expectEqual(expected_color.bg, token.color.bg);
    }
}

test "simple tokens" {
    try testTokenize("-+{", &.{ .minus, .plus, .lbrace });
    try testTokenize("[]]", &.{ .lbracket, .rbracket, .rbracket });
    try testTokenize("amd", &.{ .double_plus, .triple_plus, .equivalent });
}

test "handle colors" {
    try testTokenize("Or>Bb<", &.{ .right, .left });
    try testColors(
        "Or>Bb<",
        &.{
            .{ .fg = .Orange, .bg = .Red },
            .{ .fg = .Blue, .bg = .Blue },
        },
    );
}

test "keep color" {
    try testTokenize("Or><Bb+-", &.{ .right, .left, .plus, .minus });
    try testColors(
        "Or><Bb+-",
        &.{
            .{ .fg = .Orange, .bg = .Red },
            .{ .fg = .Orange, .bg = .Red },
            .{ .fg = .Blue, .bg = .Blue },
            .{ .fg = .Blue, .bg = .Blue },
        },
    );
}

test "complex input" {
    const ex1 =
        \\+r>{Ro>{Oy>{Yg>{Gb>{Bv>{Vp>{Pc>Cw>
        \\VaYaW.c+OsBaCc.-YaC..RaC+.Bb.RwsGaW
        \\+.Cc.-OaC.RsOsC.YsC.Bw+W.
    ;
    const tags = &.{
        .plus,
        .right,
        .lbrace,
        .right,
        .lbrace,
        .right,
        .lbrace,
        .right,
        .lbrace,
        .right,
        .lbrace,
        .right,
        .lbrace,
        .right,
        .lbrace,
        .right,
        .right,
        .double_plus,
        .double_plus,
        .dot,
        .plus,
        .equals,
        .double_plus,
        .dot,
        .minus,
        .double_plus,
        .dot,
        .dot,
        .double_plus,
        .plus,
        .dot,
        .dot,
        .equals,
        .double_plus,
        .plus,
        .dot,
        .dot,
        .minus,
        .double_plus,
        .dot,
        .equals,
        .equals,
        .dot,
        .equals,
        .dot,
        .plus,
        .dot,
    };
    try testTokenize(ex1, tags);
}

test "confusing func" {
    const src = "@aOo@*Kk+@bO*cK[-##+Oo@*Kk#Oo@*Kk]";
    try testTokenize(src, &.{
        .at,
        .at,
        .plus,
        .at,
        .asterisk,
        .lbracket,
        .minus,
        .hash,
        .hash,
        .plus,
        .at,
        .hash,
        .at,
        .rbracket,
    });
    try testColors(
        src,
        &.{
            .{ .fg = .Black, .bg = .Black }, //.at,
            .{ .fg = .Orange, .bg = .Orange }, //.at,
            .{ .fg = .Black, .bg = .Black }, //.plus,
            .{ .fg = .Black, .bg = .Black }, //.at,
            .{ .fg = .Black, .bg = .Black }, //.asterisk,
            .{ .fg = .Black, .bg = .Black }, //.lbracket,
            .{ .fg = .Black, .bg = .Black }, //.minus,
            .{ .fg = .Black, .bg = .Black }, //.hash,
            .{ .fg = .Black, .bg = .Black }, //.hash,
            .{ .fg = .Black, .bg = .Black }, //.plus,
            .{ .fg = .Black, .bg = .Black }, //.at,
            .{ .fg = .Black, .bg = .Black }, //.hash,
            .{ .fg = .Black, .bg = .Black }, //.at,
            .{ .fg = .Black, .bg = .Black }, //.rbracket,
        },
    );
}

test {
    _ = Token.Tag;
}
