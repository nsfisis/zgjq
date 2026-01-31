const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Value = struct {
    const _Internal = std.json.Value;
    _internal: _Internal,

    pub const Kind = enum { null, bool, integer, float, string, array, object, number_string };

    pub fn kind(self: Value) Kind {
        return switch (self._internal) {
            .null => .null,
            .bool => .bool,
            .integer => .integer,
            .float => .float,
            .string => .string,
            .array => .array,
            .object => .object,
            .number_string => .number_string,
        };
    }

    pub const @"null": Value = .{ ._internal = .null };
    pub const @"true": Value = .{ ._internal = .{ .bool = true } };
    pub const @"false": Value = .{ ._internal = .{ .bool = false } };

    pub fn initBool(b: bool) Value {
        return .{ ._internal = .{ .bool = b } };
    }

    pub fn initInteger(i: i64) Value {
        return .{ ._internal = .{ .integer = i } };
    }

    pub fn initFloat(f: f64) Value {
        return .{ ._internal = .{ .float = f } };
    }

    pub fn initString(s: []const u8) Value {
        return .{ ._internal = .{ .string = s } };
    }

    pub fn initArray(arr: Array) Value {
        return .{ ._internal = .{ .array = arr._internal } };
    }

    pub fn initObject(obj: Object) Value {
        return .{ ._internal = .{ .object = obj._internal } };
    }

    pub fn deinit(self: *Value, allocator: Allocator) void {
        switch (self._internal) {
            .string => |s| allocator.free(s),
            .array => |*a| a.deinit(),
            .object => |*o| o.deinit(),
            else => {},
        }
    }

    pub fn boolean(self: Value) bool {
        return self._internal.bool;
    }

    pub fn integer(self: Value) i64 {
        return self._internal.integer;
    }

    pub fn float(self: Value) f64 {
        return self._internal.float;
    }

    pub fn string(self: Value) []const u8 {
        return self._internal.string;
    }

    pub fn array(self: Value) Array {
        return .{ ._internal = self._internal.array };
    }

    pub fn object(self: Value) Object {
        return .{ ._internal = self._internal.object };
    }

    pub fn arrayGet(self: Value, idx: usize) Value {
        const items = self._internal.array.items;
        if (idx < items.len) {
            return .{ ._internal = items[idx] };
        }
        return Value.null;
    }

    pub fn arrayLen(self: Value) usize {
        return self._internal.array.items.len;
    }

    pub fn arrayAppend(self: *Value, item: Value) !void {
        try self._internal.array.append(item._internal);
    }

    pub fn objectGet(self: Value, key: []const u8) ?Value {
        if (self._internal.object.get(key)) |v| {
            return .{ ._internal = v };
        }
        return null;
    }

    pub fn objectSet(self: *Value, key: []const u8, val: Value) !void {
        try self._internal.object.put(key, val._internal);
    }
};

pub const Array = struct {
    const _Internal = std.json.Array;
    _internal: _Internal,

    pub fn init(allocator: Allocator) Array {
        return .{ ._internal = _Internal.init(allocator) };
    }

    pub fn deinit(self: *Array) void {
        self._internal.deinit();
    }

    pub fn get(self: Array, idx: usize) Value {
        return .{ ._internal = self._internal.items[idx] };
    }

    pub fn len(self: Array) usize {
        return self._internal.items.len;
    }

    pub fn append(self: *Array, value: Value) !void {
        try self._internal.append(value._internal);
    }
};

pub const Object = struct {
    const _Internal = std.json.ObjectMap;
    _internal: _Internal,

    pub fn init(allocator: Allocator) Object {
        return .{ ._internal = _Internal.init(allocator) };
    }

    pub fn deinit(self: *Object) void {
        self._internal.deinit();
    }

    pub fn get(self: Object, key: []const u8) ?Value {
        if (self._internal.get(key)) |v| {
            return .{ ._internal = v };
        }
        return null;
    }

    pub fn set(self: *Object, key: []const u8, value: Value) !void {
        try self._internal.put(key, value._internal);
    }
};
