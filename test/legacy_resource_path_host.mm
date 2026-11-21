#import <Foundation/Foundation.h>
#include "../HostFrameworks/Foundation/LegacyResourcePath.h"
#include "../HostFrameworks/LC32/guest_bootstrap.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

static unsigned failures;

static void check(bool passed, const char *message) {
    if(!passed) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        ++failures;
    }
}

int main() {
    @autoreleasepool {
        char temporary[] = "/tmp/lc32-resource-path-XXXXXX";
        const char *rootBytes = mkdtemp(temporary);
        if(!rootBytes) return 1;
        NSString *root = [NSString stringWithUTF8String:rootBytes];
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *home = [root stringByAppendingPathComponent:@"guest-home"];
        // Match LiveContainer's renamed bundle, not HOME/PLClient.app.
        NSString *bundle = [root stringByAppendingPathComponent:
            @"Applications/com.tencent.game.rhythmmaster.app"];
        check([files createDirectoryAtPath:home withIntermediateDirectories:YES
            attributes:nil error:nil], "create guest home");
        check([files createDirectoryAtPath:bundle withIntermediateDirectories:YES
            attributes:nil error:nil], "create renamed game bundle");
        NSString *infoPath = [bundle stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = @{@"CFBundleIdentifier": @"com.tencent.game.rhythmmaster",
            @"CFBundleExecutable": @"PLClient"};
        check([info writeToURL:[NSURL fileURLWithPath:infoPath] error:nil],
            "write game identity");
        NSString *executable = [bundle stringByAppendingPathComponent:@"PLClient"];
        check([files createFileAtPath:executable contents:[NSData data]
            attributes:nil], "create guest executable");
        NSString *marker = [bundle stringByAppendingPathComponent:@"GameCfg.xml"];
        NSData *markerData = [@"test-resource" dataUsingEncoding:NSUTF8StringEncoding];
        check([markerData writeToFile:marker atomically:YES], "write resource");

        const char literal[] = "PLClient.app/";
        char snapshot[sizeof(literal)];
        std::memcpy(snapshot, literal, sizeof(literal));
        NSString *broken = [[NSString alloc] initWithBytes:literal
            length:sizeof(literal) encoding:NSASCIIStringEncoding];
        check([home stringByAppendingPathComponent:broken] == nil,
            "reproduce original embedded-NUL path failure");
        auto length = [&](std::uint32_t flags, const void *bytes,
                          std::size_t count, const char *path) {
            return LC32LegacyResourcePathConstantLength(flags, bytes, count, path);
        };
        const char *path = executable.fileSystemRepresentation;
        check(length(0x7c8, literal, sizeof(literal), path) == 13,
            "correct matching Rhythm Master constant");
        check(length(0x7c8, literal, 13, path) == 13,
            "preserve already valid literal");
        check(length(0x7d8, literal, sizeof(literal), path) == 14,
            "preserve UTF-16 constants");
        check(length(0x7c8, literal, sizeof(literal), nullptr) == 14,
            "preserve pre-launch constants");
        check(length(0x7c8, literal, sizeof(literal), "PLClient") == 14,
            "reject unconfigured relative executable path");
        check(length(0x7c8, nullptr, 14, path) == 14,
            "preserve missing byte buffer");
        const char unrelated[] = "unrelated.app";
        static_assert(sizeof(unrelated) == sizeof(literal));
        check(length(0x7c8, unrelated, sizeof(unrelated), path) == 14,
            "preserve other embedded-NUL strings");
        check(length(0x7c8, literal, sizeof(literal),
            [bundle stringByAppendingPathComponent:@"OtherGame"].fileSystemRepresentation) == 14,
            "preserve other executable names");

        NSString *otherBundle = [root stringByAppendingPathComponent:@"Other.app"];
        check([files createDirectoryAtPath:otherBundle withIntermediateDirectories:YES
            attributes:nil error:nil], "create unrelated bundle");
        NSURL *otherInfoURL = [NSURL fileURLWithPath:
            [otherBundle stringByAppendingPathComponent:@"Info.plist"]];
        check([@{@"CFBundleIdentifier": @"com.example.other"}
            writeToURL:otherInfoURL error:nil], "write unrelated identity");
        const char *otherPath = [otherBundle
            stringByAppendingPathComponent:@"PLClient"].fileSystemRepresentation;
        check(length(0x7c8, literal, sizeof(literal), otherPath) == 14,
            "preserve other apps with same executable and literal");
        check([@{@"CFBundleIdentifier": @42} writeToURL:otherInfoURL error:nil],
            "write malformed identity");
        check(length(0x7c8, literal, sizeof(literal), otherPath) == 14,
            "ignore non-string bundle identifier");
        check([files removeItemAtURL:otherInfoURL error:nil], "remove missing-metadata fixture");
        check(length(0x7c8, literal, sizeof(literal), otherPath) == 14,
            "preserve constants when bundle metadata is missing");

        check(LC32GuestBootstrap::EnsureLegacyBundleLayout(
            home.fileSystemRepresentation, path, 0x70000) == 0,
            "create existing legacy bundle aliases");
        NSString *fixed = [[NSString alloc] initWithBytes:literal
            length:length(0x7c8, literal, sizeof(literal), path)
            encoding:NSASCIIStringEncoding];
        NSString *resourceDirectory = [home stringByAppendingPathComponent:fixed];
        const char *cstring = [resourceDirectory cStringUsingEncoding:NSASCIIStringEncoding];
        check(cstring && std::strlen(cstring) > 0,
            "GetResourceDir receives a usable C string");
        NSData *loaded = [NSData dataWithContentsOfFile:
            [resourceDirectory stringByAppendingPathComponent:@"GameCfg.xml"]];
        check([loaded isEqualToData:markerData],
            "corrected path opens resources through PLClient.app alias");
        check(std::memcmp(snapshot, literal, sizeof(literal)) == 0,
            "guest literal bytes remain untouched");
        check([files removeItemAtPath:root error:nil], "remove test fixture");
    }
    std::printf("legacy-resource-path: %u failures\n", failures);
    return failures ? 1 : 0;
}
