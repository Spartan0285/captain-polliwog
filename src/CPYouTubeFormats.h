/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>
@class WebView;

// Asks YouTube for the streams it will not offer this engine.
//
// A page loaded here plays at 360p and has no quality menu, and for a long
// time the explanation in our own release notes was that this is what a
// browser without Media Source Extensions gets. That was wrong. MSE governs
// whether the *engine* can play adaptive streams; it has nothing to do with
// which streams YouTube is willing to name.
//
// What actually happens: the watch page's own playerResponse carries
// adaptiveFormats up to 1080p with plain unciphered URLs - and every one of
// them answers 403. The web client's formats require a PO token, a BotGuard
// attestation appended as &pot=..., and BotGuard cannot run in this engine.
// Progressive itag 18 is exempt, which is why 360p works and nothing else
// does.
//
// The way through is to ask InnerTube as a client that is not gated that
// way, from inside the page - because the one ingredient that cannot be
// forged is visitorData, and the page already has it. Cookies do not
// substitute: without visitorData the answer is LOGIN_REQUIRED.
//
// Which client that is has changed once already and will change again. See
// the note on CP_INNERTUBE_CLIENT in the implementation before touching
// this: an earlier one served sixty seconds of a video and then refused, and
// a good deal of this file used to be built around working within that.
//
// These are separate video and audio streams unless the video has an HLS
// manifest, so for the ordinary case this does not let the engine play them
// - <video> would need MSE. It lets us hand a real player something better
// than 360p, which is where the decoding was happening anyway.
@interface CPYouTubeFormats : NSObject

// Whether this page is a YouTube watch page worth asking about.
+ (BOOL)canResolveInWebView:(WebView *)webView;

// Starts the request inside the page. Asynchronous because the answer needs
// a round trip to YouTube; the page keeps its own state and is polled, since
// stringByEvaluatingJavaScriptFromString cannot wait for anything.
//
// Calls -youTubeFormats:error:forWebView: on the delegate exactly once, with
// an array of format dictionaries tallest first, or nil and an error string
// fit to show someone. Safe to call again while one is in flight; the second
// call joins the first.
+ (void)resolveInWebView:(WebView *)webView delegate:(id)delegate;

// Keys in each format dictionary.
//   CPFormatHeight    NSNumber, pixels
//   CPFormatFPS       NSNumber
//   CPFormatVideoURL  NSString
//   CPFormatAudioURL  NSString, the best AAC stream, same for every entry
//   CPFormatLabel     NSString, "720p" or "720p60", for a menu
//   CPFormatBitrate   NSNumber, bits per second, video only
//   CPFormatProgressive  NSNumber, YES when picture and sound are one
//                        stream - the only kind that plays to the end
//   CPFormatSeconds   NSNumber, how long the video is
//   CPFormatHLSURL    NSString, a muxed manifest up to 1080p when this
//                     video has one, which is uncapped - empty when not
+ (NSArray *)formatsForWebView:(WebView *)webView;

// The one to hand over, given what someone asked for in Preferences: the
// tallest on offer that is no taller than that, or a muxed manifest when the
// video has one.
+ (NSDictionary *)formatToHandOverIn:(NSArray *)formats preferredHeight:(unsigned)wanted;

// The tallest format this Mac is asked for by default, by processor: 360p on
// a G3, 480p on a G4, 1080p on a G5. Deliberately below what each can be made
// to manage - a G4 will play 720p and will also drop frames doing it with
// anything else running - because a default should be right without anyone
// thinking about it. Used when the preference is left at "best this Mac can
// handle"; naming a height in Preferences overrides it.
+ (unsigned)advisableHeightCeiling;

// The entry from formats that best matches a wanted height, never taller
// than the ceiling. nil when the array is empty.
+ (NSDictionary *)formatInFormats:(NSArray *)formats closestToHeight:(unsigned)wanted;

@end

// What resolveInWebView:delegate: calls back. An informal protocol, which is
// all this runtime has.
@interface NSObject (CPYouTubeFormatsDelegate)
- (void)youTubeFormats:(NSArray *)formats error:(NSString *)error
            forWebView:(WebView *)webView;
@end

extern NSString * const CPFormatHeight;
extern NSString * const CPFormatFPS;
extern NSString * const CPFormatVideoURL;
extern NSString * const CPFormatAudioURL;
extern NSString * const CPFormatLabel;
extern NSString * const CPFormatBitrate;
extern NSString * const CPFormatProgressive;
extern NSString * const CPFormatSeconds;
extern NSString * const CPFormatHLSURL;
