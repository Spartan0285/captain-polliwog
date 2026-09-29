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
// What actually happens: the watch page's own playerResponse does carry
// adaptiveFormats up to 1080p, with plain unciphered URLs - and every one of
// them answers 403. The WEB client's formats require a PO token, a BotGuard
// attestation appended as &pot=..., and BotGuard cannot run in this engine.
// Progressive itag 18 is exempt, which is why 360p works and nothing else
// does.
//
// The way through is the one yt-dlp takes: ask InnerTube as a different
// client. ANDROID_VR is the only client in yt-dlp's table with no PO token
// policy at all and no JS player requirement, so its URLs arrive ready to
// use - unsigned, unscrambled, and good for about six hours. The request is
// made from inside the page, because the one ingredient that cannot be
// forged is visitorData, and the page already has it. Cookies do not
// substitute: without visitorData the answer is LOGIN_REQUIRED, "Sign in to
// confirm you're not a bot".
//
// These are separate video and audio streams, so this does not let the
// engine play them - <video> would need MSE for that. It lets us hand a real
// player something better than 360p, which is where the decoding was
// happening anyway.
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

// The one to hand over, given what someone asked for in Preferences.
//
// Above 360p YouTube serves us only the first minute or so: every adaptive
// URL refuses any byte range ending past roughly sixty seconds of media,
// whoever asks and however it is asked. Measured across six formats of one
// video the wall sits at 62.2s, 63.4s, 66.8s, 66.2s, 74.7s and 76.2s, and it
// does not move with time or with reading the part that is allowed. So a
// video longer than that gets the progressive stream, whatever quality was
// asked for, because a picture that stops after a minute is worse than one
// that is only 360p. A video short enough to fit - a Short, say - can have
// any quality on the list.
+ (NSDictionary *)formatToHandOverIn:(NSArray *)formats preferredHeight:(unsigned)wanted;

// The tallest format this Mac should be asked to decode, by processor: a G3
// cannot keep up with 720p even in PowerVLC, and a G5 can take 1080p. Used
// when the preference is left at "best this Mac can handle".
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
