help:
    @just -l

build: fmt
    @zig build

test: fmt
    @zig build test

fmt:
    @zig fmt .
