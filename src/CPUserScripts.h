/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Scripts the browser runs in every page before the page's own:
// Resources/polyfills.js, which adds newer web platform features the
// engine lacks (AbortController, Array.prototype.flat, IntersectionObserver
// and so on). Uses WebKit's user script support, which Tiger's original
// WebKit lacks; there it does nothing.
@interface CPUserScripts : NSObject

// Idempotent: user scripts belong to the WebView group, which every tab
// shares.
+ (void)installForGroup:(NSString *)groupName;

@end
