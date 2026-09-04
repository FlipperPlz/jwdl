const std = @import("std");
const jwdl = @import("../main.zig").jwdl;
const vxfw = @import("../main.zig").vxfw;

const Allocator = std.mem.Allocator;

const Header = @This();

pub fn widget(self: *Header) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    _ = ptr;
    _ = ctx;
    _ = event;
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Header = @ptrCast(@alignCast(ptr));
    const max_size = ctx.max.size();

    const TITLE = "JWDL";
    const header_text: vxfw.Text = .{
        .text = TITLE,
    };
    const header_surface = try header_text.draw(ctx);

    const text_len: u16 = @intCast(TITLE.len);
    const col = if (max_size.width > text_len) (max_size.width - text_len) / 2 else 0;

    const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
    children[0] = .{
        .origin = .{ .row = 0, .col = col },
        .surface = header_surface,
    };

    return .{
        .size = max_size,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}