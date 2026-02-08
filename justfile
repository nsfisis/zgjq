help:
    @just -l

build: fmt
    @zig build

run QUERY:
    @zig build run -- --debug-dump-disasm "{{QUERY}}"

test: fmt
    @zig build test

fmt:
    @zig fmt .
