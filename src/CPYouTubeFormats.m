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

// Pinned on purpose. yt-dlp's own source warns that ANDROID_VR above 1.65
// "may return SABR streams only" - a streaming protocol with no plain URLs
// at all, which would leave us exactly where we started. When this stops
// working, the value to copy is in yt-dlp's youtube/_base.py.
#define CP_INNERTUBE_CLIENT_VERSION "1.65.10"

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
    // when ytcfg is not what we expect. Without it YouTube answers
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
    @"      clientName: 'ANDROID_VR', clientVersion: '" CP_INNERTUBE_CLIENT_VERSION "',"
    @"      hl: 'en', visitorData: vd } },"
    @"    videoId: vid, contentCheckOk: true, racyCheckOk: true });"
    // Two requests, because no single client answers both halves.
    // ANDROID_VR is the only one that hands out adaptive URLs; plain ANDROID
    // is the only one whose progressive itag 18 URL can be read right
    // through. See the comment on the ladder below for why that matters.
    @"  var post = function (body, done) {"
    @"    var x = new XMLHttpRequest();"
    @"    x.open('POST', '/youtubei/v1/player?prettyPrint=false', true);"
    @"    x.setRequestHeader('Content-Type', 'application/json');"
    @"    x.onreadystatechange = function () {"
    @"      if (x.readyState !== 4) return;"
    @"      if (x.status !== 200) { done(null, 'YouTube answered ' + x.status); return; }"
    @"      try { done(JSON.parse(x.responseText), null); }"
    @"      catch (e) { done(null, 'unreadable answer'); }"
    @"    };"
    @"    try { x.send(body); } catch (e) { done(null, 'the request was refused'); }"
    @"  };"
    @"  post(body, function (r, failed) {"
    @"    var q = W.__cpQ;"
    @"    if (!q || q.video !== vid) return;"
    @"    if (failed) { q.state = 'error'; q.error = failed; return; }"
    @"    var ps = r.playabilityStatus && r.playabilityStatus.status;"
    @"    var sd = r.streamingData || {};"
    @"    var adaptive = sd.adaptiveFormats || [];"
    @"    if (!adaptive.length) {"
    // UNPLAYABLE here is usually a "made for kids" video, which this client
    // is not allowed to fetch. Reported rather than worked around: the
    // hand-off falls back to the 360p the page is already playing.
    // Not fatal. The progressive stream below comes from a different client
    // and often answers when this one will not, and it is the one that plays
    // to the end anyway.
    @"      q.why = (ps === 'UNPLAYABLE') ? 'YouTube will not serve the better qualities'"
    @"                                    : (ps || 'no adaptive streams offered');"
    @"    }"
    @"    var vids = [], auds = [], i;"
    @"    for (i = 0; i < adaptive.length; i++) {"
    @"      var f = adaptive[i], mt = f.mimeType || '';"
    @"      if (!f.url) continue;"
    // H.264 only, and AAC only. These are what QuickTime, VLC and MPlayer
    // all decode on PowerPC; VP9 and Opus would be software-decoded from
    // scratch and are hopeless on a G4.
    @"      if (mt.indexOf('avc1') >= 0 && f.height) vids.push(f);"
    @"      else if (mt.indexOf('mp4a') >= 0) auds.push(f);"
    @"    }"
    @"    auds.sort(function (a, b) { return (b.bitrate || 0) - (a.bitrate || 0); });"
    @"    var audio = auds.length ? auds[0].url : '';"
    // Tallest first, and for a given height the *lower* frame rate first:
    // 720p60 exists on many videos and a G4 cannot decode it, while 720p30
    // of the same video plays.
    @"    vids.sort(function (a, b) {"
    @"      return (b.height - a.height) || ((a.fps || 30) - (b.fps || 30)); });"
    @"    var out = [];"
    @"    for (i = 0; audio && i < vids.length; i++) {"
    @"      var v = vids[i];"
    @"      if (i && vids[i - 1].height === v.height) continue;"
    @"      out.push({ height: v.height, fps: v.fps || 30, url: v.url, audio: audio,"
    @"                 label: String(v.height) + 'p' + ((v.fps || 30) > 30 ? String(v.fps) : ''),"
    @"                 bitrate: v.bitrate || 0 });"
    @"    }"
    @"    var seconds = parseInt((r.videoDetails && r.videoDetails.lengthSeconds) || '0', 10);"
    // Now the progressive stream, from the plain ANDROID client. This is the
    // one that can actually be played to the end - see formatsForWebView's
    // note on the sixty-second wall - so it is always fetched, and it is what
    // a video longer than that wall is handed.
    @"    var second = JSON.stringify({ context: { client: {"
    @"        clientName: 'ANDROID', clientVersion: '21.02.35', androidSdkVersion: 30,"
    @"        osName: 'Android', osVersion: '11', hl: 'en', gl: 'US' } },"
    @"      videoId: vid, contentCheckOk: true, racyCheckOk: true });"
    @"    post(second, function (r2, failed2) {"
    @"      var q2 = W.__cpQ, i2, f2, prog = '';"
    @"      if (!q2 || q2.video !== vid) return;"
    @"      var fs = (r2 && r2.streamingData && r2.streamingData.formats) || [];"
    @"      for (i2 = 0; i2 < fs.length; i2++) {"
    @"        f2 = fs[i2];"
    @"        if (f2.itag === 18 && f2.url) { prog = f2.url; break; }"
    @"      }"
    @"      if (prog)"
    @"        out.unshift({ height: 360, fps: 30, url: prog, audio: '', prog: 1,"
    @"                      label: '360p', bitrate: 0, secs: seconds });"
    @"      for (i2 = 0; i2 < out.length; i2++) out[i2].secs = seconds;"
    @"      if (!out.length) {"
    @"        q2.state = 'error';"
    @"        q2.error = q2.why || 'nothing playable offered';"
    @"        return;"
    @"      }"
    @"      q2.formats = out; q2.state = 'ok';"
    @"    });"
    @"  });"
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
    int subtype = 0;
    size_t length = sizeof subtype;

    if (sysctlbyname("hw.cpusubtype", &subtype, &length, NULL, 0) != 0)
        return 720;
    switch (subtype) {
    case 9:             return 480;     // 750: PowerVLC manages 720p and
                                        // cannot keep up with it
    case 10: case 11:   return 720;     // 7400, 7450: 720p, measured
    case 100:           return 1080;    // 970
    default:            return 720;
    }
}

// How much of a video YouTube will actually let us read above 360p. The
// shortest wall measured was 62 seconds; this is under it on purpose, because
// being wrong in the other direction hands someone a video that stops.
#define CPReadableSeconds 55

+ (NSDictionary *)formatToHandOverIn:(NSArray *)formats preferredHeight:(unsigned)wanted
{
    NSEnumerator *entries = [formats objectEnumerator];
    NSDictionary *entry;
    NSDictionary *progressive = nil;
    int seconds = 0;

    while ((entry = [entries nextObject]) != nil) {
        if ([[entry objectForKey:CPFormatProgressive] boolValue] && progressive == nil)
            progressive = entry;
        if ([[entry objectForKey:CPFormatSeconds] intValue] > seconds)
            seconds = [[entry objectForKey:CPFormatSeconds] intValue];
    }
    // Long enough that the better qualities would run out partway.
    if (seconds > CPReadableSeconds && progressive != nil)
        return progressive;
    if (seconds > CPReadableSeconds)
        return nil;     // nothing here can be played to the end
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
