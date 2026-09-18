/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPPrivateBrowsing.h"
#import "CPHTTPCache.h"
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>

NSString * const CPPrivateBrowsingDidChangeNotification = @"CPPrivateBrowsingDidChange";

static NSString *CPCookieKey(NSHTTPCookie *cookie)
{
    return [NSString stringWithFormat:@"%@|%@|%@", [cookie domain], [cookie path], [cookie name]];
}

@interface CPPrivateBrowsing (Private)
- (void)restoreCookies;
@end

@implementation CPPrivateBrowsing (Private)

// Puts the cookie store back as it was when private browsing began.
- (void)restoreCookies
{
    NSHTTPCookieStorage *store = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSMutableDictionary *before = [NSMutableDictionary dictionary];
    NSArray *now = [[[store cookies] copy] autorelease];
    NSArray *deleted;
    unsigned removed = 0;
    unsigned restored = 0;
    unsigned index;

    for (index = 0; index < [cookiesAtStart count]; index++) {
        NSHTTPCookie *cookie = [cookiesAtStart objectAtIndex:index];
        [before setObject:cookie forKey:CPCookieKey(cookie)];
    }

    for (index = 0; index < [now count]; index++) {
        NSHTTPCookie *cookie = [now objectAtIndex:index];
        NSHTTPCookie *original = [before objectForKey:CPCookieKey(cookie)];
        if (original == nil) {
            [store deleteCookie:cookie];
            removed++;
        } else if (![[original value] isEqualToString:[cookie value]]) {
            [store setCookie:original];
            restored++;
        }
        [before removeObjectForKey:CPCookieKey(cookie)];
    }

    // Anything deleted during the session comes back too.
    deleted = [before allValues];
    for (index = 0; index < [deleted count]; index++)
        [store setCookie:[deleted objectAtIndex:index]];
    restored += [deleted count];

    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: private browsing ended: %u cookies removed, %u restored "
              @"(%u at start, %u at end)", removed, restored, [cookiesAtStart count], [now count]);
}

@end

@implementation CPPrivateBrowsing

+ (CPPrivateBrowsing *)sharedPrivateBrowsing
{
    static CPPrivateBrowsing *shared = nil;
    if (shared == nil)
        shared = [[CPPrivateBrowsing alloc] init];
    return shared;
}

- (void)dealloc
{
    [cookiesAtStart release];
    [super dealloc];
}

- (BOOL)isEnabled
{
    return enabled;
}

- (void)setEnabled:(BOOL)flag
{
    Class webCache = NSClassFromString(@"WebCache");

    if (flag == enabled)
        return;

    if (flag) {
        [cookiesAtStart release];
        cookiesAtStart = [[[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies] copy];
        enabled = YES;
        [[WebPreferences standardPreferences] setPrivateBrowsingEnabled:YES];
    } else {
        enabled = NO;
        [[WebPreferences standardPreferences] setPrivateBrowsingEnabled:NO];
        [self restoreCookies];
        [cookiesAtStart release];
        cookiesAtStart = nil;
        // Pages from the private session should not linger in memory either.
        if ([webCache respondsToSelector:@selector(empty)])
            [webCache performSelector:@selector(empty)];
        [CPHTTPCache emptyMemoryCache];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:CPPrivateBrowsingDidChangeNotification
                                                        object:self];
}

@end
