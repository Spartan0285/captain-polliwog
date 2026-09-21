/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPExternalPlayer.h"
#import <WebKit/WebKit.h>
#include <CoreServices/CoreServices.h>
#include <signal.h>

static NSString * const CPPreferredPlayerKey = @"CPExternalPlayerPath";

// Best first. The first three decode H.264 with FFmpeg, which on PowerPC
// means AltiVec; QuickTime Player is the one every Mac has and the slowest
// of them, so it comes last and is never chosen over the others.
static NSString * const CPKnownPlayers[] = {
    @"/Applications/VLC.app",
    @"/Applications/MPlayer OSX Extended.app",
    @"/Applications/MPlayer OSX.app",
    @"/Applications/Movist.app",
    @"/Applications/NicePlayer.app",
    @"/Applications/QuickTime Player.app",
    nil
};

@implementation CPExternalPlayer

+ (NSArray *)availablePlayers
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray *found = [NSMutableArray array];
    unsigned i;

    for (i = 0; CPKnownPlayers[i] != nil; i++) {
        if ([files fileExistsAtPath:CPKnownPlayers[i]])
            [found addObject:CPKnownPlayers[i]];
    }
    return found;
}

+ (NSString *)displayNameForPlayer:(NSString *)bundlePath
{
    return [[NSFileManager defaultManager] displayNameAtPath:bundlePath];
}

+ (NSString *)preferredPlayer
{
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:CPPreferredPlayerKey];
    NSArray *available = [self availablePlayers];

    if (chosen != nil && [[NSFileManager defaultManager] fileExistsAtPath:chosen])
        return chosen;
    return [available count] > 0 ? [available objectAtIndex:0] : nil;
}

+ (void)setPreferredPlayer:(NSString *)bundlePath
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (bundlePath == nil)
        [defaults removeObjectForKey:CPPreferredPlayerKey];
    else
        [defaults setObject:bundlePath forKey:CPPreferredPlayerKey];
}

#pragma mark What the page is playing

// Asking the page is the only way to know. A site may have several <video>
// elements - a hero loop, an advert, the one being watched - so this takes
// the biggest one with a source, which on every video site is the one the
// viewer is looking at. currentSrc, not src: the source may have come from
// a <source> child, and after a redirect currentSrc is the address that was
// actually fetched.
+ (NSString *)playingMediaURLInWebView:(WebView *)webView
{
    static NSString * const script =
        @"(function () {"
        @"  var videos = document.getElementsByTagName('video'), best = null, bestArea = -1;"
        @"  for (var i = 0; i < videos.length; i++) {"
        @"    var v = videos[i], src = v.currentSrc || v.src;"
        @"    if (!src) continue;"
        @"    var area = (v.videoWidth || v.clientWidth || 1) * (v.videoHeight || v.clientHeight || 1);"
        @"    if (area > bestArea) { bestArea = area; best = src; }"
        @"  }"
        @"  return best || '';"
        @"})()";
    NSString *found;

    if (webView == nil)
        return nil;
    found = [webView stringByEvaluatingJavaScriptFromString:script];
    if ([found length] == 0)
        return nil;
    return found;
}

#pragma mark Handing it over

// The relay's own URL form, the same one MediaPlayerPrivateQTKit builds:
// http://127.0.0.1:<port>/media?token=<token>&url=<escaped>
static NSURL *CPRelayedURL(NSString *mediaURL)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    int port = (int)[defaults integerForKey:@"CPMediaRelayPort"];
    NSString *token = [defaults stringForKey:@"CPMediaRelayToken"];
    NSString *scheme = [[[NSURL URLWithString:mediaURL] scheme] lowercaseString];
    NSString *escaped;

    // blob: and data: sources cannot be relayed; nothing outside the browser
    // can resolve them.
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
        return nil;
    if (port <= 0 || token == nil)
        return [NSURL URLWithString:mediaURL];

    escaped = [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)mediaURL, NULL,
        CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8) autorelease];
    return [NSURL URLWithString:[NSString stringWithFormat:
        @"http://127.0.0.1:%d/media?token=%@&url=%@", port, token, escaped]];
}

// The last player this browser started, so a second hand-over can end it
// rather than leaving it open behind the new one.
static pid_t lastLaunched = 0;

static BOOL CPIsVLC(NSString *bundlePath)
{
    NSString *identifier = [[[NSBundle bundleWithPath:bundlePath] infoDictionary]
                            objectForKey:@"CFBundleIdentifier"];
    return [identifier hasPrefix:@"org.videolan"] || [identifier hasPrefix:@"com.videolan"];
}

// The players that read an address from argv. Both of these are ports of
// command-line programs and have always taken one.
static BOOL CPTakesURLArgument(NSString *bundlePath)
{
    NSString *identifier = [[[NSBundle bundleWithPath:bundlePath] infoDictionary]
                            objectForKey:@"CFBundleIdentifier"];
    return [identifier hasPrefix:@"org.videolan"] || [identifier hasPrefix:@"com.videolan"]
        || [identifier rangeOfString:@"mplayer" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

+ (BOOL)playMediaURL:(NSString *)mediaURL
{
    NSString *player = [self preferredPlayer];
    NSURL *relayed = CPRelayedURL(mediaURL);
    NSMutableDictionary *environment;
    NSEnumerator *names;
    NSString *name;
    NSTask *task;

    if (player == nil || relayed == nil)
        return NO;

    // Not NSWorkspace, and this is the whole reason: the browser runs with
    // DYLD_FRAMEWORK_PATH pointing at its own bundled WebKit, and a player
    // launched from here inherits it. QuickTime Player then tries to load
    // our JavaScriptCore instead of the system's, fails in dyld, and
    // disappears without ever showing a window - which looks exactly like
    // the launch having silently done nothing.
    environment = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
    names = [[environment allKeys] objectEnumerator];
    while ((name = [names nextObject]) != nil) {
        if ([name hasPrefix:@"DYLD_"])
            [environment removeObjectForKey:name];
    }

    // How the URL reaches the player differs, and getting it wrong looks
    // like success: `open -a VLC <http url>` launches VLC and leaves it
    // sitting on an empty window, because LaunchServices has no reason to
    // route http at it. VLC and MPlayer both take the address as an
    // argument, so they are run directly. QuickTime Player does not, and
    // does accept it through LaunchServices, so it goes the other way.
    // Running the binary means LaunchServices is not involved, and so the
    // usual "the app is already open, give it this document" does not
    // happen: every hand-over started another copy, and they piled up one
    // per click. Two answers, because neither covers both players.
    //
    // VLC has --one-instance for exactly this: a second invocation passes
    // the item to the one already running and exits. MPlayer has nothing of
    // the kind, so the one we started last is ended first - only ever a
    // process this browser launched, never a copy opened by hand.
    if (lastLaunched > 0 && kill(lastLaunched, 0) == 0)
        kill(lastLaunched, SIGTERM);
    lastLaunched = 0;

    task = [[[NSTask alloc] init] autorelease];
    if (CPTakesURLArgument(player)) {
        NSString *executable = [[[NSBundle bundleWithPath:player] infoDictionary]
                                objectForKey:@"CFBundleExecutable"];
        NSMutableArray *arguments = [NSMutableArray array];
        if (executable == nil)
            return NO;
        if (CPIsVLC(player))
            [arguments addObject:@"--one-instance"];
        [arguments addObject:[relayed absoluteString]];
        [task setLaunchPath:[[player stringByAppendingPathComponent:@"Contents/MacOS"]
                             stringByAppendingPathComponent:executable]];
        [task setArguments:arguments];
    } else {
        [task setLaunchPath:@"/usr/bin/open"];
        [task setArguments:[NSArray arrayWithObjects:@"-a", player, [relayed absoluteString], nil]];
    }
    [task setEnvironment:environment];
    NS_DURING
        [task launch];
    NS_HANDLER
        return NO;
    NS_ENDHANDLER

    // Bring it forward. A program started from another program is not
    // activated the way one opened from the Finder is, so without this VLC
    // plays perfectly well behind the browser window and looks like nothing
    // happened. It cannot be done at once: the process has to register with
    // the window server first, which on a G4 takes several seconds, so this
    // asks once a second until it works or a minute has passed.
    lastLaunched = [task processIdentifier];
    [self performSelector:@selector(bringForward:)
               withObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:lastLaunched],
                                                    [NSNumber numberWithInt:0], nil]
               afterDelay:0.5];
    return YES;
}

+ (void)bringForward:(NSArray *)state
{
    pid_t pid = (pid_t)[[state objectAtIndex:0] intValue];
    int attempt = [[state objectAtIndex:1] intValue];
    ProcessSerialNumber serial;

    if (GetProcessForPID(pid, &serial) == noErr) {
        SetFrontProcess(&serial);
        return;
    }
    if (attempt >= 60 || kill(pid, 0) != 0)
        return;     // it gave up, or we have
    [self performSelector:@selector(bringForward:)
               withObject:[NSArray arrayWithObjects:[state objectAtIndex:0],
                                                    [NSNumber numberWithInt:attempt + 1], nil]
               afterDelay:1.0];
}

@end
