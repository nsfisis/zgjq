const std = @import("std");
const Rc = @import("./rc.zig").Rc;

pub const ValueKind = enum {
    null,
    bool,
    integer,
    float,
    string,
    array,
    object,
};

pub const Value = union(ValueKind) {
    null: void,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: Array,
    object: Object,

    pub const @"true": Value = .{ .bool = true };
    pub const @"false": Value = .{ .bool = false };

    pub fn initBool(b: bool) Value {
        return .{ .bool = b };
    }

    pub fn initInteger(i: i64) Value {
        return .{ .integer = i };
    }

    pub fn initFloat(f: f64) Value {
        return .{ .float = f };
    }

    pub fn initString(s: []const u8) Value {
        return .{ .string = s };
    }

    pub fn initArray(arr: Array) Value {
        return .{ .array = arr };
    }

    pub fn initObject(obj: Object) Value {
        return .{ .object = obj };
    }

    pub fn kind(self: Value) ValueKind {
        return self;
    }

    pub fn clone(self: Value) Value {
        return switch (self) {
            .array => |a| .{ .array = a.clone() },
            .object => |o| .{ .object = o.clone() },
            else => self,
        };
    }

    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .array => |a| a.deinit(allocator),
            .object => |o| o.deinit(allocator),
            else => {},
        }
    }

    pub fn arrayAppend(self: *Value, allocator: std.mem.Allocator, item: Value) !void {
        try self.array.append(allocator, item);
    }

    pub fn jsonStringify(self: Value, jws: anytype) !void {
        switch (self) {
            .null => try jws.write(null),
            .bool => |b| try jws.write(b),
            .integer => |i| try jws.write(i),
            .float => |f| try jws.write(f),
            .string => |s| try jws.write(s),
            .array => |a| {
                try jws.beginArray();
                for (0..a.len()) |i| {
                    try a.get(i).jsonStringify(jws);
                }
                try jws.endArray();
            },
            .object => |o| {
                try jws.beginObject();
                var it = o.iterator();
                while (it.next()) |entry| {
                    try jws.objectField(entry.key_ptr.*);
                    try entry.value_ptr.jsonStringify(jws);
                }
                try jws.endObject();
            },
        }
    }
};

pub const Array = struct {
    const Inner = std.ArrayList(Value);

    rc: Rc(Inner),

    pub fn init(allocator: std.mem.Allocator) !Array {
        return .{ .rc = try Rc(Inner).init(allocator, .{}) };
    }

    pub fn clone(self: Array) Array {
        return .{ .rc = self.rc.retain() };
    }

    pub fn deinit(self: Array, allocator: std.mem.Allocator) void {
        if (self.rc.isUnique()) {
            for (self.rc.get().items) |item| {
                item.deinit(allocator);
            }
            self.rc.get().deinit(allocator);
        }
        self.rc.release(allocator);
    }

    pub fn get(self: Array, idx: usize) Value {
        const items = self.rc.get().items;
        if (idx < items.len) {
            return items[idx];
        }
        return Value.null;
    }

    pub fn len(self: Array) usize {
        return self.rc.get().items.len;
    }

    pub fn append(self: *Array, allocator: std.mem.Allocator, value: Value) !void {
        try self.ensureUnique(allocator);
        try self.rc.get().append(allocator, value);
    }

    fn ensureUnique(self: *Array, allocator: std.mem.Allocator) !void {
        if (!self.rc.isUnique()) {
            const old_items = self.rc.get().items;
            var new_inner: Inner = .{};
            try new_inner.ensureTotalCapacity(allocator, old_items.len);
            for (old_items) |item| {
                new_inner.appendAssumeCapacity(item.clone());
            }
            self.rc.release(allocator);
            self.rc = try Rc(Inner).init(allocator, new_inner);
        }
    }
};

pub const Object = struct {
    const Inner = std.StringArrayHashMapUnmanaged(Value);

    rc: Rc(Inner),

    pub fn init(allocator: std.mem.Allocator) !Object {
        return .{ .rc = try Rc(Inner).init(allocator, .{}) };
    }

    pub fn clone(self: Object) Object {
        return .{ .rc = self.rc.retain() };
    }

    pub fn deinit(self: Object, allocator: std.mem.Allocator) void {
        if (self.rc.isUnique()) {
            for (self.rc.get().values()) |v| {
                v.deinit(allocator);
            }
            self.rc.get().deinit(allocator);
        }
        self.rc.release(allocator);
    }

    pub fn get(self: Object, key: []const u8) ?Value {
        return self.rc.get().get(key);
    }

    pub fn set(self: *Object, allocator: std.mem.Allocator, key: []const u8, value: Value) !void {
        try self.ensureUnique(allocator);
        try self.rc.get().put(allocator, key, value);
    }

    pub fn count(self: Object) usize {
        return self.rc.get().count();
    }

    pub fn iterator(self: Object) Inner.Iterator {
        return self.rc.get().iterator();
    }

    fn ensureUnique(self: *Object, allocator: std.mem.Allocator) !void {
        if (!self.rc.isUnique()) {
            const old = self.rc.get();
            var new_inner: Inner = .{};
            try new_inner.ensureTotalCapacity(allocator, old.count());
            var it = old.iterator();
            while (it.next()) |entry| {
                new_inner.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.clone());
            }
            self.rc.release(allocator);
            self.rc = try Rc(Inner).init(allocator, new_inner);
        }
    }
};
