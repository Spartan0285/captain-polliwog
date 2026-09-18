/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPScriptWatchdog.h"
#import <WebKit/WebKit.h>
#include <dlfcn.h>
#include <stdbool.h>

// JavaScriptCore's C API, looked up at run time: the 10.4 SDK has no
// headers for it, and the time limit exists only in newer engines.
typedef const struct OpaqueJSContextGroup *CPJSContextGroupRef;
typedef const struct OpaqueJSContext *CPJSContextRef;
typedef bool (*CPJSShouldTerminateCallback)(CPJSContextRef context, void *info);
typedef CPJSContextGroupRef (*CPJSContextGetGroupFunction)(CPJSContextRef context);
typedef void (*CPJSSetExecutionTimeLimitFunction)(CPJSContextGroupRef group, double limit,
                                                  CPJSShouldTerminateCallback callback, void *info);

// Seconds a single script may run without a break. Real pages do their work
// in short pieces; even interpreted on a 500MHz G3, nothing well-behaved
// comes near this.
#define CPScriptTimeLimit 15.0

static bool CPStopLongScript(CPJSContextRef context, void *info)
{
    NSLog(@"Captain Polliwog: stopped a script that ran for more than %.0f seconds", CPScriptTimeLimit);
    return true;
}

@implementation CPScriptWatchdog

+ (void)installForWebView:(WebView *)webView
{
    static BOOL installed = NO;
    CPJSContextGetGroupFunction getGroup;
    CPJSSetExecutionTimeLimitFunction setLimit;
    WebFrame *frame = [webView mainFrame];
    CPJSContextRef context = NULL;

    if (installed)
        return;
    installed = YES;

    getGroup = (CPJSContextGetGroupFunction)dlsym(RTLD_DEFAULT, "JSContextGetGroup");
    setLimit = (CPJSSetExecutionTimeLimitFunction)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
    if (getGroup == NULL || setLimit == NULL)
        return;
    if ([frame respondsToSelector:@selector(globalContext)])
        context = (CPJSContextRef)[frame performSelector:@selector(globalContext)];
    if (context == NULL)
        return;
    setLimit(getGroup(context), CPScriptTimeLimit, CPStopLongScript, NULL);
}

@end
