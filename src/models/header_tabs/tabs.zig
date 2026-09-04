const std = @import("std");
const vxfw = @import("../../main.zig").vxfw;
const vaxis = @import("../../main.zig").vaxis;

// Add Tab struct to add tab
pub const TabList = struct {
    pub const ConnectionTab = @import("ConnectionTab.zig");
    pub const DownloadTab = @import("DownloadTab.zig");
    pub const SongsPageTab = @import("SongsPageTab.zig");
    pub const DownloadsPageTab = @import("DownloadsPageTab.zig");
};

pub const ITab = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    is_open: bool = false,
    click_pos: ?vxfw.Point = null,
    title: ?[]const u8 = null,

    pub const VTable = struct {
        tabDrawFn: *const fn(*anyopaque, vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface = Defaults.tabDraw,
        tabEventHandlerFn: *const fn(*anyopaque, *vxfw.EventContext, vxfw.Event) anyerror!void = Defaults.tabEventHandler,
        tabContentDrawFn: *const fn(*anyopaque, vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface,
        getShortcutKeyFn: *const fn(*anyopaque, std.mem.Allocator) std.mem.Allocator.Error!u8 = Defaults.getShortcutKey,
        titleDrawFn:  *const fn(*anyopaque, vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface = Defaults.titleDraw,
        openFn: *const fn(*anyopaque, ?vxfw.Point) void = Defaults.open,
        closeFn: *const fn(*anyopaque) void = Defaults.close,
        toggleFn: *const fn(*anyopaque, ?vxfw.Point) bool = Defaults.toggle,
        getTitleFn: *const fn(*anyopaque, std.mem.Allocator) std.mem.Allocator.Error![]const u8 = Defaults.getTitle,
        computeTitleTextFn: *const fn(*anyopaque, std.mem.Allocator) std.mem.Allocator.Error![]const u8 = getStructTitle,
        destroyFn: ?*const fn(*anyopaque, std.mem.Allocator) void,
    };

    pub fn createVTable(comptime T: type, comptime custom_vtable: ITab.VTable) ITab.VTable {
        return .{
            .tabDrawFn = custom_vtable.tabDrawFn,
            .tabEventHandlerFn = custom_vtable.tabEventHandlerFn,
            .tabContentDrawFn = custom_vtable.tabContentDrawFn,
            .getShortcutKeyFn = custom_vtable.getShortcutKeyFn,
            .titleDrawFn = custom_vtable.titleDrawFn,
            .openFn = custom_vtable.openFn,
            .closeFn = custom_vtable.closeFn,
            .toggleFn = custom_vtable.toggleFn,
            .getTitleFn = custom_vtable.getTitleFn,
            .computeTitleTextFn = struct {
                pub fn computeTitleText(_: *anyopaque, arena: std.mem.Allocator) ![]const u8 {
                    const name = @typeName(T);
                    return titleFromName(arena, name);
                }
            }.computeTitleText,
            .destroyFn = custom_vtable.destroyFn orelse struct {
                pub fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(T, "deinit")) {
                        self.deinit(allocator);
                    }
                    allocator.destroy(self);
                }
            }.destroy,
        };
    }

    pub fn widget(self: *ITab) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = tabEventHandler,
            .drawFn = tabDraw,
        };
    }

    pub fn destroy(self: *ITab, allocator: std.mem.Allocator) void {
        if (self.vtable.destroyFn) |destroy_fn| {
            destroy_fn(self.ptr, allocator);
        }
    }

    pub fn tabContentDraw(self: *ITab, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        return self.vtable.tabContentDrawFn(self.ptr, ctx);
    }

    pub fn tabDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *ITab = @ptrCast(@alignCast(ptr));
        return self.vtable.tabDrawFn(self, ctx);
    }

    pub fn titleDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *ITab = @ptrCast(@alignCast(ptr));
        return self.vtable.titleDrawFn(self, ctx);
    }

    pub fn tabEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *ITab = @ptrCast(@alignCast(ptr));
        return self.vtable.tabEventHandlerFn(self, ctx, event);
    }

    pub fn computeTitleText(self: *ITab, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        return self.vtable.computeTitleTextFn(self.ptr, allocator);
    }

    pub fn open(self: *ITab, point: ?vxfw.Point) void {
        self.vtable.openFn(self, point);
    }

    pub fn close(self: *ITab) void {
        self.vtable.closeFn(self);
    }

    pub fn toggle(self: *ITab, point: ?vxfw.Point) bool {
        return self.vtable.toggleFn(self, point);
    }

    pub fn getShortcutKey(self: *ITab, allocator: std.mem.Allocator) std.mem.Allocator.Error!u8 {
        return self.vtable.getShortcutKeyFn(self, allocator);
    }

    pub fn getTitle(self: *ITab, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        return self.vtable.getTitleFn(self, allocator);
    }

    const Defaults = struct {
        pub fn toggle(ptr: *anyopaque, point: ?vxfw.Point) bool {
            const self: *ITab = @ptrCast(@alignCast(ptr));
            self.is_open = !self.is_open;
            self.click_pos = if (self.is_open) point else null;
            return self.is_open;
        }

        pub fn open(ptr: *anyopaque, point: ?vxfw.Point) void {
            const self: *ITab = @ptrCast(@alignCast(ptr));
            self.is_open = true;
            self.click_pos = point;
        }

        pub fn close(ptr: *anyopaque) void {
            const self: *ITab = @ptrCast(@alignCast(ptr));
            self.is_open = false;
            self.click_pos = null;
        }

        pub fn getShortcutKey(ptr: *anyopaque, allocator: std.mem.Allocator) std.mem.Allocator.Error!u8 {
            const self: *ITab = @ptrCast(@alignCast(ptr));
            return std.ascii.toLower((try self.getTitle(allocator))[0]);
        }

        pub fn tabEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
            const self: *ITab = @ptrCast(@alignCast(ptr));

            switch (event) {
                .key_press => |key| {
                    if (key.matches(@intCast(try self.getShortcutKey(ctx.alloc)), .{ .alt = true })) {
                        _ = self.toggle(null);
                        ctx.consume_event = true;
                        ctx.redraw = true;
                    }
                },
                else => {},
            }
        }

        pub fn tabDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
            const self: *ITab = @ptrCast(@alignCast(ptr));
            var title_surf: vxfw.Surface = try self.vtable.titleDrawFn(self, ctx);

            title_surf.widget = self.widget();

            if (!self.is_open) {
                return title_surf;
            }
            const content_surf = try self.tabContentDraw(ctx);

            const drop_col: u16 = if (self.click_pos) |pos| pos.col else 0;
            const drop_row: u16 = if (self.click_pos) |pos| pos.row + 1 else title_surf.size.height;

            const combined_width = @max(title_surf.size.width, drop_col + content_surf.size.width);
            const combined_height = @max(title_surf.size.height, drop_row + content_surf.size.height);

            const buf = try ctx.arena.alloc(vaxis.Cell, combined_width * combined_height);
            @memset(buf, .{
                .char = .{ .grapheme = " ", .width = 1 },
            });

            var children = try ctx.arena.alloc(vxfw.SubSurface, 2);
            children[0] = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = title_surf,
                .z_index = 0,
            };
            children[1] = .{
                .origin = .{ .row = @intCast(drop_row), .col = @intCast(drop_col) },
                .surface = content_surf,
                .z_index = 1,
            };

            return .{
                .size = .{ .width = combined_width, .height = combined_height },
                .buffer = buf,
                .children = children,
                .widget = self.widget(),
            };
        }

        pub fn getTitle(ptr: *anyopaque, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
            const self: *ITab = @ptrCast(@alignCast(ptr));

            if(self.title) |_title| {
                return _title;
            }

            self.title = try self.computeTitleText(allocator);
            return self.title.?;
        }

        pub fn titleDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
            const self: *ITab = @ptrCast(@alignCast(ptr));
            const _title = try self.getTitle(ctx.arena);
            const formatted_name = try std.fmt.allocPrint(ctx.arena, " {s} ", .{_title});
            const tab_text: vxfw.Text = .{
                .text = formatted_name,
            };

            const text_widget = tab_text.widget();

            return try text_widget.draw(ctx);
        }
    };
};

pub fn getStructFirstChar(ptr: *anyopaque, arena: std.mem.Allocator) u8 {
    _ = arena;
    return std.ascii.toLower(@typeName(@TypeOf(ptr)));
}

pub fn getStructTitle(ptr: *anyopaque, arena: std.mem.Allocator) ![]const u8 {
    const name = @typeName(@TypeOf(ptr));
    const base = if (std.mem.endsWith(u8, name, "Tab")) name[0 .. name.len - 3] else name;

    var extra_spaces: usize = 0;
    for (base, 0..) |c, i| {
        if (i > 0 and std.ascii.isUpper(c)) {
            extra_spaces += 1;
        }
    }

    const result = try arena.alloc(u8, base.len + extra_spaces);
    var dest_idx: usize = 0;
    for (base, 0..) |c, i| {
        if (i > 0 and std.ascii.isUpper(c)) {
            result[dest_idx] = ' ';
            dest_idx += 1;
        }
        result[dest_idx] = c;
        dest_idx += 1;
    }
    return result;
}

pub fn titleFromName(arena: std.mem.Allocator, full_name: []const u8) ![]const u8 {
    const name = if (std.mem.lastIndexOf(u8, full_name, ".")) |idx| full_name[idx + 1 ..] else full_name;
    const base = if (std.mem.endsWith(u8, name, "Tab")) name[0 .. name.len - 3] else name;

    var extra_spaces: usize = 0;
    for (base, 0..) |c, i| {
        if (i > 0 and std.ascii.isUpper(c)) {
            extra_spaces += 1;
        }
    }

    const result = try arena.alloc(u8, base.len + extra_spaces);
    var dest_idx: usize = 0;
    for (base, 0..) |c, i| {
        if (i > 0 and std.ascii.isUpper(c)) {
            result[dest_idx] = ' ';
            dest_idx += 1;
        }
        result[dest_idx] = c;
        dest_idx += 1;
    }
    return result;
}