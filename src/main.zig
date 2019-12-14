const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

pub fn GenContext(comptime Out: type) type {
    return struct {
        suspended: ?anyframe = null,
        out: ?Out = undefined,
        fresh: bool = true,

        pub fn next(self: *@This()) ?Out {
            if (self.fresh) {
                self.fresh = false;
                return self.out;
            }

            if (self.suspended) |suspended| {
                // Copy elision... bug?
                const copy = suspended;
                self.suspended = null;
                self.out = null;
                resume copy;
                return self.out;
            }

            return null;
        }
    };
}

const Directive = struct {
    name: []const u8,
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
    comptime var build_directives: [num_exprs]Directive = undefined;

    const State = enum {
        Literal,
        Directive,
    };

    comptime var start_idx = 0;
    comptime var build_idx = 0;

    comptime var state: State = .Literal;

    for (fmt) |c, i| {
        switch (c) {
            '{' => {
                if (state == .Directive) {
                    @compileError("Too many levels of '{' at " ++ i);
                }
                build_literals[build_idx] = fmt[start_idx..i];
                start_idx = i;
                state = .Directive;
            },
            '}' => {
                if (state == .Literal) {
                    @compileError("Unmatched '}' at " ++ i);
                }
                build_directives[build_idx] = .{
                    .name = fmt[start_idx + 1 .. i],
                };
                start_idx = i + 1;
                build_idx += 1;
                state = .Literal;
            },
            else => {},
        }
    }
    if (state == .Directive) {
        @compileError("Unmatched '{' at " ++ start_idx);
    }
    build_literals[build_idx] = fmt[start_idx..];

    return struct {
        const literals = build_literals;
        const directives = build_directives;

        pub fn gen(ctx: *GenContext([]const u8), args: var) void {
            inline for (directives) |dir, i| {
                ctx.out = literals[i];
                ctx.suspended = @frame();
                suspend;

                genDirective(ctx, dir, @field(args, dir.name));
            }
            ctx.out = literals[literals.len - 1];
            ctx.suspended = @frame();
            suspend;
        }

        pub fn genDirective(ctx: *GenContext([]const u8), directive: Directive, value: var) void {
            ctx.out = value;
            ctx.suspended = @frame();
            suspend;
        }

        pub fn countSize(args: var) usize {
            var ctx = GenContext([]const u8){};
            _ = async gen(&ctx, args);

            var result: usize = 0;
            while (ctx.next()) |value| {
                result += value.len;
            }
            return result;
        }

        pub fn bufPrint(buf: []u8, args: var) ![]u8 {
            var ctx = GenContext([]const u8){};
            _ = async gen(&ctx, args);

            var curr: usize = 0;
            while (ctx.next()) |value| {
                if (curr + value.len > buf.len) return error.BufferTooSmall;
                std.mem.copy(u8, buf[curr..], value);
                curr += value.len;
            }

            return buf[0..curr];
        }

        pub fn allocPrint(allocator: *std.mem.Allocator, args: var) ![]u8 {
            const result = try allocator.alloc(u8, countSize(args));
            return bufPrint(result, args) catch |err| switch (err) {
                error.BufferTooSmall => unreachable,
            };
        }
    };
}

test "basic tests" {
    var out_buf: [1000]u8 = undefined;
    {
        const tmpl = Template("hello");

        testing.expectEqual(tmpl.literals.len, 1);
        testing.expectEqual(tmpl.directives.len, 0);
        testing.expectEqualSlices(u8, tmpl.literals[0], "hello");

        const out = try tmpl.bufPrint(&out_buf, .{});
        testing.expectEqualSlices(u8, out, "hello");
    }

    {
        const tmpl = Template("hello{0}world");
        testing.expectEqual(tmpl.literals.len, 2);
        testing.expectEqualSlices(u8, tmpl.literals[0], "hello");
        testing.expectEqualSlices(u8, tmpl.literals[1], "world");
        testing.expectEqual(tmpl.directives.len, 1);
        testing.expectEqualSlices(u8, tmpl.directives[0].name, "0");

        const out1 = try tmpl.bufPrint(&out_buf, .{" "});
        testing.expectEqualSlices(u8, out1, "hello world");

        const out2 = try tmpl.bufPrint(&out_buf, .{"\n"});
        testing.expectEqualSlices(u8, out2, "hello\nworld");
    }

    {
        const tmpl = Template("{hello} {world}");
        testing.expectEqual(tmpl.literals.len, 3);
        testing.expectEqualSlices(u8, tmpl.literals[0], "");
        testing.expectEqualSlices(u8, tmpl.literals[1], " ");
        testing.expectEqualSlices(u8, tmpl.literals[2], "");
        testing.expectEqual(tmpl.directives.len, 2);
        testing.expectEqualSlices(u8, tmpl.directives[0].name, "hello");
        testing.expectEqualSlices(u8, tmpl.directives[1].name, "world");

        const out = try tmpl.bufPrint(&out_buf, .{ .hello = "1", .world = "2" });
        testing.expectEqualSlices(u8, out, "1 2");
    }
}

test "allocPrint" {
    const tmpl = Template("hello{0}world");
    testing.expectEqual(tmpl.literals.len, 2);
    testing.expectEqualSlices(u8, tmpl.literals[0], "hello");
    testing.expectEqualSlices(u8, tmpl.literals[1], "world");
    testing.expectEqual(tmpl.directives.len, 1);
    testing.expectEqualSlices(u8, tmpl.directives[0].name, "0");

    const out1 = try tmpl.allocPrint(std.heap.page_allocator, .{" "});
    defer std.heap.page_allocator.free(out1);
    testing.expectEqualSlices(u8, out1, "hello world");

    const out2 = try tmpl.allocPrint(std.heap.page_allocator, .{"\n"});
    defer std.heap.page_allocator.free(out2);
    testing.expectEqualSlices(u8, out2, "hello\nworld");
}
