const std = @import("std");
const VM = @import("VM.zig").VM;
const emitter = @import("emitter.zig");
const colorize = @import("colorize.zig").colorize;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

const sources = [_][:0]const u8{
    \\>++++++++[<+++++++++>-]<.>++++[<+++++++>-]
    \\<+.+++++++..+++.>>++++++[<+++++++>-]<++.
    \\------------.>++++++[<+++++++++>-]<+.
    \\<.+++.------.--------.>>>++++[<++++++++>-]<+.
    ,
    \\Kr>Ro>Oy>Yg>Gb>Bv>Vp>Pc>Cw>WKk++++++v+Vk+K[Rr++++Kk-]Ro+Oy+Yg+Gw+W[Yy+Gg++Ww-]
    \\Yy++b+Vv[Bb++Vv-]Gv+Vp+P++c+C++Gg------w-Yy.Gg.Vv..Pp.Rr.Bb.Pp.Cc.Vv.Ww.Oo.
    ,
    \\+r>{Ro>{Oy>{Yg>{Gb>{Bv>{Vp>{Pc>Cw>
    \\VaYaW.c+OsBaCc.-YaC..RaC+.Bb.RwsGaW
    \\+.Cc.-OaC.RsOsC.YsC.Bw+W.
    ,
    \\[-]@a@b+++#@b@b@b@b#@a@a@a@a@b.#
    ,
    \\[-][
    \\@b+++#
    \\@a[>@B<-@A]#
    \\@c[>@D@A<-@C]#
    \\]
    \\@d+++++# @c >> .
    ,
    \\Kr>Ro>Kk+o+k+r+k{{oak{RmOo[Kk.+Oo-]
    ,
    \\@a@aOo++++Kk#@a@a@a@a#@a@a@a@aOo.
    ,
    // \\@aOo@*Kk+@bO*cK[-##+Oo@*Kk#Oo@*Kk]
};

fn usage() void {
    std.debug.print("{s}", .{
        \\ Usage: rainbowz [file]
        \\  . will attempt to read from standard input and will put 0 into the cell on any read error
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var machine = VM.init(alloc);
    defer machine.deinit();

    const input = "";
    var input_reader = std.io.fixedBufferStream(input);

    if (@import("builtin").os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const stdin = std.io.getStdIn().reader();
    _ = stdin;

    var args = try std.process.ArgIterator.initWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();

    const file_name = args.next() orelse {
        usage();
        std.process.exit(1);
    };
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const source = try file.readToEndAllocOptions(alloc, std.math.maxInt(u32), null, @alignOf(u8), 0);
    defer alloc.free(source);

    const em = try emitter.emit(source, alloc);
    defer alloc.free(em);
    machine.reset();
    try colorize(source, stdout);
    try stdout.writeByte('\n');
    try machine.run(em, input_reader.reader(), stdout);
    try stdout.writeByte('\n');
    try bw.flush();

    // for (sources) |src| {
    //     const em = try emitter.emit(src, alloc);
    //     defer alloc.free(em);
    //     machine.reset();
    //     try colorize(src, stdout);
    //     try stdout.writeByte('\n');
    //     try bw.flush();
    //     try machine.run(em, input_reader.reader(), stdout);
    //     try stdout.writeByte('\n');
    //     try bw.flush();
    // }

}

test {
    _ = VM;
    _ = @import("tokenizer.zig");
    _ = @import("emitter.zig");
    const emitted = try @import("emitter.zig").emit(
        \\+r>{Ro>{Oy>{Yg>{Gb>{Bv>{Vp>{Pc>Cw>
        \\VaYaW.c+OsBaCc.-YaC..RaC+.Bb.RwsGaW
        \\+.Cc.-OaC.RsOsC.YsC.Bw+W.
    , std.testing.allocator);
    defer std.testing.allocator.free(emitted);
    var machine = VM.init(std.testing.allocator);
    defer machine.deinit();
    const input = "";
    var input_reader = std.io.fixedBufferStream(input);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();
    try machine.run(emitted, input_reader.reader(), output.writer());
}
