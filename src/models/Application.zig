const std = @import("std");
const jwdl = @import("../main.zig").jwdl;
const vxfw = @import("../main.zig").vxfw;
const Header = @import("Header.zig");

const Allocator = std.mem.Allocator;

const Application = @This();

client: *jwdl.Client,
header: *Header,

pub fn init(client: *jwdl.Client, gpa: Allocator) !*Application {
    const c = try gpa.create(Application);

    c.* = .{
        .client = client,
        .header = try .init(gpa)
    };

    return c;
}

pub fn deinit(self: *Application, gpa: Allocator) void {
    self.header.deinit(gpa);
    gpa.destroy(self);
}

pub fn widget(self: *Application) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *Application = @ptrCast(@alignCast(ptr));

    if(self.header.widget().eventHandler) |fun| {
        try fun(self.header, ctx, event);
        if (ctx.consume_event) return;
    }


    switch (event) {
        .key_press => |key| {
            if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                ctx.quit = true;
                ctx.consume_event = true;
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Application = @ptrCast(@alignCast(ptr));
    const max_size = ctx.max.size();

    const header_surface = try self.header.widget().draw(ctx);

    const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
    children[0] = .{
        .origin = .{ .row = 0, .col = 0 },
        .surface = header_surface,
    };

    return .{
        .size = max_size,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}