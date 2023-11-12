# Rainbowz

`rainbowz` is a Zig implementation of the Rainbow Brainfuck programming language

To build it you'll need the most recent Zig version (download from https://ziglang.org/download).
```sh
$ zig build -Doptimize=ReleaseFast
```
or to build a debug version
```sh
$ zig build
```
the binary will then appear as `zig-out/bin/rainbowz` or `zig-out\bin\rainbowz.exe`