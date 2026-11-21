#import <Foundation/Foundation.h>
#include "LegacyResourcePath.h"

#include <cstring>

std::size_t LC32LegacyResourcePathConstantLength(
        std::uint32_t flags, const void *bytes, std::size_t length,
        const char *executablePath) {
    // Rhythm Master 2.1.5's supplied binary declares 14 characters for the
    // 13-byte PLClient.app/ literal, including its C terminator. Modern
    // stringByAppendingPathComponent: rejects that embedded NUL and returns
    // nil; GetResourceDir then passes its nil C-string result to strlen.
    static constexpr char malformedPath[] = "PLClient.app/";
    if(flags != 0x7c8 || !bytes || length != sizeof(malformedPath) ||
            std::memcmp(bytes, malformedPath, sizeof(malformedPath)) != 0 ||
            !executablePath || executablePath[0] != '/') {
        return length;
    }

    @autoreleasepool {
        NSString *path = [NSString stringWithUTF8String:executablePath];
        if(![path.lastPathComponent isEqualToString:@"PLClient"]) return length;
        NSURL *infoURL = [NSURL fileURLWithPath:
            [path.stringByDeletingLastPathComponent
                stringByAppendingPathComponent:@"Info.plist"]];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:infoURL
            error:nil];
        id identifier = info[@"CFBundleIdentifier"];
        if(![identifier isKindOfClass:NSString.class] ||
                ![identifier isEqualToString:@"com.tencent.game.rhythmmaster"]) {
            return length;
        }
    }

    // EnsureLegacyBundleLayout already exposes HOME/PLClient.app even when
    // LiveContainer installs the real bundle under its identifier. Correct
    // only this native mirror's length; keep all guest memory unchanged.
    return sizeof(malformedPath) - 1;
}
