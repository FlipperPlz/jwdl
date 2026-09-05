const std = @import("std");
const vxfw = @import("../main.zig").vxfw;
const vaxis = @import("../main.zig").vaxis;

const ITab = @import("Tab.zig");
const Dropdown = @This();

pub const ClickHandler = *const fn (?*anyopaque, ctx: *vxfw.EventContext) anyerror!void;

pub const ButtonStyle = struct {
    default: vaxis.Style = .{ .fg = .{ .index = 0 }, .bg = .{ .index = 7 } },
    mouse_down: vaxis.Style = .{ .fg = .{ .index = 15 }, .bg = .{ .index = 4 } },
    hover: vaxis.Style = .{ .fg = .{ .index = 0 }, .bg = .{ .index = 3 } },
    focus: vaxis.Style = .{ .fg = .{ .index = 15 }, .bg = .{ .index = 5 } },
};

pub const ActionOptions = union(enum) {
    dropdown: Options,
    on_click: ?ClickHandler,
};

pub const ButtonOptions = struct {
    title: []const u8,
    style: ButtonStyle = .{},
    action: ActionOptions,
};

pub const Options = struct {
    title: []const u8,
    buttons: []const ButtonOptions,
};

pub const DropdownButton = struct {
    pub const Action = union(enum) {
        dropdown: *Dropdown,
        on_click: ?ClickHandler,
    };

    dropdown: *Dropdown,
    index: usize,
    title: []const u8,
    style: ButtonStyle = .{},
    action: Action,

    pub fn deinit(self: *DropdownButton, gpa: std.mem.Allocator) void {
        gpa.free(self.title);

        switch (self.action) {
            .dropdown => |submenu| submenu.interface.destroy(gpa),
            .on_click => {},
        }
    }
};

pub const vtable = ITab.createVTable(Dropdown, .{
    .tabContentDrawFn = drawDropdownContent,
    .destroyFn = destroyDropdown,
    .closeFn = closeTab,
    .openFn = openTab,
});

interface: ITab,
buttons: []DropdownButton,
button_widgets: []vxfw.Button,
open_submenu: ?usize = null,

pub fn init(gpa: std.mem.Allocator, options: Options) std.mem.Allocator.Error!*Dropdown {
    const dropdown = try gpa.create(Dropdown);
    errdefer gpa.destroy(dropdown);

    const title = try gpa.dupe(u8, options.title);
    errdefer gpa.free(title);

    const buttons = try gpa.alloc(DropdownButton, options.buttons.len);
    errdefer gpa.free(buttons);

    const button_widgets = try gpa.alloc(vxfw.Button, options.buttons.len);
    errdefer gpa.free(button_widgets);

    var initialized_buttons: usize = 0;
    errdefer for (buttons[0..initialized_buttons]) |*button| button.deinit(gpa);

    dropdown.* = .{
        .interface = .{
            .ptr = dropdown,
            .vtable = &vtable,
            .title = title,
        },
        .buttons = buttons,
        .button_widgets = button_widgets,
        .open_submenu = null,
    };

    for (options.buttons, 0..) |button_options, i| {
        const button_title = try gpa.dupe(u8, button_options.title);
        errdefer gpa.free(button_title);

        const action: DropdownButton.Action = switch (button_options.action) {
            .dropdown => |submenu_options| .{
                .dropdown = try Dropdown.init(gpa, submenu_options),
            },
            .on_click => |handler| .{
                .on_click = handler,
            },
        };

        buttons[i] = .{
            .dropdown = dropdown,
            .index = i,
            .title = button_title,
            .style = button_options.style,
            .action = action,
        };

        button_widgets[i] = .{
            .label = buttons[i].title,
            .onClick = onButtonClick,
            .userdata = &buttons[i],
            .style = .{
                .default = button_options.style.default,
                .mouse_down = button_options.style.mouse_down,
                .hover = button_options.style.hover,
                .focus = button_options.style.focus,
            },
        };

        initialized_buttons += 1;
    }

    return dropdown;
}

fn onButtonClick(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    const btn: *DropdownButton = @ptrCast(@alignCast(ptr orelse return));
    const self = btn.dropdown;

    switch (btn.action) {
        .dropdown => |submenu| {
            if (self.open_submenu) |open_idx| {
                if (open_idx == btn.index) {
                    submenu.close();
                    self.open_submenu = null;
                } else {
                    switch (self.buttons[open_idx].action) {
                        .dropdown => |prev_sub| prev_sub.close(),
                        .on_click => {},
                    }
                    self.open_submenu = btn.index;
                    submenu.open(null);
                }
            } else {
                self.open_submenu = btn.index;
                submenu.open(null);
            }
            ctx.consume_event = true;
            ctx.redraw = true;
        },
        .on_click => |handler| {
            if (self.open_submenu) |open_idx| {
                switch (self.buttons[open_idx].action) {
                    .dropdown => |prev_sub| prev_sub.close(),
                    .on_click => {},
                }
                self.open_submenu = null;
            }
            if (handler) |click_fn| {
                try click_fn(self, ctx);
            } else {
                ctx.consume_event = true;
                ctx.redraw = true;
            }
        },
    }
}

pub fn deinit(self: *Dropdown, allocator: std.mem.Allocator) void {
    if (self.interface.title) |title| allocator.free(title);

    for (self.buttons) |*button| button.deinit(allocator);
    allocator.free(self.buttons);
    allocator.free(self.button_widgets);

    allocator.destroy(self);
}


fn openTab(ptr: *anyopaque, point: ?vxfw.Point) void {
    ITab.Defaults.open(ptr, point);
}

fn closeTab(ptr: *anyopaque) void {
    const itab: *ITab = @ptrCast(@alignCast(ptr));
    const self: *Dropdown = @ptrCast(@alignCast(itab.ptr));
    ITab.Defaults.close(ptr);

    if (self.open_submenu) |open_idx| {
        switch (self.buttons[open_idx].action) {
            .dropdown => |submenu| submenu.close(),
            .on_click => {},
        }
        self.open_submenu = null;
    }
}

fn drawDropdownContent(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Dropdown = @ptrCast(@alignCast(ptr));

    const width: u16 = 20;
    const height: u16 = @as(u16, @intCast(self.button_widgets.len));

    const btn_ctx = ctx.withConstraints(
        .{ .width = 0, .height = 0 },
        .{ .width = width, .height = 1 },
    );

    const button_surfaces = try ctx.arena.alloc(vxfw.Surface, self.button_widgets.len);
    for (self.button_widgets, 0..) |*btn_widget, i| {
        button_surfaces[i] = try btn_widget.widget().draw(btn_ctx);
    }

    if (self.open_submenu) |open_idx| {
        const sub_surf = switch (self.buttons[open_idx].action) {
            .dropdown => |submenu| try submenu.tabContentDraw(ctx),
            .on_click => null,
        };

        if (sub_surf) |submenu_surface| {
            const sub_width = submenu_surface.size.width;
            const sub_height = submenu_surface.size.height;

            const total_width = width + sub_width;
            const total_height = @max(height, @as(u16, @intCast(open_idx)) + sub_height);

            const buf = try ctx.arena.alloc(vaxis.Cell, total_width * total_height);
            @memset(buf, .{
                .style = .{ .bg = .{ .index = 7 } },
            });

            const children = try ctx.arena.alloc(vxfw.SubSurface, self.button_widgets.len + 1);
            for (button_surfaces, 0..) |surf, i| {
                children[i] = .{
                    .origin = .{ .row = @intCast(i), .col = 0 },
                    .surface = surf,
                    .z_index = 0,
                };
            }
            children[self.button_widgets.len] = .{
                .origin = .{ .row = @intCast(open_idx), .col = width },
                .surface = submenu_surface,
                .z_index = 1,
            };

            return .{
                .size = .{ .width = total_width, .height = total_height },
                .buffer = buf,
                .children = children,
                .widget = self.interface.widget(),
            };
        }
    }

    const buf = try ctx.arena.alloc(vaxis.Cell, width * height);
    @memset(buf, .{
        .style = .{ .bg = .{ .index = 7 } },
    });

    const children = try ctx.arena.alloc(vxfw.SubSurface, self.button_widgets.len);
    for (button_surfaces, 0..) |surf, i| {
        children[i] = .{
            .origin = .{ .row = @intCast(i), .col = 0 },
            .surface = surf,
            .z_index = 0,
        };
    }

    return .{
        .size = .{ .width = width, .height = height },
        .buffer = buf,
        .children = children,
        .widget = self.interface.widget(),
    };
}

fn destroyDropdown(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *Dropdown = @ptrCast(@alignCast(ptr));
    self.deinit(allocator);
}

// passthrough
pub fn widget(self: *Dropdown) vxfw.Widget {
    return self.interface.widget();
}

pub fn open(self: *Dropdown, point: ?vxfw.Point) void {
    self.interface.open(point);
}

pub fn close(self: *Dropdown) void {
    self.interface.close();
}

pub fn toggle(self: *Dropdown, point: ?vxfw.Point) bool {
    return self.interface.toggle(point);
}

pub fn getShortcutKey(self: *Dropdown, allocator: std.mem.Allocator) std.mem.Allocator.Error!u8 {
    return self.interface.getShortcutKey(allocator);
}

pub fn tabContentDraw(self: *Dropdown, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    return self.interface.tabContentDraw(ctx);
}
