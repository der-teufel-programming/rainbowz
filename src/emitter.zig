const std = @import("std");
const VM = @import("VM.zig");
const tokenizer = @import("tokenizer.zig");
const Allocator = std.mem.Allocator;

pub fn emit(source: [:0]const u8, gpa: Allocator) ![]const VM.Instr {
    var tokens = tokenizer.Tokenizer.init(source);
    var instrs = try std.ArrayList(VM.Instr).initCapacity(gpa, source.len / 4);
    defer instrs.deinit();

    var loop_stacks: [@typeInfo(VM.Color).Enum.fields.len]std.ArrayListUnmanaged(usize) = .{.{}} ** @typeInfo(VM.Color).Enum.fields.len;
    defer {
        for (&loop_stacks) |*lst| {
            lst.deinit(gpa);
        }
    }

    const Scope = struct {
        functions: [26]?usize = .{null} ** 26,
        origin: usize = 0,
        parent_scope: ?*@This() = null,
        waiting_calls: std.ArrayListUnmanaged(usize) = .{},
    };

    var current_scope: *Scope = try gpa.create(Scope);
    defer gpa.destroy(current_scope);
    current_scope.* = .{};
    defer current_scope.waiting_calls.deinit(gpa);

    var tok_idx: usize = 0;
    while (true) : (tok_idx += 1) {
        const tok = tokens.next();
        switch (tok.tag) {
            .exclamation => try instrs.append(.{
                .op = .inv,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .ampersand => try instrs.append(.{
                .op = .bit_and,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .pipe => try instrs.append(.{
                .op = .bit_or,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .caret => try instrs.append(.{
                .op = .bit_xor,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .plus => try instrs.append(.{
                .op = .inc,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
                .val = .{ .u8 = 1 },
            }),
            .minus => try instrs.append(.{
                .op = .dec,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
                .val = .{ .u8 = 1 },
            }),
            .left => try instrs.append(.{
                .op = .left,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
                .val = .{ .u15 = 1 },
            }),
            .right => try instrs.append(.{
                .op = .right,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
                .val = .{ .u15 = 1 },
            }),
            .dot => try instrs.append(.{
                .op = .output,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .comma => try instrs.append(.{
                .op = .input,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .lbrace => try instrs.append(.{
                .op = .shift_left,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .rbrace => try instrs.append(.{
                .op = .shift_right,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .double_plus => try instrs.append(.{
                .op = .add,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .triple_plus => try instrs.append(.{
                .op = .mul,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .equals => try instrs.append(.{
                .op = .sub,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .equivalent => try instrs.append(.{
                .op = .div,
                .fg = tok.color.fg,
                .bg = tok.color.bg,
            }),
            .lbracket => {
                // Begin a loop with jump color in bg
                // and test color in fg
                const loop_idx = instrs.items.len;
                try instrs.append(.{
                    .op = .ncjmp,
                    .fg = tok.color.fg,
                    .bg = tok.color.bg,
                    .val = .{ .usize = 0 },
                });
                try loop_stacks[@intFromEnum(tok.color.bg)].append(gpa, loop_idx);
            },
            .rbracket => {
                // End a loop with jump color in bg
                // and test color in fg
                const loop_idx = instrs.items.len;
                const loop_start = loop_stacks[@intFromEnum(tok.color.bg)].popOrNull() orelse return error.UnmatchedLoop;
                try instrs.append(.{
                    .op = .cjmp,
                    .fg = tok.color.fg,
                    .bg = tok.color.bg,
                    .val = .{ .usize = loop_start },
                });
                instrs.items[loop_start].val.usize = loop_idx;
            },
            .hash => {
                if (current_scope.parent_scope != null) {
                    try instrs.append(.{
                        .op = .ret,
                        .fg = tok.color.fg,
                        .bg = tok.color.bg,
                        .val = .{ .usize = current_scope.origin },
                    });
                    var old_scope = current_scope;
                    for (old_scope.waiting_calls.items) |call_idx| {
                        if (old_scope.functions[instrs.items[call_idx].val.u8]) |code| {
                            instrs.items[call_idx].val = .{ .usize = code };
                        } else {
                            instrs.items[call_idx].op = .nop;
                        }
                    }
                    current_scope = current_scope.parent_scope.?;
                    old_scope.waiting_calls.deinit(gpa);
                    gpa.destroy(old_scope);
                }
            },
            .at => {
                const letter = tokens.token(tok)[1];
                switch (letter) {
                    'a'...'z' => {
                        if (current_scope.functions[letter - 'a']) |code| {
                            try instrs.append(.{
                                .op = .call,
                                .fg = tok.color.fg,
                                .bg = tok.color.bg,
                                .val = .{ .usize = code },
                            });
                        } else {
                            current_scope.functions[letter - 'a'] = instrs.items.len;
                            try instrs.append(.{
                                .op = .nop,
                                .fg = tok.color.fg,
                                .bg = tok.color.bg,
                            });
                            var new_scope = try gpa.create(Scope);
                            new_scope.* = .{};
                            new_scope.parent_scope = current_scope;
                            new_scope.functions = .{null} ** 26;
                            new_scope.origin = instrs.items.len - 1;
                            current_scope = new_scope;
                        }
                    },
                    'A'...'Z' => {
                        if (current_scope.parent_scope) |scope| {
                            if (scope.functions[letter - 'A']) |code| {
                                try instrs.append(.{
                                    .op = .call,
                                    .fg = tok.color.fg,
                                    .bg = tok.color.bg,
                                    .val = .{ .usize = code },
                                });
                            } else {
                                try scope.waiting_calls.append(gpa, instrs.items.len);
                                try instrs.append(.{
                                    .op = .call,
                                    .fg = tok.color.fg,
                                    .bg = tok.color.bg,
                                    .val = .{ .u8 = letter - 'A' },
                                });
                            }
                        }
                    },
                    '*' => try instrs.append(.{
                        .op = .ptr_call,
                        .fg = tok.color.fg,
                        .bg = tok.color.bg,
                    }),
                    else => {
                        std.debug.print("Error :{}..{}:\n", .{ tok.loc.start, tok.loc.end });
                        std.debug.print("{s}\n", .{tokens.buffer});

                        return error.InvalidToken;
                    },
                }
            },
            // Not implemented yet
            .asterisk => {},
            .eof => break,
            .invalid => return error.InvalidToken,
        }
        if (false) {
            const ins = instrs.getLast();
            std.debug.print("[{d:0>2}] {s: >2} => {s:.<7} {?}\n", .{
                tok_idx,
                tokens.token(tok),
                @tagName(ins.op),
                switch (ins.val) {
                    .void => null,
                    inline else => |u| @as(usize, u),
                },
            });
        }
    }
    for (current_scope.waiting_calls.items) |call_idx| {
        if (current_scope.functions[instrs.items[call_idx].val.u8]) |code| {
            instrs.items[call_idx].val = .{ .usize = code };
        } else {
            instrs.items[call_idx].op = .nop;
        }
    }

    return instrs.toOwnedSlice();
}
