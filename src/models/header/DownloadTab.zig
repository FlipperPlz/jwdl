const std = @import("std");
const vxfw = @import("../../main.zig").vxfw;
const Dropdown = @import("../../widgets/Dropdown.zig");

const DownloadTab = @This();

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!*Dropdown {
    return Dropdown.init(allocator, .{
        .title = "Download",
        .buttons = &.{
            .{
                .title = "Download All",
                .action = .{ .on_click = onDownloadAllClick },
            },
        },
    });
}

fn onDownloadAllClick(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    _ = ptr;
    ctx.consume_event = true;
    ctx.redraw = true;
}
