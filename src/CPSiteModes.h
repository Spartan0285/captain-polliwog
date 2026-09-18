/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Which version of a website to ask for. Sites decide what to send from the
// browser's user agent, and a lighter device gets a lighter page: less
// script, smaller images. That is most of the work on these machines.
typedef enum {
    CPSiteModeDesktop = 0,  // the browser's own identity
    CPSiteModeMobile  = 1,  // an iPhone whose Safari matches this engine
    CPSiteModeBasic   = 2   // Opera Mini: the lightest pages sites still offer
} CPSiteMode;

extern NSString * const CPSiteModesDidChangeNotification;

// A default for every site, and choices made for particular sites. A choice
// is kept for the site without "www." or "m.", so it survives a site sending
// its mobile visitors to m.example.com, and covers the site's subdomains.
// In private browsing, choices last only until private browsing ends.
@interface CPSiteModes : NSObject

+ (CPSiteMode)defaultMode;
+ (void)setDefaultMode:(CPSiteMode)mode;

// The mode to use for a page: the site's own choice, or the default.
+ (CPSiteMode)modeForURL:(NSURL *)url;
// Whether the site has a choice of its own.
+ (BOOL)hasModeForURL:(NSURL *)url;
+ (void)setMode:(CPSiteMode)mode forURL:(NSURL *)url;
+ (void)removeModeForURL:(NSURL *)url;

// The user agent to send, or nil for the browser's own.
+ (NSString *)userAgentForMode:(CPSiteMode)mode;
+ (NSString *)nameForMode:(CPSiteMode)mode;

// Only web pages have site versions.
+ (BOOL)appliesToURL:(NSURL *)url;

@end
