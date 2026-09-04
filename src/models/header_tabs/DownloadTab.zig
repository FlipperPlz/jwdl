const std = @import("std");
const vaxis = @import("../../main.zig").vaxis;
const vxfw = @import("../../main.zig").vxfw;
const tabs = @import("tabs.zig");

const DownloadTab = @This();

pub const vtable = tabs.ITab.createVTable(DownloadTab, .{
    .tabContentDrawFn = tabContentDraw,
    .destroyFn = deinit,
});

interface: tabs.ITab = .{
    .ptr = undefined,
    .vtable = &vtable
},

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!*DownloadTab {
    const t = try allocator.create(DownloadTab);

    t.* = .{
        .interface = .{
            .ptr = t,
            .vtable = &vtable,
        },
    };
    return t;
}

pub fn deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *DownloadTab = @ptrCast(@alignCast(ptr));

    if(self.interface.title) |title| allocator.free(title);

    allocator.destroy(self);
}

fn tabContentDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *DownloadTab = @ptrCast(@alignCast(ptr));

    const width: u16 = 20;
    const height: u16 = 10;

    const buf = try ctx.arena.alloc(vaxis.Cell, width * height);
    @memset(buf, .{
        .style = .{ .bg = .{ .index = 7 } },
    });

    return .{
        .size = .{ .width = width, .height = height },
        .buffer = buf,
        .children = &.{},
        .widget = self.interface.widget(),
    };
}
