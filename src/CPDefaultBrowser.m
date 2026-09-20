/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPDefaultBrowser.h"

#include <ApplicationServices/ApplicationServices.h>

@implementation CPDefaultBrowser

+ (NSString *)bundleIdentifier
{
    NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];
    return identifier != nil ? identifier : @"org.captainpolliwog.browser";
}

// The bundle identifier of whatever handles http at the moment.
+ (NSString *)currentHandler
{
    CFStringRef handler = LSCopyDefaultHandlerForURLScheme(CFSTR("http"));
    return handler != NULL ? [(NSString *)handler autorelease] : nil;
}

+ (BOOL)isDefault
{
    NSString *handler = [self currentHandler];
    return handler != nil
        && [handler caseInsensitiveCompare:[self bundleIdentifier]] == NSOrderedSame;
}

+ (NSString *)currentDefaultName
{
    NSString *handler = [self currentHandler];
    NSString *path;

    if (handler == nil)
        return nil;
    path = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:handler];
    if (path == nil)
        return handler;
    return [[NSFileManager defaultManager] displayNameAtPath:path];
}

+ (BOOL)makeDefault
{
    NSString *identifier = [self bundleIdentifier];
    OSStatus httpResult, httpsResult;

    // Launch Services keeps one handler per scheme, and a browser wants both.
    // This copy has to be registered with Launch Services to be eligible,
    // which lsregister does when the app is installed; asking here as well
    // costs nothing and covers a copy that was only ever dragged into place.
    LSRegisterURL((CFURLRef)[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]], true);

    httpResult = LSSetDefaultHandlerForURLScheme(CFSTR("http"), (CFStringRef)identifier);
    httpsResult = LSSetDefaultHandlerForURLScheme(CFSTR("https"), (CFStringRef)identifier);
    if (httpResult != noErr || httpsResult != noErr) {
        NSLog(@"Captain Polliwog: could not become the default browser (%d, %d)",
              (int)httpResult, (int)httpsResult);
        return NO;
    }
    return YES;
}

@end
