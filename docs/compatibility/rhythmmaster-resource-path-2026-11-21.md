# Rhythm Master 2.1.5 resource path compatibility

The supplied `com.tencent.game.rhythmmaster` game (version 2.1.5, build
2.1.5.1, executable `PLClient`, SDK 7.0) reaches its startup display and
audio, then reports a guest null read in `strlen`, called by
`GetResourceDir() + 0x9c`.

Static inspection finds this sequence:

1. Obtain `NSHomeDirectory()`.
2. Append the constant `PLClient.app/` with `stringByAppendingPathComponent:`.
3. Convert the result with `cStringUsingEncoding:NSASCIIStringEncoding`.
4. Pass the returned pointer to `strlen` without a null check.

The constant declares length 14, but its text is 13 bytes plus a C
terminator. The terminator becomes an embedded NUL in the native string
mirror. Native Foundation rejects the path component and returns nil;
the subsequent C-string result is null. This failure is reproducible on
macOS without executing the ARM32 game.

## Runtime change

`LC32GetHostConstString` now consults the Foundation compatibility helper
when constructing a native mirror. The helper corrects the mirror length
to 13 only when all of these conditions match:

- The storage flags are the observed 8-bit constant-string flags `0x7c8`.
- The declared length is 14 and the bytes are exactly `PLClient.app/\0`.
- The configured executable is named `PLClient`.
- Its adjacent `Info.plist` identifies `com.tencent.game.rhythmmaster`.

The guest constant, executable, resources, and IPA are unchanged. Other
embedded NULs and UTF-16 constants retain their original lengths. Missing
or malformed bundle metadata does not enable the workaround.

The existing `EnsureLegacyBundleLayout` implementation already creates an
executable-named `HOME/PLClient.app` alias for SDKs before iOS 8, including
when LiveContainer names the actual bundle after its identifier. No new
filesystem alias or global string/path behavior is introduced here.

## Validation and limits

- `make -C test check-legacy-resource-path check-guest-bootstrap` passes.
- The new native regression reproduces the nil path, then loads a fixture
  resource through the existing alias after applying the production helper.
  It also checks unrelated apps, literals, Unicode flags, malformed/missing
  metadata, and unchanged input bytes.
- The Foundation helper compiles for iOS ARM64 with an iOS 15 minimum.
- No full runtime IPA build or iPhone 15 Pro / iOS 27.0 device test has been
  performed. Startup beyond this call and audio stutter remain unverified.
- The earlier `libstdc++.6.dylib: file too short` failure is a separate
  RootFS/library packaging issue. This change does not supply that library;
  a runtime build must still contain a valid ARM32 version.
