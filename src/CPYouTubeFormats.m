/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPYouTubeFormats.h"
#import <WebKit/WebKit.h>
#import <sys/sysctl.h>

NSString * const CPFormatHeight   = @"height";
NSString * const CPFormatFPS      = @"fps";
NSString * const CPFormatVideoURL = @"url";
NSString * const CPFormatAudioURL = @"audio";
NSString * const CPFormatLabel    = @"label";
NSString * const CPFormatBitrate  = @"bitrate";
NSString * const CPFormatProgressive = @"prog";
NSString * const CPFormatSeconds = @"secs";
NSString * const CPFormatHLSURL = @"hls";

// The client we ask as, and the whole reason this works.
//
// YouTube will not hand this engine the better streams as itself: the web
// client's formats need a PO token, a BotGuard attestation we cannot
// compute, and without one every adaptive address it gives us serves about
// sixty seconds and then answers 403 - measured, bisected to the byte, on
// six formats at once.
//
// VISIONOS is not gated that way. It requires no PO token, needs no
// JavaScript player, and its addresses read from the first byte to the last:
// verified on a 257MB 1080p file, where the final 64KB came back as readily
// as the first. It also returns a muxed HLS manifest on every video that
// plays, which ANDROID_VR never did and the iPhone client did for about one
// in eight.
//
// This surface moves. ANDROID_VR was the right answer a month ago and is
// now refused outright; yt-dlp dropped it for this same client. When the
// better qualities stop arriving, this is the line to look at first, and
// yt-dlp's youtube/_base.py is where to look for what replaced it.
#define CP_INNERTUBE_CLIENT         "VISIONOS"
#define CP_INNERTUBE_CLIENT_VERSION "1.02"

// The request, made inside the page because visitorData lives there. The
// page keeps the answer on window.__cpQ, which is then polled: this engine's
// only way into a page is stringByEvaluatingJavaScriptFromString, and that
// returns a string at once and cannot wait for a round trip.
static NSString *CPResolveScript(void)
{
    return @"(function () {"
    @"  var W = window, m, vid = null;"
    @"  m = location.search.match(/[?&]v=([^&]+)/);"
    @"  if (m) vid = m[1];"
    @"  if (!vid) { m = location.pathname.match(/^\\/(?:shorts|embed|v)\\/([^\\/?#]+)/); if (m) vid = m[1]; }"
    @"  if (!vid) return 'error:not a video page';"
    @"  if (W.__cpQ && W.__cpQ.video === vid && W.__cpQ.state !== 'error') return W.__cpQ.state;"
    // visitorData, three ways. The first two are the shapes ytcfg takes; the
    // third reads it out of the page source, which is where it always is even
    // when ytcfg is not what we expect. Without it this client answers
    // LOGIN_REQUIRED and cookies do not help.
    @"  var vd = null;"
    @"  try { vd = W.ytcfg.data_.INNERTUBE_CONTEXT.client.visitorData; } catch (e) {}"
    @"  if (!vd) { try { vd = W.ytcfg.get('INNERTUBE_CONTEXT').client.visitorData; } catch (e) {} }"
    @"  if (!vd) {"
    @"    m = document.documentElement.innerHTML.match(/\"visitorData\":\"([^\"]+)\"/);"
    @"    if (m) { try { vd = JSON.parse('\"' + m[1] + '\"'); } catch (e) { vd = m[1]; } }"
    @"  }"
    @"  if (!vd) return 'error:this page did not identify itself';"
    @"  W.__cpQ = { state: 'working', video: vid };"
    @"  var body = JSON.stringify({ context: { client: {"
    @"      clientName: '" CP_INNERTUBE_CLIENT "', clientVersion: '" CP_INNERTUBE_CLIENT_VERSION "',"
    @"      hl: 'en', gl: 'US', visitorData: vd } },"
    @"    videoId: vid, contentCheckOk: true, racyCheckOk: true });"
    @"  var x = new XMLHttpRequest();"
    @"  x.open('POST', '/youtubei/v1/player?prettyPrint=false', true);"
    @"  x.setRequestHeader('Content-Type', 'application/json');"
    @"  x.onreadystatechange = function () {"
    @"    if (x.readyState !== 4) return;"
    @"    var q = W.__cpQ;"
    @"    if (!q || q.video !== vid) return;"
    @"    if (x.status !== 200) { q.state = 'error'; q.error = 'YouTube answered ' + x.status; return; }"
    @"    var r; try { r = JSON.parse(x.responseText); }"
    @"    catch (e) { q.state = 'error'; q.error = 'unreadable answer'; return; }"
    @"    var ps = r.playabilityStatus && r.playabilityStatus.status;"
    @"    var sd = r.streamingData || {};"
    @"    var adaptive = sd.adaptiveFormats || [];"
    @"    var seconds = parseInt((r.videoDetails && r.videoDetails.lengthSeconds) || '0', 10);"
    @"    var hls = sd.hlsManifestUrl || '';"
    @"    var vids = [], auds = [], i, out = [];"
    @"    for (i = 0; i < adaptive.length; i++) {"
    @"      var f = adaptive[i], mt = f.mimeType || '';"
    @"      if (!f.url) continue;"
    // H.264 and AAC only. These are what QuickTime, VLC and MPlayer all
    // decode on PowerPC; VP9 and Opus would be software-decoded from scratch
    // and are hopeless on a G4.
    @"      if (mt.indexOf('avc1') >= 0 && f.height) vids.push(f);"
    @"      else if (mt.indexOf('mp4a') >= 0) auds.push(f);"
    @"    }"
    @"    auds.sort(function (a, b) { return (b.bitrate || 0) - (a.bitrate || 0); });"
    @"    var audio = auds.length ? auds[0].url : '';"
    // Tallest first, and for a given height the lower frame rate first:
    // 720p60 exists on many videos and a G4 cannot decode it, while 720p30
    // of the same video plays.
    @"    vids.sort(function (a, b) {"
    @"      return (b.height - a.height) || ((a.fps || 30) - (b.fps || 30)); });"
    @"    for (i = 0; audio && i < vids.length; i++) {"
    @"      var v = vids[i];"
    @"      if (i && vids[i - 1].height === v.height) continue;"
    @"      out.push({ height: v.height, fps: v.fps || 30, url: v.url, audio: audio, prog: 0,"
    @"                 label: String(v.height) + 'p' + ((v.fps || 30) > 30 ? String(v.fps) : ''),"
    @"                 bitrate: v.bitrate || 0, secs: seconds, hls: hls });"
    @"    }"
    @"    if (!out.length) {"
    @"      q.state = 'error';"
    @"      q.error = (ps === 'UNPLAYABLE') ? 'YouTube will not serve this video to us'"
    @"                                      : (ps || 'no streams offered');"
    @"      return;"
    @"    }"
    @"    q.formats = out; q.state = 'ok';"
    @"  };"
    @"  try { x.send(body); }"
    @"  catch (e) { W.__cpQ.state = 'error'; W.__cpQ.error = 'the request was refused'; }"
    @"  return 'working';"
    @"})()";
}

static NSString * const CPPollScript =
    @"(function () {"
    @"  var q = window.__cpQ;"
    @"  if (!q) return 'none';"
    @"  if (q.state === 'working') return 'working';"
    @"  if (q.state === 'error') return 'error:' + (q.error || 'it did not say why');"
    @"  return 'ok:' + JSON.stringify(q.formats);"
    @"})()";

// One resolve in flight, with the delegate to answer and how long we have
// waited. A dictionary rather than a class so nothing needs releasing on a
// path that can be abandoned.
#define CPPollInterval 0.3
#define CPPollLimit    40      // twelve seconds, which is generous on a G3

// Used before they are defined, so declared here: gcc has no idea a class
// method exists until it has read it.
@interface CPYouTubeFormats (Private)
+ (void)poll:(NSArray *)state;
+ (void)answerDelegate:(id)delegate formats:(NSArray *)formats
                 error:(NSString *)error webView:(WebView *)webView;
+ (NSArray *)formatsFromJSON:(NSString *)json;
@end

@implementation CPYouTubeFormats

+ (BOOL)canResolveInWebView:(WebView *)webView
{
    NSString *url;

    if (webView == nil)
        return NO;
    url = [[[[[webView mainFrame] dataSource] request] URL] absoluteString];
    if ([url length] == 0)
        return NO;
    if ([url rangeOfString:@"youtube.com" options:NSCaseInsensitiveSearch].location == NSNotFound
        && [url rangeOfString:@"youtu.be" options:NSCaseInsensitiveSearch].location == NSNotFound)
        return NO;
    // A watch page, a short or an embed. The front page has no video to ask
    // about and answering 'yes' there would put a quality menu on nothing.
    return [url rangeOfString:@"v="].location != NSNotFound
        || [url rangeOfString:@"/shorts/"].location != NSNotFound
        || [url rangeOfString:@"/embed/"].location != NSNotFound;
}

+ (void)resolveInWebView:(WebView *)webView delegate:(id)delegate
{
    NSString *started;

    if (webView == nil) {
        [self answerDelegate:delegate formats:nil error:@"there is no page here" webView:nil];
        return;
    }
    started = [webView stringByEvaluatingJavaScriptFromString:CPResolveScript()];
    if ([started hasPrefix:@"error:"]) {
        [self answerDelegate:delegate formats:nil
                       error:[started substringFromIndex:6] webView:webView];
        return;
    }
    // 'ok' means a previous resolve on this same video already finished, so
    // the answer is there to be read immediately.
    [self poll:[NSArray arrayWithObjects:webView, delegate,
                        [NSNumber numberWithInt:0], nil]];
}

+ (void)poll:(NSArray *)state
{
    WebView *webView = [state objectAtIndex:0];
    id delegate = [state objectAtIndex:1];
    int attempt = [[state objectAtIndex:2] intValue];
    NSString *answer = [webView stringByEvaluatingJavaScriptFromString:CPPollScript];

    if ([answer hasPrefix:@"ok:"]) {
        NSArray *formats = [self formatsFromJSON:[answer substringFromIndex:3]];
        if (CPDebugLogging())
            NSLog(@"Captain Polliwog: the stream list took %.1f seconds",
                  attempt * CPPollInterval);
        if ([formats count] == 0)
            [self answerDelegate:delegate formats:nil
                           error:@"the answer made no sense" webView:webView];
        else
            [self answerDelegate:delegate formats:formats error:nil webView:webView];
        return;
    }
    if ([answer hasPrefix:@"error:"]) {
        [self answerDelegate:delegate formats:nil
                       error:[answer substringFromIndex:6] webView:webView];
        return;
    }
    // 'none' means the page was replaced under us - a navigation, or a
    // reload - and there is nothing left to wait for.
    if ([answer isEqualToString:@"none"] && attempt > 0) {
        [self answerDelegate:delegate formats:nil
                       error:@"the page changed while we were asking" webView:webView];
        return;
    }
    if (attempt >= CPPollLimit) {
        NSLog(@"Captain Polliwog: gave up on the stream list after %.0f seconds",
              attempt * CPPollInterval);
        [self answerDelegate:delegate formats:nil
                       error:@"YouTube did not answer in time" webView:webView];
        return;
    }
    [self performSelector:@selector(poll:)
               withObject:[NSArray arrayWithObjects:webView, delegate,
                                   [NSNumber numberWithInt:attempt + 1], nil]
               afterDelay:CPPollInterval];
}

+ (void)answerDelegate:(id)delegate formats:(NSArray *)formats
                 error:(NSString *)error webView:(WebView *)webView
{
    if ([delegate respondsToSelector:@selector(youTubeFormats:error:forWebView:)])
        [delegate youTubeFormats:formats error:error forWebView:webView];
    else if (error != nil)
        NSLog(@"Captain Polliwog: could not get YouTube's stream list: %@", error);
}

// Two readers for the flat JSON the script above produces. Deliberately not
// a JSON parser: the shape is ours, one level deep, with no nested objects
// and no arrays inside the entries.
static NSString *CPJSONString(NSString *piece, NSString *key)
{
    NSString *needle = [NSString stringWithFormat:@"\"%@\":\"", key];
    NSRange start = [piece rangeOfString:needle];
    NSRange end;
    NSString *value;
    NSMutableString *clean;

    if (start.location == NSNotFound)
        return nil;
    value = [piece substringFromIndex:NSMaxRange(start)];
    end = [value rangeOfString:@"\""];
    if (end.location == NSNotFound)
        return nil;
    // Tiger lacks -stringByReplacingOccurrencesOfString:withString:, so the
    // mutable form, as everywhere else in this project.
    //
    // JSON.stringify leaves / alone and these URLs carry no quotes, so the
    // only escapes that turn up in practice are the one for & - which
    // YouTube's own JSON uses heavily - and, from the page source path, the
    // escaped slash.
    clean = [[value substringToIndex:end.location] mutableCopy];
    [clean replaceOccurrencesOfString:@"\\u0026" withString:@"&"
                             options:0 range:NSMakeRange(0, [clean length])];
    [clean replaceOccurrencesOfString:@"\\/" withString:@"/"
                             options:0 range:NSMakeRange(0, [clean length])];
    return [clean autorelease];
}

static int CPJSONNumber(NSString *piece, NSString *key)
{
    NSString *needle = [NSString stringWithFormat:@"\"%@\":", key];
    NSRange start = [piece rangeOfString:needle];

    if (start.location == NSNotFound)
        return 0;
    return [[piece substringFromIndex:NSMaxRange(start)] intValue];
}

// The page hands back JSON and this engine has no JSONObjectWithData - it
// predates NSJSONSerialization by three releases. The shape is ours and
// fixed, so the fields are pulled out directly rather than by writing a
// parser: a quoted string value and a bare number value, per object.
+ (NSArray *)formatsFromJSON:(NSString *)json
{
    NSMutableArray *formats = [NSMutableArray array];
    NSArray *chunks = [json componentsSeparatedByString:@"{"];
    NSEnumerator *pieces = [chunks objectEnumerator];
    NSString *piece;

    while ((piece = [pieces nextObject]) != nil) {
        NSString *url = CPJSONString(piece, @"url");
        NSString *audio = CPJSONString(piece, @"audio");
        NSString *label = CPJSONString(piece, @"label");
        int height = CPJSONNumber(piece, @"height");
        int fps = CPJSONNumber(piece, @"fps");
        int bitrate = CPJSONNumber(piece, @"bitrate");

        // A progressive entry has no separate sound, which is the whole
        // point of it, so only the address and the height are required.
        if ([url length] == 0 || height <= 0)
            continue;
        [formats addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:height], CPFormatHeight,
            [NSNumber numberWithInt:fps > 0 ? fps : 30], CPFormatFPS,
            url, CPFormatVideoURL,
            audio, CPFormatAudioURL,
            [label length] > 0 ? label
                : [NSString stringWithFormat:@"%dp", height], CPFormatLabel,
            [NSNumber numberWithInt:bitrate], CPFormatBitrate,
            [NSNumber numberWithBool:CPJSONNumber(piece, @"prog") != 0], CPFormatProgressive,
            [NSNumber numberWithInt:CPJSONNumber(piece, @"secs")], CPFormatSeconds,
            CPJSONString(piece, @"hls") != nil ? CPJSONString(piece, @"hls") : @"", CPFormatHLSURL,
            nil]];
    }
    return formats;
}

+ (NSArray *)formatsForWebView:(WebView *)webView
{
    NSString *answer;

    if (webView == nil)
        return nil;
    answer = [webView stringByEvaluatingJavaScriptFromString:CPPollScript];
    if (![answer hasPrefix:@"ok:"])
        return nil;
    return [self formatsFromJSON:[answer substringFromIndex:3]];
}

+ (unsigned)advisableHeightCeiling
{
    int subtype = 0, cpus = 1;
    uint64_t hz = 0;
    uint32_t narrow = 0;
    size_t length;

    length = sizeof subtype;
    if (sysctlbyname("hw.cpusubtype", &subtype, &length, NULL, 0) != 0)
        return 480;
    length = sizeof cpus;
    if (sysctlbyname("hw.ncpu", &cpus, &length, NULL, 0) != 0 || cpus < 1)
        cpus = 1;

    // hw.cpufrequency is eight bytes on some of these systems and four on
    // others, and a four-byte answer read into an eight-byte box lands in the
    // wrong half on a big-endian machine - which would read 1.5GHz as
    // something astronomical. So the width that comes back is checked rather
    // than assumed.
    length = sizeof hz;
    if (sysctlbyname("hw.cpufrequency", &hz, &length, NULL, 0) != 0 || length != sizeof hz) {
        length = sizeof narrow;
        hz = (sysctlbyname("hw.cpufrequency", &narrow, &length, NULL, 0) == 0) ? narrow : 0;
    }

    // "G4" covers a 350MHz Sawtooth and a dual 1.42GHz, which do not belong
    // at the same quality, so the clock decides rather than the family.
    //
    // The one anchor measured on real hardware is a 1.5GHz single G4, which
    // handles 480p: PowerBook5,4, hw.cpufrequency 1499999994, hw.ncpu 1.
    // Everything else here is reasoning outward from that point and should be
    // corrected by anyone who tests a machine it gets wrong.
    //
    // A second processor is counted, but not at face value: H.264 decoding
    // threads well enough to help and nowhere near twice over.
    {
        double effective = (double)hz * (cpus >= 2 ? 1.6 : 1.0);

        switch (subtype) {
        case 9:                             // 750: no vector unit at all
            return 360;
        case 10: case 11:                   // 7400, 7450
            if (hz == 0)
                return 480;                 // no clock to go on: the measured machine
            return effective >= 1.2e9 ? 480 : 360;
        case 100:                           // 970
            if (hz == 0)
                return 1080;
            // Inferred, not measured - there is no G5 here to try it on.
            return effective >= 2.0e9 ? 1080 : 720;
        default:
            return 480;
        }
    }
}

+ (NSDictionary *)formatToHandOverIn:(NSArray *)formats preferredHeight:(unsigned)wanted
{
    // The separate streams, not the manifest, even though the manifest comes
    // ready-muxed.
    //
    // VLC plays a YouTube HLS manifest for some videos and sits at nothing
    // for others - measured, on the same build minutes apart: Big Buck Bunny
    // decoded at 25-57% CPU for two and a half minutes, while another video's
    // manifest left it at 0.1% and 40MB, having resolved the address and
    // chosen a "ps" demuxer. The separate streams behave the same way on
    // every video, and they let the requested height be honoured exactly
    // rather than left to the player's own adaptive logic.
    //
    // The manifest is still resolved and carried on every entry, because it
    // is the better thing when it works and this is worth returning to.
    return [self formatInFormats:formats closestToHeight:wanted];
}

+ (NSDictionary *)formatInFormats:(NSArray *)formats closestToHeight:(unsigned)wanted
{
    NSEnumerator *entries;
    NSDictionary *entry;
    NSDictionary *best = nil;
    NSDictionary *shortest = nil;

    // Tallest that is no taller than asked for. Never rounds up: a G3 handed
    // 720p because 480p was missing plays a slideshow.
    entries = [formats objectEnumerator];
    while ((entry = [entries nextObject]) != nil) {
        unsigned height = (unsigned)[[entry objectForKey:CPFormatHeight] intValue];
        if (shortest == nil
            || height < (unsigned)[[shortest objectForKey:CPFormatHeight] intValue])
            shortest = entry;
        if (height > wanted)
            continue;
        if (best == nil
            || height > (unsigned)[[best objectForKey:CPFormatHeight] intValue])
            best = entry;
    }
    // Everything on offer is taller than we want, so take the least bad.
    return best != nil ? best : shortest;
}

@end
