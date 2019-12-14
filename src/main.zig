const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const Expression = struct {
    name: []const u8,
    typeId: builtin.TypeId,
    format: void = {},
};

fn countExprs(str: []const u8) usize {
    var result: usize = 0;
    for (str) |c| {
        if (c == '{') {
            result += 1;
        }
    }
    return result;
}

fn Template(comptime fmt: []const u8) type {
    const num_exprs = countExprs(fmt);

    comptime var build_literals: [num_exprs + 1][]const u8 = undefined;
    comptime var build_expressions: [num_exprs]Expression = undefined;

    const State = enum {
        Literal,
        Expression,
    };

    comptime var start_idx = 0;
    comptime var build_idx = 0;

    comptime var state: State = .Literal;

    for (fmt) |c, i| {
        switch (c) {
            '{' => {
                if (state == .Expression) {
                    @compileError("Too many levels of '{' at " ++ i);
                }
                build_literals[build_idx] = fmt[start_idx..i];
                start_idx = i;
                state = .Expression;
            },
            '}' => {
                if (state == .Literal) {
                    @compileError("Unmatched '}' at " ++ i);
                }
                build_expressions[build_idx] = .{
                    .name = fmt[start_idx .. i + 1],
                    .typeId = .Int,
                };
                start_idx = i + 1;
                build_idx += 1;
                state = .Literal;
            },
            else => {},
        }
    }
    if (state == .Expression) {
        @compileError("Unmatched '{' at " ++ start_idx);
    }
    build_literals[build_idx] = fmt[start_idx..];

    return struct {
        const literals = build_literals;
        const expressions = build_expressions;

        fn copy(buf: []u8, val: []const u8) !usize {
            if (val.len > buf.len) return error.BufferTooSmall;
            std.mem.copy(u8, buf, val);
            return val.len;
        }

        pub fn bufPrint(buf: []u8, args: var) error{BufferTooSmall}![]u8 {
            var curr: usize = 0;
            for (expressions) |expr, i| {
                curr += try copy(buf[curr..], literals[i]);
            }
            curr += try copy(buf[curr..], literals[literals.len - 1]);
            return buf[0..curr];
        }
    };
}

test "basic init" {
    var out_buf: [1000]u8 = undefined;
    {
        const tmpl = Template("hello");

        testing.expectEqual(tmpl.literals.len, 1);
        testing.expectEqual(tmpl.expressions.len, 0);
        testing.expectEqualSlices(u8, tmpl.literals[0], "hello");

        const out = try tmpl.bufPrint(&out_buf, .{});
        testing.expectEqualSlices(u8, out, "hello");
    }

    {
        const tmpl = Template("hello{0}world");
        testing.expectEqual(tmpl.literals.len, 2);
        testing.expectEqualSlices(u8, tmpl.literals[0], "hello");
        testing.expectEqualSlices(u8, tmpl.literals[1], "world");
        testing.expectEqual(tmpl.expressions.len, 1);
        testing.expectEqualSlices(u8, tmpl.expressions[0].name, "{0}");

        const out = try tmpl.bufPrint(&out_buf, .{});
        testing.expectEqualSlices(u8, out, "helloworld");
    }
}
