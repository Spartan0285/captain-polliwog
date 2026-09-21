/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>
@class WebView;

// Hands the video a page is playing to a real media player.
//
// The browser decodes H.264 through QuickTime, and QuickTime 7's decoder is
// the slowest part of watching anything on a G4. VLC and MPlayer decode the
// same stream with FFmpeg's AltiVec assembly and are markedly faster - far
// enough that a 480p file plays in them and stutters here.
//
// The player is pointed at the media relay rather than at the site, for the
// same reason the engine is: the relay fetches through the browser's own
// libcurl and OpenSSL, and these players are linked against a system TLS
// that video servers hung up on years ago.
@interface CPExternalPlayer : NSObject

// The players installed on this Mac, best first, each as a bundle path.
// QuickTime Player is always last and always present.
+ (NSArray *)availablePlayers;
+ (NSString *)displayNameForPlayer:(NSString *)bundlePath;

// The one to use: the preference if it is still installed, else the best
// available.
+ (NSString *)preferredPlayer;
+ (void)setPreferredPlayer:(NSString *)bundlePath;

// What the page is playing, as the page itself reports it: the source of
// the largest <video> that has one. nil when there is nothing to play.
+ (NSString *)playingMediaURLInWebView:(WebView *)webView;

// Opens that URL in the preferred player, through the relay. Returns NO if
// the player could not be launched.
+ (BOOL)playMediaURL:(NSString *)mediaURL;

// Internal: keeps asking the window server to front the player until it has
// finished launching.
+ (void)bringForward:(NSArray *)state;

@end
