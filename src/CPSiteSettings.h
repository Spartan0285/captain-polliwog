/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Settings for single websites, as Safari's "Settings for This Website":
// text size, Reader by default, and JavaScript and images (which cost the
// most on these Macs) on or off. The site version (desktop, mobile, basic)
// is kept by CPSiteModes. Sites are keyed without "www.".
@interface CPSiteSettings : NSObject

+ (float)textSizeForURL:(NSURL *)url;                 // 1.0 when unset
+ (void)setTextSize:(float)size forURL:(NSURL *)url;
+ (BOOL)usesReaderForURL:(NSURL *)url;
+ (void)setUsesReader:(BOOL)flag forURL:(NSURL *)url;
// YES/NO when the site has its own setting; else the browser-wide one.
+ (BOOL)javaScriptEnabledForURL:(NSURL *)url;
+ (void)setJavaScriptEnabled:(BOOL)flag forURL:(NSURL *)url;
+ (BOOL)imagesEnabledForURL:(NSURL *)url;
+ (void)setImagesEnabled:(BOOL)flag forURL:(NSURL *)url;
+ (NSString *)siteNameForURL:(NSURL *)url;

@end

extern NSString * const CPSiteSettingsDidChangeNotification;
