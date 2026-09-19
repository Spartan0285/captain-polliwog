/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class WebView;

// Site icons for the address bar, the tabs and the start page. Fetched
// after a page has loaded, through the browser's own networking (so from
// the disk cache when they can be), and kept for each site while the
// browser runs.
@interface CPFavicons : NSObject

// The icon known for the URL's site, or nil.
+ (NSImage *)iconForURL:(NSURL *)url;

// Looks for the loaded page's icon, then tells the target
// -performSelector:withObject: with the image (nil if the page has none).
+ (void)loadIconForPage:(WebView *)webView URL:(NSURL *)url target:(id)target action:(SEL)action;

// The icon as a data: URL, for pages the browser makes itself, or nil.
+ (NSString *)dataURLForURL:(NSURL *)url;

@end
