const std = @import("std");
const jwdl = @import("../main.zig").jwdl;
const vxfw = @import("../main.zig").vxfw;
const ITab = @import("../widgets/Tab.zig");

const Allocator = std.mem.Allocator;

pub const tab_imports = struct {
    pub const ConnectionTab = @import("header/ConnectionTab.zig");
    pub const DownloadTab = @import("header/DownloadTab.zig");
    pub const SongsPageTab = @import("header/SongsPageTab.zig");
    pub const DownloadsPageTab = @import("header/DownloadsPageTab.zig");
};

const Header = @This();

tab_list: []*ITab,

pub fn widget(self: *Header) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = headerEventHandler,
        .drawFn = drawHeader,
    };
}

pub fn init(allocator: Allocator) std.mem.Allocator.Error!*Header {
    const self = try allocator.create(Header);
    const decls = comptime std.meta.declarations(tab_imports);
    const list = try allocator.alloc(*ITab, decls.len);

    inline for (decls, 0..) |decl, i| {
        const TabType = @field(tab_imports, decl.name);
        const tab_ptr = try TabType.init(allocator);
        list[i] = &tab_ptr.interface;
    }

    self.* = .{ .tab_list = list };
    return self;
}

pub fn deinit(self: *Header, allocator: Allocator) void {
    for (self.tab_list) |tab| {
        tab.destroy(allocator);
    }
    allocator.free(self.tab_list);
    allocator.destroy(self);
}

fn headerEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *Header = @ptrCast(@alignCast(ptr));

    switch (event) {
        .mouse => |mouse| {
            if (mouse.button == .left and mouse.type == .press) {
                const draw_title_width: u16 = 4;
                var col: u16 = draw_title_width;

                var clicked_tab: ?*ITab = null;
                var clicked_tab_start: u16 = 0;

                for (self.tab_list, 0..) |tab, i| {
                    if (i > 0) {
                        col += 1;
                    }
                    const title = try tab.getTitle(ctx.alloc);
                    const tab_width: u16 = @intCast(title.len + 2);
                    const tab_start = col;
                    const tab_end = col + tab_width;

                    if (mouse.row == 0 and mouse.col >= tab_start and mouse.col < tab_end) {
                        clicked_tab = tab;
                        clicked_tab_start = tab_start;
                        break;
                    }
                    col += tab_width;
                }

                if (clicked_tab) |tab| {
                    for (self.tab_list) |other_tab| {
                        if (other_tab != tab) {
                            other_tab.close();
                        }
                    }
                    _ = tab.toggle(vxfw.Point{
                        .col = @as(u16, @intCast(mouse.col)) - clicked_tab_start,
                        .row = @intCast(mouse.row),
                    });
                    ctx.consume_event = true;
                    ctx.redraw = true;
                    return;
                } else {
                    var any_open = false;
                    for (self.tab_list) |tab| {
                        if (tab.is_open) {
                            any_open = true;
                            tab.close();
                        }
                    }
                    if (any_open) {
                        ctx.redraw = true;
                    }
                }
            }
        },
        .key_press => |key| {
            for (self.tab_list) |tab| {
                const shortcut = try tab.getShortcutKey(ctx.alloc);
                if (key.matches(@intCast(shortcut), .{ .alt = true })) {
                    for (self.tab_list) |other_tab| {
                        if (other_tab != tab) {
                            other_tab.close();
                        }
                    }
                    _ = tab.toggle(null);
                    ctx.consume_event = true;
                    ctx.redraw = true;
                    return;
                }
            }
        },
        else => {},
    }

    for (self.tab_list) |tab| {
        const w = tab.widget();
        if (w.eventHandler) |handler| {
            try handler(w.userdata, ctx, event);
            if (ctx.consume_event) return;
        }
    }
}

pub fn drawHeader(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Header = @ptrCast(@alignCast(ptr));
    const max_size = ctx.max.size();
    
    const num_separators = if (self.tab_list.len > 1) self.tab_list.len - 1 else 0;
    const children = try ctx.arena.alloc(vxfw.SubSurface, 1 + self.tab_list.len + num_separators);
    const draw_title = try drawTitle(ctx);
    children[0] = .{
        .origin = .{ .row = 0, .col = 0 },
        .surface = draw_title.surface,
    };

    try self.drawTabs(ctx, .{
        .state = @ptrCast(self),
        .sub_surfaces = children,
        .index = 1,
        .col = @intCast(draw_title.width),
        .row = 0,
    });

    return .{
        .size = max_size,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}

const AppendTabContext = struct {
    tab: ITab = undefined,
    state: *anyopaque,
    sub_surfaces: []vxfw.SubSurface,
    index: usize = 0,
    col: i17,
    row: i17,
};

pub fn drawTabs(self: *Header, ctx: vxfw.DrawContext, base_state: AppendTabContext) std.mem.Allocator.Error!void {
    var append_ctx = AppendTabContext{
        .col = base_state.col,
        .state = base_state.state,
        .index = base_state.index,
        .row = base_state.row,
        .sub_surfaces = base_state.sub_surfaces,
    };

    for (self.tab_list, 0..) |itab, i| {
        if (i > 0) {
            const sep_text: vxfw.Text = .{ .text = "|" };
            const sep_surf = try sep_text.draw(ctx);
            append_ctx.sub_surfaces[append_ctx.index] = .{
                .origin = .{ .row = append_ctx.row, .col = append_ctx.col },
                .surface = sep_surf,
            };
            append_ctx.index += 1;
            append_ctx.col += 1;
        }

        const itab_widget = itab.widget();
        const itab_surface = try itab_widget.draw(ctx);

        const sub_surface = vxfw.SubSurface{
            .origin = .{ .row = append_ctx.row, .col = append_ctx.col },
            .surface = itab_surface,
        };

        append_ctx.sub_surfaces[append_ctx.index] = sub_surface;
        append_ctx.index += 1;

        const title = try itab.getTitle(ctx.arena);
        const title_width: u16 = @intCast(title.len + 2);
        append_ctx.col += @intCast(title_width);
    }
}

fn drawTitle(ctx: vxfw.DrawContext) std.mem.Allocator.Error!struct {surface: vxfw.Surface, width: usize} {
    const title_text: vxfw.Text = .{
        .text = "JWDL |",
    };
    const width = ctx.stringWidth("JWDL |");
    return .{
        .surface = try title_text.draw(ctx),
        .width = width,
    };
}
