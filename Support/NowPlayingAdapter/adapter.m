// What the system says is playing, for MycSs (spec 014, ADR 008).
//
// MediaRemote is closed to third-party apps since macOS 15.4, but not to the
// system's own binaries: this library is loaded by /usr/bin/perl, which is allowed,
// and runs inside it. It prints one JSON line about every 300 ms with what plays
// and who plays it, and reads commands from its standard input. When the input
// closes (MycSs quit) it ends.
//
// Build:  clang -dynamiclib -fobjc-arc -framework Foundation adapter.m -o libMycSsNowPlaying.dylib
// Run:    /usr/bin/perl -e 'use DynaLoader; ...dl_find_symbol($h, "adapter_stream")...'
//
// Commands, one per line: play, pause, toggle, next, previous, seek <seconds>.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (^InfoBlock)(CFDictionaryRef);
typedef void (^ObjectBlock)(id);
typedef void (^BoolBlock)(BOOL);

static void (*GetInfo)(dispatch_queue_t, InfoBlock);
static void (*GetDisplayID)(dispatch_queue_t, ObjectBlock);
static void (*GetIsPlaying)(dispatch_queue_t, BoolBlock);
static Boolean (*SendCommand)(int, CFDictionaryRef);
static void (*SetElapsed)(double);

static double number(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
}

static NSString *text(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static void handle(NSString *line) {
    NSString *command = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // kMRPlay 0, kMRPause 1, kMRTogglePlayPause 2, kMRNextTrack 4, kMRPreviousTrack 5.
    if ([command isEqualToString:@"play"]) SendCommand(0, NULL);
    else if ([command isEqualToString:@"pause"]) SendCommand(1, NULL);
    else if ([command isEqualToString:@"toggle"]) SendCommand(2, NULL);
    else if ([command isEqualToString:@"next"]) SendCommand(4, NULL);
    else if ([command isEqualToString:@"previous"]) SendCommand(5, NULL);
    else if ([command hasPrefix:@"seek "]) SetElapsed([[command substringFromIndex:5] doubleValue]);
}

void adapter_stream(void *perl, void *cv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        void *handle_ = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (handle_) {
            GetInfo = dlsym(handle_, "MRMediaRemoteGetNowPlayingInfo");
            GetDisplayID = dlsym(handle_, "MRMediaRemoteGetNowPlayingApplicationDisplayID");
            GetIsPlaying = dlsym(handle_, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
            SendCommand = dlsym(handle_, "MRMediaRemoteSendCommand");
            SetElapsed = dlsym(handle_, "MRMediaRemoteSetElapsedTime");
        }
        if (!GetInfo || !GetDisplayID || !GetIsPlaying || !SendCommand || !SetElapsed) {
            printf("{\"error\":\"unavailable\"}\n");
            return;
        }

        // Commands, on a thread of their own: reading blocks.
        dispatch_queue_t reader = dispatch_queue_create("mycss.reader", DISPATCH_QUEUE_SERIAL);
        dispatch_async(reader, ^{
            char buffer[256];
            while (fgets(buffer, sizeof buffer, stdin)) handle([NSString stringWithUTF8String:buffer] ?: @"");
            exit(0);   // MycSs closed the pipe.
        });

        dispatch_queue_t queue = dispatch_queue_create("mycss.mr", DISPATCH_QUEUE_SERIAL);
        while (1) {
            @autoreleasepool {
                __block NSString *bundle = @"";
                __block BOOL playing = NO;
                __block NSDictionary *info = @{};
                dispatch_semaphore_t done = dispatch_semaphore_create(0);
                GetDisplayID(queue, ^(id value) {
                    bundle = [value isKindOfClass:[NSString class]] ? value : @"";
                    dispatch_semaphore_signal(done);
                });
                dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
                GetIsPlaying(queue, ^(BOOL value) { playing = value; dispatch_semaphore_signal(done); });
                dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
                GetInfo(queue, ^(CFDictionaryRef value) {
                    info = value ? [(__bridge NSDictionary *)value copy] : @{};
                    dispatch_semaphore_signal(done);
                });
                dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));

                NSDate *stamp = [info[@"kMRMediaRemoteNowPlayingInfoTimestamp"] isKindOfClass:[NSDate class]]
                    ? info[@"kMRMediaRemoteNowPlayingInfoTimestamp"] : [NSDate date];
                NSDictionary *line = @{
                    @"b": bundle,
                    @"p": @(playing),
                    @"ti": text(info, @"kMRMediaRemoteNowPlayingInfoTitle"),
                    @"ar": text(info, @"kMRMediaRemoteNowPlayingInfoArtist"),
                    @"al": text(info, @"kMRMediaRemoteNowPlayingInfoAlbum"),
                    @"t": @(number(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime")),
                    @"d": @(number(info, @"kMRMediaRemoteNowPlayingInfoDuration")),
                    @"r": @(number(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate")),
                    @"ts": @([stamp timeIntervalSince1970]),
                };
                NSData *json = [NSJSONSerialization dataWithJSONObject:line options:0 error:nil];
                if (json) {
                    fwrite(json.bytes, 1, json.length, stdout);
                    fputc('\n', stdout);
                    fflush(stdout);
                }
            }
            usleep(300 * 1000);
            if (feof(stdout) || ferror(stdout)) exit(0);
        }
    }
}
