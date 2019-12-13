const std = @import("std");
const testing = std.testing;

const Expression = enum {
    placeholder,
};

const Template = struct {
    literals: [][]const u8,
    expressions: []Expression,

    pub fn init(comptime fmt: []const u8) Template {
        comptime var build_literals = [_][]const u8{undefined};
        comptime var build_expressions = [_]Expression{};

        build_literals[0] = fmt;

        return .{
            .literals = &build_literals,
            .expressions = &build_expressions,
        };
    }

    fn runAlloc(allocator: *std.mem.Allocator, args: var) void {}
};

test "basic init" {
    const tmpl = Template.init("hello");

    testing.expectEqual(tmpl.literals.len, 1);
    testing.expectEqual(tmpl.expressions.len, 0);
    testing.expectEqual(tmpl.literals[0], "hello");
}
