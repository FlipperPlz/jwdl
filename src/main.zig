const std = @import("std");
const http = std.http;
pub const jwdl = @import("jwdl");
pub const vaxis = @import("vaxis");
pub const vxfw = vaxis.vxfw;
pub const models = struct {
    pub const Application = @import("models/Application.zig");
    pub const Header = @import("models/Header.zig");
};

test {
    std.testing.refAllDecls(models.Header);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var httpClient = http.Client { .allocator = gpa, .io = io };
    defer httpClient.deinit();

    var apiClient = jwdl.Client.init(gpa, io, &httpClient);
    defer apiClient.deinit();

    var buffer: [1024]u8 = undefined;
    var app: vxfw.App = try .init(io, gpa, init.environ_map, &buffer);
    defer app.deinit();

    const model = try models.Application.init(&apiClient, app.allocator);
    defer model.deinit(gpa);

    try app.run(model.widget(), .{});
}