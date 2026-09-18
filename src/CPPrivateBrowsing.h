/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

extern NSString * const CPPrivateBrowsingDidChangeNotification;

// Private browsing, for the whole app as it was in Safari at the time.
//
// While it is on, WebKit records no history and Captain Polliwog's disk cache
// stores nothing. Cookies are the hard part: a page's JavaScript reaches the
// system cookie store directly, and Captain Polliwog cannot swap that store
// for one kept in memory (it is also Safari's). Leopard's WebKit keeps a
// private session's cookies apart by itself; Tiger's does not. So, as
// Safari 4 did, the cookies that exist when private browsing starts are
// noted, and when it ends -- or the app quits -- every cookie added during
// the session is deleted and any that were changed are put back. Measured:
// on Tiger this removed the session's cookie; on Leopard there was nothing
// left to remove. Always starts off at launch.
@interface CPPrivateBrowsing : NSObject
{
    BOOL     enabled;
    NSArray *cookiesAtStart;
}

+ (CPPrivateBrowsing *)sharedPrivateBrowsing;

- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)flag;

@end
