help:
    @just -l

build: fmt
    @zig build

run QUERY:
    @zig build run -- {{QUERY}}

test: fmt
    @zig build test

fmt:
    @zig fmt .
