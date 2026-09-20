/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Checking for a new version of Captain Polliwog, and installing it.
//
// Sparkle is the usual answer, and its "classic" 1.5b6 is the last release
// that runs on PowerPC - but it asks Foundation to fetch the feed, and on
// Tiger and Leopard that means TLS 1.0 with a certificate store from 2009,
// which cannot reach GitHub or anywhere else a release would be kept. It also
// renders release notes in a WebView, which is how CVE-2016-4663 worked.
//
// So: the feed is fetched through Captain Polliwog's own network stack
// (CPCurlProtocol: libcurl, OpenSSL 3, our own certificate bundle), the feed
// is a property list because Tiger can parse those and cannot parse JSON,
// release notes are shown as plain text, and every download is checked
// against an Ed25519 signature made with a key that never leaves the
// maintainer's machine. Nothing is ever installed without being asked for.

extern NSString * const CPUpdaterDidChangeNotification;

typedef enum {
    CPUpdateIdle,
    CPUpdateChecking,
    CPUpdateAvailable,
    CPUpdateDownloading,
    CPUpdateReadyToInstall,
    CPUpdateUpToDate,
    CPUpdateFailed
} CPUpdateState;

@interface CPUpdater : NSObject
{
    CPUpdateState  state;
    NSString      *availableVersion;
    NSString      *releaseNotes;
    NSURL         *downloadURL;
    long long      downloadLength;
    NSString      *expectedDigest;      // SHA-256, hex
    NSString      *signature;           // Ed25519 over the manifest, base64
    NSString      *failureReason;
    NSString      *downloadPath;        // the .zip while it is being fetched
    NSString      *unpackedPath;        // the verified app bundle, ready to install
    long long      received;
    NSMutableData *feedData;
    NSURLConnection *feedConnection;
    id             downloadTask;        // CPNetworkTask
    BOOL           userAsked;           // a check the user started, so speak up
    BOOL           overridden;          // the feed was named in the defaults
}

+ (CPUpdater *)sharedUpdater;

// The version this build reports (CFBundleShortVersionString).
+ (NSString *)currentVersion;

// At launch: checks at most once a day, and only if the preference is on.
- (void)checkInBackground;
// From the menu: always checks, and says so even when there is nothing new.
- (void)checkAsked;

// Fetch the new version and verify it. -installAndRelaunch replaces the
// running app with it and starts it again.
- (void)download;
- (void)installAndRelaunch;
- (void)cancel;

- (CPUpdateState)state;
- (NSString *)availableVersion;
- (NSString *)releaseNotes;
- (NSString *)failureReason;
- (double)downloadProgress;             // 0 to 1, or -1 when the size is unknown
- (long long)downloadLength;

@end
