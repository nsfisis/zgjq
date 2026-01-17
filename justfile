help:
    @just -l

build: fmt
    @zig build

test: fmt
    @zig test src/root.zig

fmt:
    @zig fmt .
