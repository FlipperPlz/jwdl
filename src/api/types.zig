const std = @import("std");

pub const Era = struct {
    id: ?i64 = null,
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    time_frame: ?[]const u8 = null,
    play_count: ?i64 = null,

    // pub fn deinit(self: *const Era, gpa: std.mem.Allocator) void {
    //     if(self.name) |name| gpa.free(name);
    //     if(self.description) |description| gpa.free(description);
    //     if(self.time_frame) |time_frame| gpa.free(time_frame);
    // }
};

pub const Category = enum {
    recording_session,
    released,
    unreleased,
    unsurfaced,

    pub fn toString(self: Category) []const u8 {
        return @tagName(self);
    }
};

pub const RandomSong = struct {
    id: []const u8,
    title: []const u8,
    path: []const u8,
    size: usize,
    modified: []const u8,
    hash: []const u8,
    song: Song,

    // pub fn deinit(self: *const RandomSong, gpa: std.mem.Allocator) void {
    //     gpa.free(self.id);
    //     gpa.free(self.title);
    //     gpa.free(self.path);
    //     gpa.free(self.modified);
    //     gpa.free(self.hash);
    //     self.song.deinit(gpa);
    // }
};

pub const GroupbuyInfo = struct {
    additional_info: []const u8,
    price: []const u8,
    start_date: []const u8,
    end_date: []const u8,
    blind: bool,
    finished: bool,
    surfaced_with_og: bool,

    // pub fn deinit(self: *const GroupbuyInfo, gpa: std.mem.Allocator) void {
    //     gpa.free(self.additional_info);
    //     gpa.free(self.price);
    //     gpa.free(self.start_date);
    //     gpa.free(self.end_date);
    // }
};

pub const Song = struct {
    id: i64,
    public_id: i64,
    name: []const u8,
    original_key: []const u8,
    category: Category,
    path: ?[]const u8,
    era: Era,
    track_titles: []const []const u8,
    credited_artists: []const u8,
    producers: []const u8,
    engineers: []const u8,
    recording_locations: []const u8,
    record_dates: []const u8,
    length: []const u8,
    bitrate: []const u8,
    additional_information: []const u8,
    file_names: [] const []const u8,
    instrumentals: []const u8,
    preview_date: []const u8,
    release_date: []const u8,
    dates: []const u8,
    session_titles: []const u8,
    session_tracking: []const u8,
    instrumental_names: []const u8,
    groupbuy_info: GroupbuyInfo,
    lyrics: []const u8,
    synced_lyrics: []const u8,
    album: []const u8,
    snippets: []const []const u8,
    date_leaked: []const u8,
    leak_type: []const u8,
    image_url: []const u8,


    pub fn canDownload(self: Song) bool {
        if(self.path) | path | {
            const trimmed = std.mem.trim(u8, path, &std.ascii.whitespace);
            return trimmed.len != 0;
        }
        return false;
    }

    pub fn wasGroupBought(self: Song) bool {
        return self.groupbuy_info.finished;
    }

    // pub fn deinit(self: *const Song, gpa: std.mem.Allocator) void {
    //     gpa.free(self.name);
    //     if(self.path) |path| gpa.free(path);
    //     gpa.free(self.original_key);
    //     self.era.deinit(gpa);
    //     for(self.track_titles) |title| {
    //         gpa.free(title);
    //     }
    //     gpa.free(self.track_titles);
    //     gpa.free(self.credited_artists);
    //     gpa.free(self.producers);
    //     gpa.free(self.engineers);
    //     gpa.free(self.recording_locations);
    //     gpa.free(self.record_dates);
    //     gpa.free(self.length);
    //     gpa.free(self.bitrate);
    //     gpa.free(self.additional_information);
    //     gpa.free(self.file_names);
    //     gpa.free(self.instrumentals);
    //     gpa.free(self.preview_date);
    //     gpa.free(self.release_date);
    //     gpa.free(self.dates);
    //     gpa.free(self.session_titles);
    //     gpa.free(self.session_tracking);
    //     gpa.free(self.instrumental_names);
    //     self.groupbuy_info.deinit(gpa);
    //     gpa.free(self.lyrics);
    //     gpa.free(self.synced_lyrics);
    //     gpa.free(self.album);
    //     gpa.free(self.snippets);
    //     gpa.free(self.date_leaked);
    //     gpa.free(self.leak_type);
    //     gpa.free(self.image_url);
    // }
};