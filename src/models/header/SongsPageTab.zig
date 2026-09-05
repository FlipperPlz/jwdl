const std = @import("std");
const vaxis = @import("../../main.zig").vaxis;
const vxfw = @import("../../main.zig").vxfw;
const ITab = @import("../../widgets/Tab.zig");

const SongsPageTab = @This();

pub const vtable = ITab.createVTable(SongsPageTab, .{
    .tabContentDrawFn = tabContentDraw,
    .destroyFn = deinit,
});

interface: ITab = .{
    .ptr = undefined,
    .vtable = &vtable
},

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!*SongsPageTab {
    const t = try allocator.create(SongsPageTab);

    t.* = .{
        .interface = .{
            .ptr = t,
            .vtable = &vtable,
        },
    };
    return t;
}

pub fn deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *SongsPageTab = @ptrCast(@alignCast(ptr));

    if(self.interface.title) |title| allocator.free(title);

    allocator.destroy(self);
}

fn tabContentDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *SongsPageTab = @ptrCast(@alignCast(ptr));
    _ = ctx;

    return .{
        .size = .{ },
        .buffer = &.{},
        .children = &.{},
        .widget = self.interface.widget(),
    };
}
