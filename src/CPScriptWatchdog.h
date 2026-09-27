/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class WebView;

// Page scripts run on the same thread as the windows, so a script that runs
// on and on (YouTube, on a G4 interpreting JavaScript) freezes the whole
// browser. JavaScriptCore can stop a script that has run too long, as
// Safari's "slow script" dialog did; this sets that limit. The WebKit that
// comes with Tiger and Leopard has no such control, so there it does nothing.
@interface CPScriptWatchdog : NSObject

// Idempotent: every page shares one JavaScript engine, so once is enough.
+ (void)installForWebView:(WebView *)webView;

// Cuts the limit to a fraction of a second, so that any script which runs at
// all is stopped, and puts it back again.
//
// This is what "stopping a page" actually needs. Turning JavaScript off in a
// WebView's preferences governs whether a page may start running scripts; it
// does not touch the timers a loaded page has already scheduled, which was
// measured: after the front tab had its scripts "stopped", its JavaScript
// objects still went from 2,812,342 to 3,194,334.
//
// The limit belongs to the context group, which every page shares, so this
// is not selective - under memory pressure that is the intent, and by the
// time it is reached every other tab has been discarded anyway.
+ (void)setEmergencyTimeLimit:(BOOL)emergency;

@end
