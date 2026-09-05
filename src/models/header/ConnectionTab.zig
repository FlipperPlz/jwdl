const std = @import("std");
const vxfw = @import("../../main.zig").vxfw;
const Dropdown = @import("../../widgets/Dropdown.zig");

const ConnectionTab = @This();

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!*Dropdown {
    return Dropdown.init(allocator, .{
        .title = "Connection",
        .buttons = &.{
            .{
                .title = "Proxy",
                .action = .{
                    .dropdown = .{
                        .title = "Proxy",
                        .buttons = &.{
                            .{
                                .title = "Add Proxy",
                                .action = .{ .on_click = onAddProxyClick },
                            },
                        },
                    },
                },
            },
            .{
                .title = "Change URL",
                .action = .{ .on_click = onChangeApiUrlClick },
            },
        },
    });
}

fn onAddProxyClick(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    _ = ptr;
    ctx.consume_event = true;
    ctx.redraw = true;
}

fn onChangeApiUrlClick(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    _ = ptr;
    ctx.consume_event = true;
    ctx.redraw = true;
}