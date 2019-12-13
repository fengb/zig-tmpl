const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const Expression = struct {
    name: []const u8,
    typeId: builtin.TypeId,
    format: void,
};

fn Template(comptime fmt: []const u8) type {
    comptime var build_literals = [_][]const u8{undefined};
    comptime var build_expressions = [_]Expression{};

    build_literals[0] = fmt;

    return struct {
        const literals = build_literals;
        const expressions = build_expressions;

        fn runAlloc(allocator: *std.mem.Allocator, args: var) void {}
    };
}

test "basic init" {
    const tmpl = Template("hello");

    testing.expectEqual(tmpl.literals.len, 1);
    testing.expectEqual(tmpl.expressions.len, 0);
    testing.expectEqual(tmpl.literals[0], "hello");
}
