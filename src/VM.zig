const std = @import("std");
const testing = std.testing;

pub var stack_limit: usize = 10_000;

pub const CPU = struct {
    tapes: [tape_len * tape_count]u8 = .{0} ** (tape_len * tape_count),
    pointers: [tape_count]u15 = .{0} ** tape_count,
    carry: u1 = 0,

    const tape_len = std.math.maxInt(u15);
    const tape_count = @typeInfo(Color).Enum.fields.len;

    pub fn reset(self: *CPU) void {
        self.* = .{};
    }

    // Instructions
    inline fn resetCarry(self: *CPU) void {
        self.carry = 0;
    }
    inline fn ptr(self: CPU, color: Color) u15 {
        return self.pointers[@intFromEnum(color)];
    }
    inline fn fetch(self: *CPU, color: Color) u8 {
        return self.accessByColor(color).*;
    }
    inline fn access(self: *CPU, color: Color) *u15 {
        return &self.pointers[@intFromEnum(color)];
    }
    inline fn accessTape(self: *CPU, color: Color, idx: usize) *u8 {
        return &self.tapes[@as(usize, @intCast(@intFromEnum(color))) * tape_len + idx];
    }
    inline fn accessByColor(self: *CPU, color: Color) *u8 {
        return self.accessTape(color, self.ptr(color));
    }
    inline fn storeInto(self: *CPU, color: Color, value: u8) void {
        self.accessByColor(color).* = value;
    }
    inline fn increment(self: *CPU, fg: Color, bg: Color, inc: u8) void {
        self.accessByColor(bg).* = self.fetch(fg) +% inc;
    }
    inline fn decrement(self: *CPU, fg: Color, bg: Color, dec: u8) void {
        self.accessByColor(bg).* = self.fetch(fg) -% dec;
    }
    inline fn left(self: *CPU, fg: Color, bg: Color, move: u15) void {
        self.access(bg).* = self.ptr(fg) -% move;
    }
    inline fn right(self: *CPU, fg: Color, bg: Color, move: u15) void {
        self.access(bg).* = self.ptr(fg) +% move;
    }
    inline fn add(self: *CPU, fg: Color, bg: Color) void {
        const val = self.fetch(fg);
        self.accessByColor(bg).*, self.carry = @addWithOverflow(self.accessByColor(bg).*, val);
    }
    inline fn sub(self: *CPU, fg: Color, bg: Color) void {
        const val = self.fetch(fg);
        self.accessByColor(bg).*, self.carry = @subWithOverflow(self.accessByColor(bg).*, val);
    }
    inline fn mul(self: *CPU, fg: Color, bg: Color) void {
        const fg_copy: u16 = @intCast(self.fetch(fg));
        const bg_copy: u16 = @intCast(self.fetch(bg));
        const res = fg_copy * bg_copy;
        self.resetCarry();
        self.storeInto(bg, @truncate(res));
        self.storeInto(fg, @truncate(res >> 8));
    }
    inline fn div(self: *CPU, fg: Color, bg: Color) void {
        const fg_copy = self.fetch(fg);
        const bg_copy = self.fetch(bg);
        self.storeInto(fg, fg_copy % bg_copy);
        self.storeInto(bg, fg_copy / bg_copy);
    }
    inline fn invert(self: *CPU, fg: Color, bg: Color) void {
        self.accessByColor(bg).* = ~self.fetch(fg);
    }
    inline fn bit_or(self: *CPU, fg: Color, bg: Color) void {
        self.resetCarry();
        self.accessByColor(bg).* = self.fetch(fg) | self.fetch(bg);
    }
    inline fn bit_and(self: *CPU, fg: Color, bg: Color) void {
        self.resetCarry();
        self.accessByColor(bg).* = self.fetch(fg) & self.fetch(bg);
    }
    inline fn bit_xor(self: *CPU, fg: Color, bg: Color) void {
        self.resetCarry();
        self.accessByColor(bg).* = self.fetch(fg) ^ self.fetch(bg);
    }
    inline fn shift_left(self: *CPU, fg: Color, bg: Color) void {
        const res, const carry = @shlWithOverflow(self.fetch(fg), 1);
        self.accessByColor(bg).* = res | self.carry;
        self.carry = carry;
    }
    inline fn shift_right(self: *CPU, fg: Color, bg: Color) void {
        const carry: u1 = @truncate(self.fetch(fg));
        const res = self.fetch(fg) >> 1 | @as(u8, self.carry) << 7;
        self.accessByColor(bg).* = res;
        self.carry = carry;
    }

    test {
        var machine: CPU = .{};
        machine.right(.Red, .Red, 1);
        try std.testing.expectEqual(@as(u15, 1), machine.pointers[@intFromEnum(Color.Red)]);
        machine.storeInto(.Red, 10);
        try std.testing.expectEqual(@as(u8, 10), machine.fetch(.Red));
        machine.access(.Black).* = 2;
        machine.storeInto(.Black, 0xFF);
        machine.add(.Black, .Red);
        try std.testing.expectEqual(@as(u1, 1), machine.carry);
        try std.testing.expectEqual(@as(u8, 9), machine.fetch(.Red));
        machine.invert(.Black, .Green);
        try std.testing.expectEqual(@as(u8, 0x00), machine.fetch(.Green));
        machine.storeInto(.Red, 10);
        machine.decrement(.Red, .Red, 1);
        try std.testing.expectEqual(@as(u8, 9), machine.fetch(.Red));
        try std.testing.expectEqual(@as(u1, 1), machine.carry);
        machine.storeInto(.Orange, 0x10);
        machine.right(.Violet, .Violet, 2);
        machine.storeInto(.Violet, 0x20);
        machine.mul(.Orange, .Violet);
        try std.testing.expectEqual(@as(u8, 0x00), machine.fetch(.Violet));
        try std.testing.expectEqual(@as(u8, 0x02), machine.fetch(.Orange));
        machine.storeInto(.Cyan, 0x01);
        machine.shift_right(.Cyan, .Yellow);
        try std.testing.expectEqual(@as(u8, 0x00), machine.fetch(.Yellow));
        try std.testing.expectEqual(@as(u1, 1), machine.carry);
        machine.shift_left(.Yellow, .Cyan);
        try std.testing.expectEqual(@as(u8, 0x01), machine.fetch(.Cyan));
        try std.testing.expectEqual(@as(u1, 0), machine.carry);
    }
};

pub const VM = struct {
    cpu: CPU = .{},
    instrs: []const Instr = &.{},
    functions: [CPU.tape_count]?usize = .{null} ** CPU.tape_count,
    ret: std.ArrayList(CallContext),
    ip: usize = 0,

    const CallContext = struct {
        func_start: usize,
        ret_addr: usize,
    };

    pub fn init(gpa: std.mem.Allocator) VM {
        return .{ .ret = std.ArrayList(CallContext).init(gpa) };
    }

    pub fn deinit(self: VM) void {
        self.ret.deinit();
    }

    pub fn reset(self: *VM) void {
        self.ret.clearRetainingCapacity();
        self.ip = 0;
        self.cpu.reset();
        self.functions = .{null} ** CPU.tape_count;
    }

    pub fn run(self: *VM, instrs: []const Instr, input: anytype, output: anytype) !void {
        while (self.ip < instrs.len) {
            const instr = instrs[self.ip];
            switch (instr.op) {
                .left => self.cpu.left(instr.fg, instr.bg, instr.val.u15),
                .right => self.cpu.right(instr.fg, instr.bg, instr.val.u15),
                .inc => self.cpu.increment(instr.fg, instr.bg, instr.val.u8),
                .dec => self.cpu.decrement(instr.fg, instr.bg, instr.val.u8),
                .add => self.cpu.add(instr.fg, instr.bg),
                .sub => self.cpu.sub(instr.fg, instr.bg),
                .mul => self.cpu.mul(instr.fg, instr.bg),
                .div => self.cpu.div(instr.fg, instr.bg),
                .inv => self.cpu.div(instr.fg, instr.bg),
                .bit_or => self.cpu.bit_or(instr.fg, instr.bg),
                .bit_and => self.cpu.bit_and(instr.fg, instr.bg),
                .bit_xor => self.cpu.bit_xor(instr.fg, instr.bg),
                .shift_left => self.cpu.shift_left(instr.fg, instr.bg),
                .shift_right => self.cpu.shift_right(instr.fg, instr.bg),
                .cjmp => {
                    if (self.cpu.fetch(instr.fg) != 0)
                        self.ip = instr.val.usize;
                },
                .ncjmp => {
                    if (self.cpu.fetch(instr.fg) == 0)
                        self.ip = instr.val.usize;
                },
                .call => {
                    try self.ret.append(.{
                        .ret_addr = self.ip,
                        .func_start = instr.val.usize,
                    });
                    if (self.ret.items.len > stack_limit) return error.StackOverflow;
                    self.ip = instr.val.usize;
                },
                .ptr_call => {
                    if (self.functions[@intFromEnum(instr.fg)]) |func| {
                        try self.ret.append(.{
                            .ret_addr = self.ip,
                            .func_start = func,
                        });
                        self.ip = func;
                    }
                },
                .ret => {
                    if (self.ret.getLastOrNull()) |top| {
                        if (instr.val.usize == top.func_start) {
                            self.ip = self.ret.pop().ret_addr;
                        }
                    }
                },
                .func_store => {
                    self.functions[@intFromEnum(instr.bg)] = instr.val.usize;
                },
                .input => {
                    self.cpu.accessByColor(instr.bg).* = input.readByte() catch 0;
                },
                .output => {
                    try output.writeByte(self.cpu.fetch(instr.fg));
                },
                .nop => {},
            }
            self.ip += 1;
        }
    }

    pub fn debugRun(self: *VM, instrs: []const Instr, input: []const u8) ![]const u8 {
        self.instrs = instrs;
        var input_stream = std.io.fixedBufferStream(input);
        const input_reader = input_stream.reader();
        var output_raw = std.ArrayList(u8).init(self.ret.allocator);
        defer output_raw.deinit();
        var output = output_raw.writer();
        while (self.ip < self.instrs.len) {
            const instr = self.instrs[self.ip];
            std.debug.print(
                "[{d:0>2}]: {s: <6} val:{?: >4} ret: {{",
                .{
                    self.ip,
                    @tagName(instr.op),
                    // @tagName(instr.fg),
                    // @tagName(instr.bg),
                    switch (instr.val) {
                        .void => null,
                        .u15 => |u| @as(usize, @intCast(u)),
                        .u8 => |u| @as(usize, @intCast(u)),
                        .usize => |u| u,
                    },
                },
            );
            for (self.ret.items) |ri| {
                std.debug.print(".{{.fs={}, .ra={}}}, ", .{ ri.func_start, ri.ret_addr });
            }
            std.debug.print("}}\n", .{});
            switch (instr.op) {
                .left => self.cpu.left(instr.fg, instr.bg, instr.val.u15),
                .right => self.cpu.right(instr.fg, instr.bg, instr.val.u15),
                .inc => self.cpu.increment(instr.fg, instr.bg, instr.val.u8),
                .dec => self.cpu.decrement(instr.fg, instr.bg, instr.val.u8),
                .add => self.cpu.add(instr.fg, instr.bg),
                .sub => self.cpu.sub(instr.fg, instr.bg),
                .mul => self.cpu.mul(instr.fg, instr.bg),
                .div => self.cpu.div(instr.fg, instr.bg),
                .inv => self.cpu.div(instr.fg, instr.bg),
                .bit_or => self.cpu.bit_or(instr.fg, instr.bg),
                .bit_and => self.cpu.bit_and(instr.fg, instr.bg),
                .bit_xor => self.cpu.bit_xor(instr.fg, instr.bg),
                .shift_left => self.cpu.shift_left(instr.fg, instr.bg),
                .shift_right => self.cpu.shift_right(instr.fg, instr.bg),
                .cjmp => {
                    if (self.cpu.fetch(instr.fg) != 0)
                        self.ip = instr.val.usize;
                },
                .ncjmp => {
                    if (self.cpu.fetch(instr.fg) == 0)
                        self.ip = instr.val.usize;
                },
                .call => {
                    try self.ret.append(.{
                        .ret_addr = self.ip,
                        .func_start = instr.val.usize,
                    });
                    self.ip = instr.val.usize;
                },
                .ptr_call => {
                    if (self.functions[@intFromEnum(instr.fg)]) |func| {
                        try self.ret.append(.{
                            .ret_addr = self.ip,
                            .func_start = func,
                        });
                        self.ip = func;
                    }
                },
                .ret => {
                    if (self.ret.getLastOrNull()) |top| {
                        if (instr.val.usize == top.func_start) {
                            self.ip = self.ret.pop().ret_addr;
                        }
                    }
                },
                .func_store => {
                    self.functions[@intFromEnum(instr.bg)] = instr.val.usize;
                },
                .input => {
                    self.cpu.accessByColor(instr.bg).* = try input_reader.readByte();
                },
                .output => {
                    try output.writeByte(self.cpu.fetch(instr.fg));
                },
                .nop => {},
            }
            self.ip += 1;
        }
        return output_raw.toOwnedSlice();
    }

    pub fn dumpState(self: *VM, writer: anytype) !void {
        try writer.print("Pointers:\n", .{});
        inline for (@typeInfo(Color).Enum.fields) |field| {
            try writer.print("* {s: <6} = {d:0>4}\n", .{ field.name, self.cpu.ptr(@field(Color, field.name)) });
        }
    }
};

pub const Instr = struct {
    op: Op,
    fg: Color,
    bg: Color,
    val: union(enum) { u8: u8, u15: u15, void: void, usize: usize } = .{ .void = {} },

    pub const Op = enum(u8) {
        left,
        right,
        inc,
        dec,
        add,
        sub,
        mul,
        div,
        cjmp,
        ncjmp,
        inv,
        bit_or,
        bit_and,
        bit_xor,
        shift_left,
        shift_right,
        call,
        ptr_call,
        ret,
        func_store,
        input,
        output,
        nop,
    };
};

pub const Color = enum(u4) {
    Red,
    Orange,
    Yellow,
    Green,
    Blue,
    Violet,
    Pink,
    Cyan,
    Brown,
    Black,

    pub const Colors = struct {
        fg: Color = .Black,
        bg: Color = .Black,
    };

    pub fn fromChar(c: u8) ?Color {
        return switch (c) {
            'r', 'R' => .Red,
            'o', 'O' => .Orange,
            'y', 'Y' => .Yellow,
            'g', 'G' => .Green,
            'b', 'B' => .Blue,
            'v', 'V' => .Violet,
            'p', 'P' => .Pink,
            'c', 'C' => .Cyan,
            'w', 'W' => .Brown,
            'k', 'K' => .Black,
            else => null,
        };
    }

    pub fn xtermNumber(color: Color) u8 {
        return switch (color) {
            .Red => 196,
            .Orange => 208,
            .Yellow => 11,
            .Green => 46,
            .Blue => 21,
            .Violet => 93,
            .Pink => 207,
            .Cyan => 51,
            .Brown => 130,
            .Black => 0,
        };
    }
};

test {
    _ = Color;
    _ = CPU;
}
