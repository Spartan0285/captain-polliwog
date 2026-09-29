/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPExternalPlayer.h"
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>
#include <CoreServices/CoreServices.h>
#include <signal.h>

static NSString * const CPPreferredPlayerKey = @"CPExternalPlayerPath";

// Best first. Most of these decode H.264 with FFmpeg, which on PowerPC
// means AltiVec; QuickTime Player is the one every Mac has and the slowest
// of them, so it comes last and is never chosen over the others.
//
// PowerVLC leads because it is the only one built for these processors
// rather than merely running on them: separate G3, G4 and G5 builds, and on
// a G4 it manages 720p, which nothing else here does.
static NSString * const CPKnownPlayers[] = {
    @"/Applications/PowerVLC.app",
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

+ (NSArray *)fasterPlayers
{
    NSMutableArray *faster = [NSMutableArray arrayWithArray:[self availablePlayers]];
    [faster removeObject:@"/Applications/QuickTime Player.app"];
    return faster;
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
// The URL as base64url with no padding: A-Z a-z 0-9 - _ and nothing else, so
// no encoder downstream has anything to act on.
static NSString *CPBase64URLEncode(NSString *text)
{
    static const char *alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const char *bytes = [text UTF8String];
    size_t length = bytes != NULL ? strlen(bytes) : 0;
    NSMutableString *out;
    size_t i;
    unsigned accumulator = 0;
    int held = 0;

    if (length == 0)
        return nil;
    out = [NSMutableString stringWithCapacity:(length * 4) / 3 + 4];
    for (i = 0; i < length; i++) {
        accumulator = (accumulator << 8) | (unsigned char)bytes[i];
        held += 8;
        while (held >= 6) {
            held -= 6;
            [out appendFormat:@"%c", alphabet[(accumulator >> held) & 0x3f]];
        }
    }
    // The leftover bits, padded with zeros rather than '=' - the decoder
    // stops on a partial group, and '=' is exactly the kind of character
    // this is avoiding.
    if (held > 0)
        [out appendFormat:@"%c", alphabet[(accumulator << (6 - held)) & 0x3f]];
    return out;
}

// The extension the relay address is given, which is the only thing VLC uses
// to decide what a --input-slave holds. Guessed from the address, since
// YouTube says so in its mime parameter and most other sites end the path
// with it.
static NSString *CPRelayExtension(NSString *mediaURL, BOOL isAudio)
{
    if (isAudio)
        return [mediaURL rangeOfString:@"mime=audio%2Fwebm"].location != NSNotFound
            ? @"weba" : @"m4a";
    return [mediaURL rangeOfString:@"mime=video%2Fwebm"].location != NSNotFound
        ? @"webm" : @"mp4";
}

static NSURL *CPRelayedURL(NSString *mediaURL, BOOL isAudio)
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

    // base64url, not percent escapes. VLC re-encodes the address it is given
    // before it sends it, so every % in a percent-escaped URL arrives at the
    // relay as %25 and the relay - which decodes once - sees an address that
    // does not begin with http and refuses it. Nothing in this alphabet can
    // be escaped again. See CPBase64URLDecode in CPMediaRelay.m.
    escaped = CPBase64URLEncode(mediaURL);
    if (escaped == nil)
        return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:
        @"http://127.0.0.1:%d/media/%@/%@.%@", port, token, escaped,
        CPRelayExtension(mediaURL, isAudio)]];
}

// The last player this browser started, so a second hand-over can end it
// rather than leaving it open behind the new one.
static pid_t lastLaunched = 0;

// The players that read an address from argv. Both of these are ports of
// command-line programs and have always taken one.
static BOOL CPTakesURLArgument(NSString *bundlePath)
{
    NSString *identifier = [[[NSBundle bundleWithPath:bundlePath] infoDictionary]
                            objectForKey:@"CFBundleIdentifier"];
    // PowerVLC is a VLC by behaviour and not by identifier: it ships as
    // com.github.PowerVLC, which matches neither videolan prefix. Without
    // this it is handed no address at all and opens to an empty window.
    return [identifier hasPrefix:@"org.videolan"] || [identifier hasPrefix:@"com.videolan"]
        || [identifier rangeOfString:@"powervlc" options:NSCaseInsensitiveSearch].location != NSNotFound
        || [identifier rangeOfString:@"mplayer" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// VLC and MPlayer both take a second stream for sound, and spell it
// differently. Returns nil for a player that cannot, which is QuickTime.
static NSString *CPAudioSlaveFlag(NSString *bundlePath)
{
    NSString *identifier = [[[NSBundle bundleWithPath:bundlePath] infoDictionary]
                            objectForKey:@"CFBundleIdentifier"];

    if ([identifier hasPrefix:@"org.videolan"] || [identifier hasPrefix:@"com.videolan"]
        || [identifier rangeOfString:@"powervlc" options:NSCaseInsensitiveSearch].location != NSNotFound)
        return @"--input-slave=";
    if ([identifier rangeOfString:@"mplayer" options:NSCaseInsensitiveSearch].location != NSNotFound)
        return @"-audiofile";
    return nil;
}

+ (BOOL)preferredPlayerAcceptsSeparateAudio
{
    NSString *player = [self preferredPlayer];
    return player != nil && CPAudioSlaveFlag(player) != nil;
}

+ (BOOL)playMediaURL:(NSString *)mediaURL
{
    return [self playMediaURL:mediaURL withAudioURL:nil];
}

// VLC reads HLS and can be told a ceiling; MPlayer of this vintage cannot be
// relied on to, and QuickTime Player will not take the option at all.
+ (BOOL)preferredPlayerAcceptsManifest
{
    NSString *player = [self preferredPlayer];
    NSString *flag = player != nil ? CPAudioSlaveFlag(player) : nil;
    return flag != nil && [flag isEqualToString:@"--input-slave="];
}

+ (BOOL)playManifestURL:(NSString *)manifestURL maxHeight:(unsigned)maxHeight
{
    NSString *player = [self preferredPlayer];
    NSMutableDictionary *environment;
    NSEnumerator *names;
    NSString *name, *executable;
    NSTask *task;

    if (player == nil || ![self preferredPlayerAcceptsManifest] || [manifestURL length] == 0)
        return NO;
    executable = [[[NSBundle bundleWithPath:player] infoDictionary] objectForKey:@"CFBundleExecutable"];
    if (executable == nil)
        return NO;

    environment = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
    names = [[environment allKeys] objectEnumerator];
    while ((name = [names nextObject]) != nil) {
        if ([name hasPrefix:@"DYLD_"])
            [environment removeObjectForKey:name];
    }
    if (lastLaunched > 0 && kill(lastLaunched, 0) == 0)
        kill(lastLaunched, SIGTERM);
    lastLaunched = 0;

    task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:[[player stringByAppendingPathComponent:@"Contents/MacOS"]
                         stringByAppendingPathComponent:executable]];
    [task setArguments:[NSArray arrayWithObjects:manifestURL,
        [NSString stringWithFormat:@"--adaptive-maxheight=%u", maxHeight], nil]];
    [task setEnvironment:environment];
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: handing a manifest to %@, no taller than %up",
              [player lastPathComponent], maxHeight);
    NS_DURING
        [task launch];
    NS_HANDLER
        NSLog(@"Captain Polliwog: %@ would not start: %@", player, [localException reason]);
        return NO;
    NS_ENDHANDLER
    lastLaunched = [task processIdentifier];
    [self performSelector:@selector(bringForward:)
               withObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:lastLaunched],
                                   [NSNumber numberWithInt:0], nil]
               afterDelay:0.5];
    return YES;
}

+ (BOOL)playMediaURL:(NSString *)mediaURL withAudioURL:(NSString *)audioURL
{
    NSString *player = [self preferredPlayer];
    NSURL *relayed = CPRelayedURL(mediaURL, NO);
    NSURL *relayedAudio = audioURL != nil ? CPRelayedURL(audioURL, YES) : nil;
    NSMutableDictionary *environment;
    NSEnumerator *names;
    NSString *name;
    NSTask *task;

    // Failing here used to be silent: the overlay button ignores the answer,
    // so a hand-over that never happened looked exactly like a button that
    // did nothing. Each way out says which way it went.
    if (player == nil) {
        NSLog(@"Captain Polliwog: no media player is set, so %@ cannot be handed over",
              [mediaURL substringToIndex:MIN((unsigned)60, (unsigned)[mediaURL length])]);
        return NO;
    }
    // Asked for two streams and given a player that takes one. Better to
    // say so than to hand over the video and let it play in silence.
    if (relayedAudio != nil && player != nil && CPAudioSlaveFlag(player) == nil) {
        NSLog(@"Captain Polliwog: %@ cannot take sound as a second stream, "
              @"so the chosen quality cannot be handed to it",
              [player lastPathComponent]);
        return NO;
    }
    if (relayed == nil) {
        NSLog(@"Captain Polliwog: cannot hand over this address (%lu characters, scheme %@): "
              @"only http and https can be passed to another program",
              (unsigned long)[mediaURL length],
              [[NSURL URLWithString:mediaURL] scheme] != nil
                  ? [[NSURL URLWithString:mediaURL] scheme] : @"unreadable");
        return NO;
    }

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
    // The one we started last is ended first - only ever a process this
    // browser launched, never a copy opened by hand.
    //
    // This used to pass --one-instance to VLC as well, to let a second
    // hand-over go to the copy already running. The PowerPC builds do not
    // have that option: VLC 2.0.10 answers "unknown option or missing
    // mandatory argument `--one-instance'", prints its usage and exits
    // before it draws a window. Nothing showed that, because launching it
    // succeeded - the browser had started a program, and the program chose
    // to leave. Which looked exactly like a button that did nothing.
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
        [arguments addObject:[relayed absoluteString]];
        // Sound as a second stream, for the qualities that only exist that
        // way. VLC wants it glued to the flag, MPlayer wants it as the next
        // argument - passing it the wrong way round is not an error, it just
        // plays the video silently, which looks like a broken hand-over.
        if (relayedAudio != nil) {
            NSString *flag = CPAudioSlaveFlag(player);
            if ([flag hasSuffix:@"="])
                [arguments addObject:[flag stringByAppendingString:[relayedAudio absoluteString]]];
            else if (flag != nil) {
                [arguments addObject:flag];
                [arguments addObject:[relayedAudio absoluteString]];
            }
        }
        [task setLaunchPath:[[player stringByAppendingPathComponent:@"Contents/MacOS"]
                             stringByAppendingPathComponent:executable]];
        [task setArguments:arguments];
    } else {
        [task setLaunchPath:@"/usr/bin/open"];
        [task setArguments:[NSArray arrayWithObjects:@"-a", player, [relayed absoluteString], nil]];
    }
    [task setEnvironment:environment];
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: handing %@ to %@", [relayed absoluteString], [task launchPath]);
    NS_DURING
        [task launch];
    NS_HANDLER
        NSLog(@"Captain Polliwog: %@ would not start: %@", player, [localException reason]);
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
