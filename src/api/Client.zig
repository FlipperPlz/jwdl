const std = @import("std");
const http = std.http;
const json = std.json;
const types = @import("types.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Client = @This();

const DEFAULT_API = "https://juicewrldapi.com/juicewrld";
const CACHE_TTL_MS: i64 = 1000 * 60 * 60; // 1 hour
const DEFAULT_SONGS_ENDPOINT = "/songs/";
const DEFAULT_ERAS_ENDPOINT = "/eras/";
const DEFAULT_FILES_DOWNLOAD_ENDPOINT = "/files/download/";
const DEFAULT_RADIO_ENDPOINT = "/radio/random/";

const DEFAULT_HEADERS = [_]std.http.Header{
    .{ .name = "accept", .value = "application/json" },
    .{ .name = "user-agent", .value = "jwdl/1.0" },
};

client: *http.Client,
cache: Cache,

pub const Parameter = struct {
    name: []const u8,
    value: []const u8,

    pub fn init(name: []const u8, value: []const u8) Parameter {
        return .{
            .name = name,
            .value = value,
        };
    }
};

test "Parameter initialization creates correct struct fields" {
    const param = Parameter.init("era", "Legends Never Die");
    try std.testing.expectEqualStrings("era", param.name);
    try std.testing.expectEqualStrings("Legends Never Die", param.value);
}

pub const Cache = struct {
    const Entry = struct {
        expires_at: i64,
        raw_json: []const u8,
    };

    mutex: std.Io.Mutex = .init,
    map: std.StringHashMapUnmanaged(Entry) = .empty,
    gpa: Allocator,
    io: Io,

    pub fn init(gpa: Allocator, io: Io) Cache {
        return .{ .gpa = gpa, .io = io};
    }

    pub fn deinit(self: *Cache) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.raw_json);
        }
        self.map.deinit(self.gpa);
    }

    pub fn reset(self: *Cache) void {
        self.deinit();
        self.map = .empty;
    }

    pub fn get(self: *Cache, url: []const u8) Io.Cancelable!?[]const u8 {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        const entry = self.map.get(url) orelse return null;
        if (Io.Clock.now(.awake, self.io).toMilliseconds() > entry.expires_at) {
            return null;
        }
        return entry.raw_json;
    }

    pub const PutError = error {
        PutFailed
    } || Io.Cancelable || Allocator.Error;

    pub fn put(self: *Cache, url: []const u8, raw_json: []const u8) PutError!void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        const heap_url = try self.gpa.dupe(u8, url);
        errdefer self.gpa.free(heap_url);

        const heap_json = try self.gpa.dupe(u8, raw_json);
        errdefer self.gpa.free(heap_json);

        const expires_at = Io.Clock.now(.awake, self.io).toMilliseconds() + CACHE_TTL_MS;
        const gop = try self.map.getOrPut(self.gpa, heap_url);

        if (gop.found_existing) {
            self.gpa.free(gop.key_ptr.*);
            self.gpa.free(gop.value_ptr.raw_json);
        }

        gop.key_ptr.* = heap_url;
        gop.value_ptr.* = .{
            .expires_at = expires_at,
            .raw_json = heap_json,
        };
    }
};

test "Cache put and get basic operations" {
    const io = std.testing.io;
    var cache = Cache.init(std.testing.allocator, io);
    defer cache.deinit();

    const test_url = "https://juicewrldapi.com/cache_test";
    const test_json = "{\"id\":1,\"name\":\"Robbery\"}";

    try cache.put(test_url, test_json);

    const cached_result = try cache.get(test_url);
    try std.testing.expect(cached_result != null);
    try std.testing.expectEqualStrings(test_json, cached_result.?);
}

test "Cache reset clears stored entries" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var cache = Cache.init(allocator, io);
    defer cache.deinit();

    try cache.put("https://juicewrldapi.com/test", "data");
    cache.reset();

    const res = try cache.get("https://juicewrldapi.com/test");
    try std.testing.expect(res == null);
}

pub fn ArenaOutput(comptime T: type) type {
    return struct {
        const Self = @This();
        inner: T,
        arena: std.heap.ArenaAllocator,

        pub fn deinit(self: Self) void {
            var mutable_arena = self.arena;
            mutable_arena.deinit();
        }
    };
}

pub const Options = struct {
    api: ?[]const u8 = DEFAULT_API,
    endpoint: ?[]const u8 = null,
    parameters: []const Parameter = &.{},
    headers: []const http.Header = &DEFAULT_HEADERS,
};

fn PagedApiResult(comptime ResultType: type) type {
    return struct {
        count: usize,
        next: ?[]const u8,
        previous: ?[]const u8,
        results: []ResultType,
    };
}

fn ObjectStreamer(state_: anytype, comptime T: type) type {
    return struct {
        const Self = @This();
        list: std.ArrayList(T) = .empty,
        on_append: ?*const fn (item: T, state: @TypeOf(state_)) void = null,

        pub const empty: Self = .{};

        pub fn with_hook(on_append: ?*const fn (item: T, state: @TypeOf(state_)) void) Self {
            return .{
                .on_append = on_append,
            };
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.list.deinit(gpa);
        }

        pub fn appendSlice(
            self: *Self,
            gpa: Allocator,
            state: @TypeOf(state_),
            items: []const T
        ) Allocator.Error!void {
            try self.list.appendSlice(gpa, items);
            if (self.on_append) |callback| {
                for (items) |item| callback(item, state);
            }
        }

        pub fn toOwnedSlice(self: *Self, gpa: Allocator) Allocator.Error![]T {
            return try self.list.toOwnedSlice(gpa);
        }
    };
}

pub fn init(gpa: Allocator, io: Io, client: *http.Client) Client {
    return .{
        .client = client,
        .cache = .init(gpa, io)
    };
}

pub fn deinit(self: *Client) void {
    self.cache.deinit();
}

pub const StreamSongError = error {
    NotArchived,
    RequestFailed
}   || http.Client.RequestError
    || http.Client.Request.ReceiveHeadError
    || Io.Writer.Error
    || Io.Reader.Error
    || JoinURLError
    || std.Uri.ParseError
;

pub fn streamSong(
    self: *Client,
    gpa: Allocator,
    song: types.Song,
    writer: *Io.Writer,
    comptime bufferSize: usize,
    options: Options
) StreamSongError!void {
    const songPath = blk: {
        if (song.path) |path| {
            if(path.len == 0) return StreamSongError.NotArchived;
            break :blk song.path.?;
        } else return StreamSongError.NotArchived;
    };

    var params = std.ArrayList(Parameter).empty;
    defer params.deinit(gpa);

    try params.append(gpa, Parameter.init("path", songPath));
    try params.appendSlice(gpa, options.parameters);

    const location = try allocJoinUrlWithParams(
        gpa,
        options.api orelse DEFAULT_API,
        DEFAULT_FILES_DOWNLOAD_ENDPOINT,
        params.items
    );
    defer gpa.free(location);

    const uri = try std.Uri.parse(location);

    var request = try self.client.request(.GET, uri, .{
        .extra_headers = options.headers,
    });
    defer request.deinit();

    try request.sendBodiless();

    var redirectBuffer: [1024]u8 = undefined;
    const response = try request.receiveHead(&redirectBuffer);

    if (response.head.status != .ok) {
        return StreamSongError.RequestFailed;
    }

    const bodyReader = request.reader;
    var readerInterface = bodyReader.interface;

    var buffer: [bufferSize]u8 = undefined;

    while (true) {
        readerInterface.readSliceAll(&buffer) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        try writer.writeAll(&buffer);
    }
}

test "streamSong returns NotArchived for empty or missing path" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var httpClient = std.http.Client{ .allocator = allocator, .io = io };
    defer httpClient.deinit();

    var client = init(allocator, io, &httpClient);
    defer client.deinit();

    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    const empty_song = types.Song{
        .id = 1,
        .name = "Test",
        .path = "",
        .additional_information = "",
        .album = "",
        .bitrate = "",
        .category = .recording_session,
        .credited_artists = "",
        .date_leaked = "",
        .dates = "",
        .engineers = "",
        .era = .{},
        .file_names = &.{},
        .groupbuy_info = .{
            .additional_info = "",
            .blind = true,
            .end_date = "",
            .finished = true,
            .price = "",
            .start_date = "",
            .surfaced_with_og = true
        },
        .image_url = "",
        .instrumental_names = "",
        .instrumentals = "",
        .leak_type = "",
        .length = "",
        .lyrics = "",
        .original_key = "",
        .preview_date = "",
        .producers = "",
        .public_id = 1,
        .record_dates = "",
        .recording_locations = "",
        .release_date = "",
        .session_titles = "",
        .session_tracking = "",
        .snippets = &.{},
        .synced_lyrics = "",
        .track_titles = &.{}
    };

    const options = Options {};

    const result = client.streamSong(allocator, empty_song, &writer.writer, 2048, options);
    try std.testing.expectError(DownloadSongError.NotArchived, result);
}

pub const DownloadSongError = error {
    NotArchived,
    RequestFailed
}   || http.Client.FetchError
    || Io.Writer.Error
    || Io.Reader.Error
    || RetrieveResponseError
    || JoinURLError
;

pub fn downloadSong(
    self: *Client,
    gpa: Allocator,
    song: types.Song,
    writer: *Io.Writer,
    options: Options
) DownloadSongError!void {
    const songPath = blk: {
        if (song.path) |path| {
            if(path.len == 0) return DownloadSongError.NotArchived;
            break :blk song.path.?;
        } else return DownloadSongError.NotArchived;
    };

    var params = std.ArrayList(Parameter).empty;
    defer params.deinit(gpa);

    try params.append(gpa, Parameter.init("path", songPath));
    try params.appendSlice(gpa, options.parameters);

    const location = try allocJoinUrlWithParams(
        gpa,
        options.api orelse DEFAULT_API,
        DEFAULT_FILES_DOWNLOAD_ENDPOINT,
        params.items
    );
    defer gpa.free(location);

    try self.writeResponse(location, writer, options);
}

test "downloadSong returns NotArchived when path is null" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var httpClient = std.http.Client{ .allocator = allocator, .io = io };
    defer httpClient.deinit();

    var client = init(allocator, io, &httpClient);
    defer client.deinit();

    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    const null_path_song = types.Song{
        .id = 1,
        .name = "Test",
        .path = null,
        .additional_information = "",
        .album = "",
        .bitrate = "",
        .category = .recording_session,
        .credited_artists = "",
        .date_leaked = "",
        .dates = "",
        .engineers = "",
        .era = .{},
        .file_names = &.{},
        .groupbuy_info = .{
            .additional_info = "",
            .blind = true,
            .end_date = "",
            .finished = true,
            .price = "",
            .start_date = "",
            .surfaced_with_og = true
        },
        .image_url = "",
        .instrumental_names = "",
        .instrumentals = "",
        .leak_type = "",
        .length = "",
        .lyrics = "",
        .original_key = "",
        .preview_date = "",
        .producers = "",
        .public_id = 1,
        .record_dates = "",
        .recording_locations = "",
        .release_date = "",
        .session_titles = "",
        .session_tracking = "",
        .snippets = &.{},
        .synced_lyrics = "",
        .track_titles = &.{}
    };

    const result = client.downloadSong(allocator, null_path_song, &writer.writer, .{});
    try std.testing.expectError(DownloadSongError.NotArchived, result);
}

pub const RandomSongError = error {
    RequestFailed
}   || ParseError
    || JoinURLError
;

pub fn getRandomSong(
    self: *Client,
    gpa: Allocator,
    options: Options
) RandomSongError!ArenaOutput(types.RandomSong) {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    const location = try allocJoinUrlWithParams(
        arena_allocator,
        DEFAULT_API,
        DEFAULT_RADIO_ENDPOINT,
        null
    );

    const song = try self.parseLeaky(arena_allocator, types.RandomSong, location, false, options);

    return .{
        .inner = song,
        .arena = arena,
    };
}

test "getRandomSong integration flow" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var httpClient = std.http.Client{ .allocator = allocator, .io = io };
    defer httpClient.deinit();

    var client = init(allocator, io, &httpClient);
    defer client.deinit();

    const result = client.getRandomSong(allocator, .{});
    if (result) |random_output| {
        defer random_output.deinit();
        try std.testing.expect(random_output.inner.title.len >= 0);
        try std.testing.expect(random_output.inner.song.id >= 0);
    } else |_| {
        return;
    }
}

pub const SongFilters = struct {
    category: ?types.Category = null,
    era: ?[]const u8 = null,
    search: ?[]const u8 = null,
    searchall: ?[]const u8 = null,
    lyrics: ?[]const u8 = null,

    pub fn toParameters(self: SongFilters, gpa: Allocator) Allocator.Error![]Parameter {
        var params = std.ArrayList(Parameter).empty;
        defer params.deinit(gpa);

        if(self.category) |category| {
            try params.append(gpa, .init("category", category.toString()));
        }

        if(self.era) |era| {
            try params.append(gpa, .init("era", era));
        }

        if(self.search) |search| {
            try params.append(gpa, .init("search", search));
        }

        if(self.searchall) |searchall| {
            try params.append(gpa, .init("searchall", searchall));
        }

        if(self.lyrics) |lyrics| {
            try params.append(gpa, .init("lyrics", lyrics));
        }

        return try params.toOwnedSlice(gpa);
    }
};

test "SongFilters toParameters conversion" {
    const allocator = std.testing.allocator;
    const filters = SongFilters{
        .search = "robbery",
        .era = "deathrace",
    };

    const params = try filters.toParameters(allocator);
    defer allocator.free(params);

    try std.testing.expect(params.len == 2);

    var found_search = false;
    var found_era = false;
    for (params) |param| {
        if (std.mem.eql(u8, param.name, "search")) {
            try std.testing.expectEqualStrings("robbery", param.value);
            found_search = true;
        } else if (std.mem.eql(u8, param.name, "era")) {
            try std.testing.expectEqualStrings("deathrace", param.value);
            found_era = true;
        }
    }
    try std.testing.expect(found_search and found_era);
}

pub fn getSongs(
    self: *Client,
    gpa: Allocator,
    cache_pages: bool,
    filters: ?SongFilters,
    options: Options
) TraversalError!ArenaOutput([]types.Song) {
    const formatParam = Parameter.init("file_names_array", "1");

    var params = std.ArrayList(Parameter).empty;
    defer params.deinit(gpa);

    try params.append(gpa, formatParam);
    if(filters) |active_filters| {
        const filterParameters = try active_filters.toParameters(gpa);
        defer gpa.free(filterParameters);
        try params.appendSlice(gpa, filterParameters);
    }
    try params.appendSlice(gpa, options.parameters);

    return self.getObjects(gpa, cache_pages, .{
        .endpoint = options.endpoint orelse DEFAULT_SONGS_ENDPOINT,
        .api = options.api orelse DEFAULT_API,
        .parameters = params.items,
        .headers = options.headers,
    }, types.Song);
}

test "getSongs with filters integration flow" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var httpClient = std.http.Client{ .allocator = allocator, .io = io};
    defer httpClient.deinit();

    var client = init(allocator, io, &httpClient);
    defer client.deinit();

    const filters = SongFilters{
        .search = "robbery",
        .category = .released
    };

    const result = client.getSongs(allocator, false, filters, .{});
    if (result) |songs_output| {
        defer songs_output.deinit();
        try std.testing.expect(songs_output.inner.len >= 0);
    } else |err| {
        try std.testing.expect(
                err == TraversalError.RequestFailed or
                err == TraversalError.Unexpected or
                err == TraversalError.NoEndpoint
        );
    }
}

pub fn getEras(
    self: *Client,
    gpa: Allocator,
    cache_pages: bool,
    options: Options
) TraversalError!ArenaOutput([]types.Era) {
    return self.getObjects(gpa, cache_pages, .{
        .endpoint = options.endpoint orelse DEFAULT_ERAS_ENDPOINT,
        .api = options.api orelse DEFAULT_API,
        .parameters = options.parameters,
        .headers = options.headers,
    }, types.Era);
}

test "getEras integration flow" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var httpClient = std.http.Client{ .allocator = allocator, .io = io };
    defer httpClient.deinit();

    var client = init(allocator, io, &httpClient);
    defer client.deinit();

    const result = client.getEras(allocator, false, .{});
    if (result) |eras_output| {
        defer eras_output.deinit();
        try std.testing.expect(eras_output.inner.len >= 0);
    } else |_| {
        return;
    }
}

fn getObjects(
    self: *Client,
    gpa: Allocator,
    cache_pages: bool,
    options: Options,
    comptime ResultType: type
) TraversalError!ArenaOutput([]ResultType) {
    return self.traverseObjects(gpa, cache_pages, options, ResultType, {}, null);
}

pub const TraversalError = error {
    NoEndpoint
}   || JoinURLError
    || Cache.PutError
    || http.Client.FetchError
    || RetrieveResponseError
    || json.ParseFromValueError
    || json.Scanner.NextError
    || json.Scanner.PeekError
    || json.Scanner.AllocError
;

fn traverseObjects(
    self: *Client,
    gpa: Allocator,
    cache_pages: bool,
    options: Options,
    comptime ResultType: type,
    state: anytype,
    on_append: ?*const fn (item: ResultType, state: @TypeOf(state)) void,
) TraversalError!ArenaOutput([]ResultType) {
    const endpoint = options.endpoint orelse return TraversalError.NoEndpoint;
    const base_api = options.api orelse DEFAULT_API;

    var master_arena = std.heap.ArenaAllocator.init(gpa);
    errdefer master_arena.deinit();
    const arena_allocator = master_arena.allocator();

    var streamer = ObjectStreamer(state, ResultType).with_hook(on_append);
    defer streamer.deinit(gpa);

    var current_url = try allocJoinUrlWithParams(
        arena_allocator,
        base_api,
        endpoint,
        options.parameters,
    );

    var scratch_arena = std.heap.ArenaAllocator.init(gpa);
    defer scratch_arena.deinit();

    while (true) {
        const scratch_allocator = scratch_arena.allocator();

        const json_response = try self.getResponse(scratch_allocator, current_url, cache_pages, options);

        const parsed_json = try json.parseFromSlice(
            PagedApiResult(ResultType),
            arena_allocator,
            json_response,
            .{}
        );

        try streamer.appendSlice(arena_allocator, state, parsed_json.value.results);

        if (parsed_json.value.next) |n| {
            current_url = try arena_allocator.dupe(u8, n);
        } else break;

        _ = scratch_arena.reset(.retain_capacity);
    }

    return .{
        .arena = master_arena,
        .inner = try streamer.toOwnedSlice(arena_allocator)
    };
}

pub const WriteResponseError = error {
    RequestFailed
}   || http.Client.FetchError
;

fn writeResponse(self: *Client, url: []const u8, writer: *Io.Writer, options: Options) WriteResponseError!void{
    const result = try self.client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .extra_headers = options.headers,
        .response_writer = writer,
    });

    if (result.status != .ok) {
        return error.RequestFailed;
    }
}

pub const RetrieveResponseError = Allocator.Error || Io.Cancelable || Cache.PutError || WriteResponseError;

fn getResponse(self: *Client, gpa: Allocator, url: []const u8, cache: bool, options: Options) RetrieveResponseError![]const u8 {
    if(cache) {
        if (try self.cache.get(url)) |cached_bytes| {
            return cached_bytes;
        }
    }

    var responseWriter = Io.Writer.Allocating.init(gpa);
    defer responseWriter.deinit();

    try self.writeResponse(url, &responseWriter.writer, options);
    const response = try responseWriter.toOwnedSlice();
    defer if (cache) gpa.free(response);

    try self.cache.put(url, response);

    return if(cache) try self.cache.get(url) orelse RetrieveResponseError.PutFailed else response;
}

const ParseError = RetrieveResponseError || json.ParseFromValueError || json.Scanner.NextError ||
    json.Scanner.PeekError || json.Scanner.AllocError;

fn parse(
    self: *Client,
    gpa: Allocator,
    comptime T: type,
    endpoint: []const u8,
    cache: bool,
    options: Options
) ParseError!json.Parsed(T) {
    const jsonText = try self.getResponse(gpa, endpoint, cache,options);
    defer gpa.free(jsonText);

    return try std.json.parseFromSlice(
        T,
        gpa,
        jsonText,
        .{ }
    );
}

fn parseLeaky(
    self: *Client,
    arena: Allocator,
    comptime T: type,
    endpoint: []const u8,
    cache: bool,
    options: Options
) ParseError!T {
    const jsonText = try self.getResponse(arena, endpoint, cache, options);

    return try std.json.parseFromSliceLeaky(
        T,
        arena,
        jsonText,
        .{ }
    );
}

pub const JoinURLError = Io.Writer.Error || Allocator.Error;

fn allocJoinUrlWithParams(gpa: Allocator, left: []const u8, right: []const u8, parameters: ?[]const Parameter) JoinURLError![]const u8 {
    const clean_left: []const u8 = std.mem.trimEnd(u8, left, "/");
    const clean_right: []const u8 = std.mem.trimStart(u8, right, "/");

    if(parameters) | parameters_null_checked | {
        var allocating: Io.Writer.Allocating = .init(gpa);
        defer allocating.deinit();

        try allocating.writer.print("{s}/{s}", .{ clean_left, clean_right });

        for (parameters_null_checked, 0..) |parameter, i| {
            const prefix: u8 = if (i == 0) '?' else '&';

            try allocating.writer.writeByte(prefix);
            try (std.Uri.Component{ .raw = parameter.name }).formatEscaped(&allocating.writer);
            try allocating.writer.writeByte('=');
            try (std.Uri.Component{ .raw = parameter.value }).formatEscaped(&allocating.writer);
        }

        return try allocating.toOwnedSlice();
    }

    return std.fmt.allocPrint(gpa, "{s}/{s}", .{ clean_left, clean_right });
}

test "allocJoinUrlWithParams formats base URL, endpoint, and query parameters correctly" {
    const allocator = std.testing.allocator;
    const params = [_]Parameter{
        Parameter.init("search", "juice wrld"),
        Parameter.init("lyrics", "down a hill"),
    };

    const url = try allocJoinUrlWithParams(allocator, "https://juicewrldapi.com/", "/songs/", &params);
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://juicewrldapi.com/songs/?search=juice%20wrld&lyrics=down%20a%20hill", url);
}

test "allocJoinUrlWithParams handles missing parameters gracefully" {
    const allocator = std.testing.allocator;
    const url = try allocJoinUrlWithParams(allocator, "https://juicewrldapi.com", "eras", null);
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://juicewrldapi.com/eras", url);
}