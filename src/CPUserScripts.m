/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPUserScripts.h"
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

    if (worldClass == Nil || ![worldClass respondsToSelector:@selector(standardWorld)]
        || ![WebView respondsToSelector:addUserScript])
        return;
    path = [[NSBundle mainBundle] pathForResource:@"polyfills" ofType:@"js"];
    source = path != nil ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
    if (source == nil)
        return;

    // The page's own world, so that what it adds is what the page sees.
    world = [worldClass performSelector:@selector(standardWorld)];
    ((CPAddUserScriptFunction)[WebView methodForSelector:addUserScript])(
        [WebView class], addUserScript, groupName, world, source, [NSURL fileURLWithPath:path],
        nil, nil, CPInjectAtDocumentStart, CPInjectInAllFrames);
}

@end
