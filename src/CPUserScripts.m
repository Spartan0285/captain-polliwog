/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPUserScripts.h"
#import "CPSettings.h"
#import "CPDebugSnapshot.h"
#import "CPExternalPlayer.h"
#import <WebKit/WebKit.h>

// -[WebView _addUserScriptToGroup:...], private WebKit API (Safari 4 and
// later), looked up at run time: the 10.4 SDK doesn't declare it.
typedef void (*CPAddUserScriptFunction)(id, SEL, NSString *, id, NSString *, NSURL *,
                                        NSArray *, NSArray *, int, int);

// WebUserScriptInjectionTime and WebUserContentInjectedFrames.
#define CPInjectAtDocumentStart 0
#define CPInjectInAllFrames 0

@implementation CPUserScripts

+ (void)installForGroup:(NSString *)groupName
{
    static BOOL installed = NO;
    SEL addUserScript = @selector(_addUserScriptToGroup:world:source:url:whitelist:blacklist:injectionTime:injectedFrames:);
    Class worldClass = NSClassFromString(@"WebScriptWorld");
    NSString *path;
    NSString *source;
    id world;

    if (installed)
        return;
    installed = YES;
    if (![[CPSettings sharedSettings] usesCompatibilityScripts])
        return;

    if (worldClass == Nil || ![worldClass respondsToSelector:@selector(standardWorld)]
        || ![WebView respondsToSelector:addUserScript])
        return;
    path = [[NSBundle mainBundle] pathForResource:@"polyfills" ofType:@"js"];
    source = path != nil ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
    if (source == nil)
        return;

    // The page's own world, so that what it adds is what the page sees.
    world = [worldClass performSelector:@selector(standardWorld)];

    // Settings the polyfills read, injected before them so they are in place
    // by the time anything looks. A global rather than a bridge: the page can
    // see it either way, and there is nothing here worth hiding.
    {
        NSString *player = [CPExternalPlayer preferredPlayer];
        NSString *name = player != nil ? [CPExternalPlayer displayNameForPlayer:player] : @"Media Player";
        NSString *flags = [NSString stringWithFormat:
            @"window.__polliwog = { playButton: %@, playerName: \"%@\", autoplay: %@ };",
            ([[CPSettings sharedSettings] showsVideoPlayButton] && player != nil) ? @"true" : @"false",
            [[name componentsSeparatedByString:@"\""] componentsJoinedByString:@""],   // Tiger has no -stringByReplacing...
            [[CPSettings sharedSettings] autoplaysVideo] ? @"true" : @"false"];
        ((CPAddUserScriptFunction)[WebView methodForSelector:addUserScript])(
            [WebView class], addUserScript, groupName, world, flags,
            [NSURL URLWithString:@"polliwog-settings:flags"],
            nil, nil, CPInjectAtDocumentStart, CPInjectInAllFrames);
    }

    ((CPAddUserScriptFunction)[WebView methodForSelector:addUserScript])(
        [WebView class], addUserScript, groupName, world, source, [NSURL fileURLWithPath:path],
        nil, nil, CPInjectAtDocumentStart, CPInjectInAllFrames);

    // Debugging: the console gets only an uncaught error's message; log its
    // stack too, which says where in a minified bundle it came from.
    if (CPDebugLogging()) {
        NSString *stacks = @"addEventListener('error', function (e) { if (e.error && e.error.stack) console.log('Uncaught ' + e.message + ' | stack: ' + String(e.error.stack).slice(0, 1500)); }, true);"
            // ...and which fetches fail, since WebKit's message is only "Type error".
            @"if (window.fetch) { var polliwogFetch = window.fetch; window.fetch = function (input, init) { var url = input && input.url ? input.url : String(input); var p; try { p = polliwogFetch.apply(this, arguments); } catch (e) { console.log('Fetch threw: ' + url + ' ' + JSON.stringify(init || {}).slice(0, 300) + ' -> ' + e); throw e; } return p.then(null, function (e) { console.log('Fetch failed: ' + url + ' ' + JSON.stringify(init || {}).slice(0, 300) + ' -> ' + e); throw e; }); }; }";
        ((CPAddUserScriptFunction)[WebView methodForSelector:addUserScript])(
            [WebView class], addUserScript, groupName, world, stacks, [NSURL URLWithString:@"polliwog-debug:stacks"],
            nil, nil, CPInjectAtDocumentStart, CPInjectInAllFrames);
    }
}

@end
