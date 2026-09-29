/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPScriptWatchdog.h"
#import "CPSettings.h"
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

// What the limit becomes in Lite mode. A page's own scripts do their work in
// short pieces and never come near this; what it catches is the kind that
// settles in - a layout that keeps re-measuring itself, a frame loop nobody
// stops, a parser chewing through something far too large. Three seconds is
// long enough that nothing ordinary notices and short enough that a G3 is not
// held for a quarter of a minute.
#define CPSparingTimeLimit 3.0

// What the limit becomes when the machine is running out of memory. Short
// enough that anything doing work is stopped, not zero: a page still has to
// be able to answer a click.
#define CPEmergencyTimeLimit 0.25

// Kept so the limit can be changed after it is first set. The group is
// shared by every page, which is why installing once is enough.
static CPJSSetExecutionTimeLimitFunction gSetLimit = NULL;
static CPJSContextGroupRef gGroup = NULL;
static BOOL gEmergency = NO;

static bool CPStopLongScript(CPJSContextRef context, void *info)
{
    if (gEmergency)
        NSLog(@"Captain Polliwog: stopped a script to free memory");
    else
        NSLog(@"Captain Polliwog: stopped a script that ran for more than %.0f seconds", CPScriptTimeLimit);
    return true;
}

// Used before it is defined, so declared here: gcc has no idea a class method
// exists until it has read it.
@interface CPScriptWatchdog (Private)
+ (double)currentLimit;
@end

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
    if (![[CPSettings sharedSettings] stopsLongScripts])
        return;

    getGroup = (CPJSContextGetGroupFunction)dlsym(RTLD_DEFAULT, "JSContextGetGroup");
    setLimit = (CPJSSetExecutionTimeLimitFunction)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
    if (getGroup == NULL || setLimit == NULL)
        return;
    if ([frame respondsToSelector:@selector(globalContext)])
        context = (CPJSContextRef)[frame performSelector:@selector(globalContext)];
    if (context == NULL)
        return;
    gSetLimit = setLimit;
    gGroup = getGroup(context);
    setLimit(gGroup, [self currentLimit], CPStopLongScript, NULL);
}

// Whichever is shortest of the reasons to be strict.
+ (double)currentLimit
{
    if (gEmergency)
        return CPEmergencyTimeLimit;
    return [[CPSettings sharedSettings] runsScriptsSparingly]
        ? CPSparingTimeLimit : CPScriptTimeLimit;
}

// Called when the setting changes, so it takes effect without a relaunch.
+ (void)limitChanged
{
    if (gSetLimit != NULL && gGroup != NULL)
        gSetLimit(gGroup, [self currentLimit], CPStopLongScript, NULL);
}

+ (void)setEmergencyTimeLimit:(BOOL)emergency
{
    if (gSetLimit == NULL || gGroup == NULL || emergency == gEmergency)
        return;
    gEmergency = emergency;
    gSetLimit(gGroup, [self currentLimit], CPStopLongScript, NULL);
    NSLog(@"Captain Polliwog: script time limit now %.2fs%@",
          [self currentLimit],
          emergency ? @" (memory)" : @" (normal)");
}

@end
