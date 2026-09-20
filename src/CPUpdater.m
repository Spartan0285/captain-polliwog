/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPUpdater.h"
#import "CPNetworkEngine.h"
#import "CPNetworkTask.h"
#import "CPDebugSnapshot.h"

#include <openssl/evp.h>

NSString * const CPUpdaterDidChangeNotification = @"CPUpdaterDidChange";

NSString * const CPChecksForUpdatesKey = @"CPChecksForUpdates";
static NSString * const CPLastUpdateCheckKey = @"CPLastUpdateCheck";
static NSString * const CPUpdateFeedOverrideKey = @"CPUpdateFeed";

// Where releases are announced. An override is allowed for testing a feed
// before it is published; it changes where the file comes from and nothing
// else, because an update is installed only if it carries a signature from
// the key below.
static NSString * const CPUpdateFeedURL =
    @"https://raw.githubusercontent.com/Spartan0285/captain-polliwog/main/updates/appcast.plist";

// The public half of the release signing key (Ed25519, raw, base64). The
// private half is on the maintainer's machine and is never in this repository
// (scripts/generate-update-key.sh).
static NSString * const CPUpdatePublicKey = @"ICJO1ej13vqCzT2ZHlciewpD5pf9vpeYlWQnYrY7Bxw=";

static const NSTimeInterval CPUpdateCheckInterval = 24 * 60 * 60;
static const long long CPUpdateMaximumLength = 200LL * 1024 * 1024;

// The signed statement. Binding the length and the digest is what makes the
// download safe to run; the version keeps a signed old release from being
// served in place of a new one.
static NSString *CPUpdateManifest(NSString *version, long long length, NSString *digest)
{
    return [NSString stringWithFormat:@"captain-polliwog-update-v1\n%@\n%lld\n%@\n",
            version, length, [digest lowercaseString]];
}

// 10.4's Foundation has no base64.
static NSData *CPDecodeBase64(NSString *string)
{
    static const signed char table[128] = {
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1, -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63, 52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-2,-1,-1,
        -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14, 15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
        -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40, 41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1
    };
    NSData *ascii = [string dataUsingEncoding:NSASCIIStringEncoding];
    const unsigned char *bytes = [ascii bytes];
    NSMutableData *out = [NSMutableData data];
    unsigned int accumulator = 0;
    int bits = 0, i;

    if (ascii == nil)
        return nil;
    for (i = 0; i < (int)[ascii length]; i++) {
        signed char value = bytes[i] < 128 ? table[bytes[i]] : -1;
        if (value == -2)                        // '=' ends the data
            break;
        if (value < 0)                          // whitespace and the like
            continue;
        accumulator = (accumulator << 6) | (unsigned int)value;
        bits += 6;
        if (bits >= 8) {
            unsigned char byte = (unsigned char)((accumulator >> (bits - 8)) & 0xff);
            bits -= 8;
            [out appendBytes:&byte length:1];
        }
    }
    return out;
}

// The file's SHA-256, as hex, read in pieces so a 30MB download never sits in
// memory on a machine that may only have 256MB of it.
static NSString *CPDigestOfFile(NSString *path)
{
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int length = 0;
    NSMutableString *hex;
    unsigned char buffer[65536];
    FILE *file;
    size_t got;
    unsigned int i;

    if (context == NULL)
        return nil;
    file = fopen([path fileSystemRepresentation], "rb");
    if (file == NULL || !EVP_DigestInit_ex(context, EVP_sha256(), NULL)) {
        if (file != NULL)
            fclose(file);
        EVP_MD_CTX_free(context);
        return nil;
    }
    while ((got = fread(buffer, 1, sizeof(buffer), file)) > 0)
        EVP_DigestUpdate(context, buffer, got);
    fclose(file);
    EVP_DigestFinal_ex(context, digest, &length);
    EVP_MD_CTX_free(context);

    hex = [NSMutableString stringWithCapacity:length * 2];
    for (i = 0; i < length; i++)
        [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static BOOL CPVerifySignature(NSString *manifest, NSString *base64Signature)
{
    NSData *publicKey = CPDecodeBase64(CPUpdatePublicKey);
    NSData *signature = CPDecodeBase64(base64Signature);
    NSData *message = [manifest dataUsingEncoding:NSUTF8StringEncoding];
    EVP_PKEY *key;
    EVP_MD_CTX *context;
    BOOL verified = NO;

    if ([publicKey length] != 32 || [signature length] != 64 || message == nil)
        return NO;
    key = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, NULL, [publicKey bytes], 32);
    if (key == NULL)
        return NO;
    context = EVP_MD_CTX_new();
    if (context != NULL && EVP_DigestVerifyInit(context, NULL, NULL, NULL, key) == 1) {
        verified = EVP_DigestVerify(context, [signature bytes], [signature length],
                                    [message bytes], [message length]) == 1;
    }
    if (context != NULL)
        EVP_MD_CTX_free(context);
    EVP_PKEY_free(key);
    return verified;
}

// "0.3" against "0.10": compared a number at a time, so 10 beats 3.
static NSComparisonResult CPCompareVersions(NSString *left, NSString *right)
{
    NSArray *leftParts = [left componentsSeparatedByString:@"."];
    NSArray *rightParts = [right componentsSeparatedByString:@"."];
    unsigned int i, count = MAX([leftParts count], [rightParts count]);

    for (i = 0; i < count; i++) {
        int a = i < [leftParts count] ? [[leftParts objectAtIndex:i] intValue] : 0;
        int b = i < [rightParts count] ? [[rightParts objectAtIndex:i] intValue] : 0;
        if (a != b)
            return a < b ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

static NSString *CPSystemVersion(void)
{
    NSDictionary *system = [NSDictionary dictionaryWithContentsOfFile:
        @"/System/Library/CoreServices/SystemVersion.plist"];
    NSString *version = [system objectForKey:@"ProductVersion"];
    return version != nil ? version : @"10.4";
}

@interface CPUpdater (Private)
- (void)setState:(CPUpdateState)newState;
- (void)failWithReason:(NSString *)reason;
- (void)startCheck;
- (void)readFeed:(NSData *)data;
- (void)verifyDownloadInBackground;
- (void)verificationFinished:(NSString *)problem;
@end

@implementation CPUpdater

+ (CPUpdater *)sharedUpdater
{
    static CPUpdater *updater = nil;
    if (updater == nil)
        updater = [[CPUpdater alloc] init];
    return updater;
}

+ (NSString *)currentVersion
{
    NSString *version = [[[NSBundle mainBundle] infoDictionary]
        objectForKey:@"CFBundleShortVersionString"];
    return version != nil ? version : @"0";
}

- (void)dealloc
{
    [availableVersion release];
    [releaseNotes release];
    [downloadURL release];
    [expectedDigest release];
    [signature release];
    [failureReason release];
    [downloadPath release];
    [unpackedPath release];
    [feedData release];
    [feedConnection release];
    [downloadTask release];
    [super dealloc];
}

- (CPUpdateState)state { return state; }
- (NSString *)availableVersion { return availableVersion; }
- (NSString *)releaseNotes { return releaseNotes; }
- (NSString *)failureReason { return failureReason; }
- (long long)downloadLength { return downloadLength; }

- (double)downloadProgress
{
    if (downloadLength <= 0)
        return -1;
    return (double)received / (double)downloadLength;
}

- (void)setState:(CPUpdateState)newState
{
    static const char *names[] = { "idle", "checking", "available", "downloading",
                                   "ready to install", "up to date", "failed" };

    state = newState;
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: update %s", names[newState]);
    [[NSNotificationCenter defaultCenter] postNotificationName:CPUpdaterDidChangeNotification
                                                        object:self];

    // CPDebugUpdate: walk the whole update through without the window, for
    // the test scripts. CPDebugUpdateInstall goes on to replace this copy.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugUpdate"]) {
        if (newState == CPUpdateAvailable)
            [self performSelector:@selector(download) withObject:nil afterDelay:0.5];
        else if (newState == CPUpdateReadyToInstall
                 && [[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugUpdateInstall"])
            [self performSelector:@selector(installAndRelaunch) withObject:nil afterDelay:0.5];
    }
}

- (void)failWithReason:(NSString *)reason
{
    [failureReason release];
    failureReason = [reason copy];
    NSLog(@"Captain Polliwog: update failed: %@", reason);
    [self setState:CPUpdateFailed];
}

#pragma mark Checking

- (void)checkInBackground
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDate *last = [defaults objectForKey:CPLastUpdateCheckKey];

    if ([defaults boolForKey:@"CPDebugUpdate"]) {      // the test scripts
        userAsked = YES;
        [self startCheck];
        return;
    }
    if (![defaults boolForKey:CPChecksForUpdatesKey])
        return;
    if (last != nil && -[last timeIntervalSinceNow] < CPUpdateCheckInterval)
        return;
    userAsked = NO;
    [self startCheck];
}

- (void)checkAsked
{
    userAsked = YES;
    [self startCheck];
}

- (void)startCheck
{
    NSString *feed = [[NSUserDefaults standardUserDefaults] stringForKey:CPUpdateFeedOverrideKey];
    NSURL *url;
    NSMutableURLRequest *request;

    if (state == CPUpdateChecking || state == CPUpdateDownloading)
        return;
    if ([feed length] == 0) {
        feed = CPUpdateFeedURL;
        overridden = NO;
    } else
        overridden = YES;
    url = [NSURL URLWithString:feed];
    // The published feed is always https. A feed named in the defaults is a
    // testing aid and may be anything, because what makes an update safe to
    // install is its signature, not where it was fetched from.
    if (!overridden && ![[[url scheme] lowercaseString] isEqualToString:@"https"]) {
        [self failWithReason:@"The update feed must be an https address."];
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:CPLastUpdateCheckKey];
    [feedData release];
    feedData = [[NSMutableData alloc] init];
    request = [NSMutableURLRequest requestWithURL:url
                                      cachePolicy:NSURLRequestReloadIgnoringCacheData
                                  timeoutInterval:30];
    [feedConnection release];
    feedConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    [self setState:CPUpdateChecking];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if ([response respondsToSelector:@selector(statusCode)]) {
        int status = [(NSHTTPURLResponse *)response statusCode];
        if (status != 200) {
            [connection cancel];
            [self failWithReason:[NSString stringWithFormat:
                @"The update feed answered %d.", status]];
        }
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // A feed is a few kilobytes; anything larger is not one.
    if ([feedData length] + [data length] > 1024 * 1024) {
        [connection cancel];
        [self failWithReason:@"The update feed is too large."];
        return;
    }
    [feedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self failWithReason:[error localizedDescription]];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self readFeed:feedData];
}

- (void)readFeed:(NSData *)data
{
    NSString *error = nil;
    id feed = [NSPropertyListSerialization propertyListFromData:data
                                               mutabilityOption:NSPropertyListImmutable
                                                         format:NULL
                                               errorDescription:&error];
    NSArray *versions;
    NSString *current = [CPUpdater currentVersion];
    NSString *system = CPSystemVersion();
    NSDictionary *best = nil;
    unsigned int i;

    if (![feed isKindOfClass:[NSDictionary class]]) {
        [self failWithReason:@"The update feed could not be read."];
        return;
    }
    versions = [feed objectForKey:@"versions"];
    if (![versions isKindOfClass:[NSArray class]]) {
        [self failWithReason:@"The update feed has no versions in it."];
        return;
    }

    for (i = 0; i < [versions count]; i++) {
        NSDictionary *item = [versions objectAtIndex:i];
        NSString *version, *minimum;

        if (![item isKindOfClass:[NSDictionary class]])
            continue;
        version = [item objectForKey:@"version"];
        if (![version isKindOfClass:[NSString class]])
            continue;
        if (CPCompareVersions(version, current) != NSOrderedDescending)
            continue;
        minimum = [item objectForKey:@"minimumSystemVersion"];
        if ([minimum isKindOfClass:[NSString class]]
            && CPCompareVersions(system, minimum) == NSOrderedAscending)
            continue;
        if (best == nil
            || CPCompareVersions(version, [best objectForKey:@"version"]) == NSOrderedDescending)
            best = item;
    }

    if (best == nil) {
        [self setState:userAsked ? CPUpdateUpToDate : CPUpdateIdle];
        return;
    }

    {
        NSString *urlString = [best objectForKey:@"url"];
        NSURL *url = [urlString isKindOfClass:[NSString class]]
            ? [NSURL URLWithString:urlString] : nil;
        NSNumber *length = [best objectForKey:@"length"];
        NSString *digest = [best objectForKey:@"sha256"];
        NSString *sign = [best objectForKey:@"signature"];
        NSString *notes = [best objectForKey:@"notes"];

        if ((!overridden && ![[[url scheme] lowercaseString] isEqualToString:@"https"])
            || url == nil
            || ![length isKindOfClass:[NSNumber class]]
            || ![digest isKindOfClass:[NSString class]]
            || ![sign isKindOfClass:[NSString class]]
            || [length longLongValue] <= 0
            || [length longLongValue] > CPUpdateMaximumLength) {
            [self failWithReason:@"That release is not described properly."];
            return;
        }

        [availableVersion release];
        availableVersion = [[best objectForKey:@"version"] copy];
        [downloadURL release];
        downloadURL = [url retain];
        downloadLength = [length longLongValue];
        [expectedDigest release];
        expectedDigest = [digest copy];
        [signature release];
        signature = [sign copy];
        [releaseNotes release];
        releaseNotes = [notes isKindOfClass:[NSString class]] ? [notes copy] : nil;
        received = 0;
    }
    [self setState:CPUpdateAvailable];
}

#pragma mark Downloading

- (void)download
{
    NSString *folder = NSTemporaryDirectory();
    NSURLRequest *request;

    if (state != CPUpdateAvailable && state != CPUpdateFailed)
        return;
    if (downloadURL == nil)
        return;

    [downloadPath release];
    downloadPath = [[folder stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CaptainPolliwog-%@.zip", availableVersion]] retain];
    [[NSFileManager defaultManager] removeFileAtPath:downloadPath handler:nil];

    request = [NSURLRequest requestWithURL:downloadURL
                               cachePolicy:NSURLRequestReloadIgnoringCacheData
                           timeoutInterval:60];
    [downloadTask release];
    downloadTask = [[CPNetworkTask alloc] initWithRequest:request
                                             downloadPath:downloadPath
                                                    owner:self];
    if (downloadTask == nil) {
        [self failWithReason:@"The update could not be started."];
        return;
    }
    received = 0;
    [self setState:CPUpdateDownloading];
    [[CPNetworkEngine sharedEngine] startTask:downloadTask];
}

- (void)downloadReceivedBytes:(NSArray *)receivedAndExpected
{
    if (state != CPUpdateDownloading)
        return;
    received = [[receivedAndExpected objectAtIndex:0] longLongValue];
    if (received > downloadLength + 1024 * 1024) {     // more than was promised
        [self cancel];
        [self failWithReason:@"The update is larger than the feed said."];
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:CPUpdaterDidChangeNotification
                                                        object:self];
}

- (void)downloadFinishedWithError:(NSError *)error
{
    [downloadTask release];
    downloadTask = nil;
    if (error != nil) {
        [self failWithReason:[error localizedDescription]];
        return;
    }
    [NSThread detachNewThreadSelector:@selector(verifyDownloadInBackground)
                             toTarget:self
                           withObject:nil];
}

#pragma mark Verifying

// On a thread: hashing tens of megabytes takes seconds on these machines.
- (void)verifyDownloadInBackground
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *problem = nil;
    NSString *digest;

    do {
        NSDictionary *attributes = [files fileAttributesAtPath:downloadPath traverseLink:NO];
        NSString *manifest;
        NSString *unpacked;
        NSString *bundle;
        NSDictionary *info;
        NSTask *ditto;

        if ([[attributes objectForKey:NSFileSize] longLongValue] != downloadLength) {
            problem = @"The update is not the size the feed said.";
            break;
        }
        digest = CPDigestOfFile(downloadPath);
        if (digest == nil || ![digest isEqualToString:[expectedDigest lowercaseString]]) {
            problem = @"The update does not match its checksum.";
            break;
        }
        manifest = CPUpdateManifest(availableVersion, downloadLength, digest);
        if (!CPVerifySignature(manifest, signature)) {
            problem = @"The update is not signed by Captain Polliwog's key.";
            break;
        }

        // Only now is it unpacked, and even then only read: nothing from it
        // runs until the user asks for it to be installed.
        unpacked = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"CaptainPolliwog-%@-unpacked", availableVersion]];
        [files removeFileAtPath:unpacked handler:nil];
        [files createDirectoryAtPath:unpacked attributes:nil];
        ditto = [[[NSTask alloc] init] autorelease];
        [ditto setLaunchPath:@"/usr/bin/ditto"];
        [ditto setArguments:[NSArray arrayWithObjects:@"-x", @"-k", downloadPath, unpacked, nil]];
        [ditto launch];
        [ditto waitUntilExit];
        if ([ditto terminationStatus] != 0) {
            problem = @"The update could not be unpacked.";
            break;
        }

        bundle = [unpacked stringByAppendingPathComponent:@"Captain Polliwog.app"];
        info = [NSDictionary dictionaryWithContentsOfFile:
            [bundle stringByAppendingPathComponent:@"Contents/Info.plist"]];
        if (![files fileExistsAtPath:[bundle stringByAppendingPathComponent:
                @"Contents/MacOS/CaptainPolliwog"]]
            || ![[info objectForKey:@"CFBundleIdentifier"]
                    isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]
            || ![[info objectForKey:@"CFBundleShortVersionString"]
                    isEqualToString:availableVersion]) {
            problem = @"The update does not contain the version it claims to.";
            break;
        }
        [unpackedPath release];
        unpackedPath = [bundle retain];
    } while (0);

    [self performSelectorOnMainThread:@selector(verificationFinished:)
                           withObject:problem
                        waitUntilDone:NO];
    [pool release];
}

- (void)verificationFinished:(NSString *)problem
{
    [[NSFileManager defaultManager] removeFileAtPath:downloadPath handler:nil];
    if (problem != nil) {
        [self failWithReason:problem];
        return;
    }
    [self setState:CPUpdateReadyToInstall];
}

#pragma mark Installing

- (void)installAndRelaunch
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    NSString *folder = [appPath stringByDeletingLastPathComponent];
    NSString *previous = [folder stringByAppendingPathComponent:@".Captain Polliwog (previous).app"];
    NSString *script;
    NSTask *relaunch;

    if (state != CPUpdateReadyToInstall || unpackedPath == nil)
        return;
    if (![files isWritableFileAtPath:folder]) {
        [self failWithReason:[NSString stringWithFormat:
            @"%@ cannot be written to. The new version is in %@ - drag it there yourself.",
            folder, [unpackedPath stringByDeletingLastPathComponent]]];
        return;
    }

    [files removeFileAtPath:previous handler:nil];
    if (![files movePath:appPath toPath:previous handler:nil]) {
        [self failWithReason:@"The running version could not be moved aside."];
        return;
    }
    if (![files movePath:unpackedPath toPath:appPath handler:nil]) {
        [files movePath:previous toPath:appPath handler:nil];   // put it back
        [self failWithReason:@"The new version could not be put in place."];
        return;
    }

    // Wait for this process to go, throw the old copy away, start the new one.
    script = [NSString stringWithFormat:
        @"while kill -0 %d 2>/dev/null; do sleep 1; done; rm -rf \"$1\"; open \"$2\"",
        [[NSProcessInfo processInfo] processIdentifier]];
    relaunch = [[[NSTask alloc] init] autorelease];
    [relaunch setLaunchPath:@"/bin/sh"];
    [relaunch setArguments:[NSArray arrayWithObjects:@"-c", script, @"sh", previous, appPath, nil]];
    [relaunch launch];
    [NSApp terminate:nil];
}

- (void)cancel
{
    if (downloadTask != nil) {
        [downloadTask markCancelled];
        [downloadTask detachDownloadOwner];
        [downloadTask release];
        downloadTask = nil;
    }
    if (feedConnection != nil) {
        [feedConnection cancel];
        [feedConnection release];
        feedConnection = nil;
    }
    [self setState:CPUpdateIdle];
}

@end
