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

@end
