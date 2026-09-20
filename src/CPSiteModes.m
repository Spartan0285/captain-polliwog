/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPSiteModes.h"
#import "CPPrivateBrowsing.h"
#import <WebKit/WebKit.h>

NSString * const CPSiteModesDidChangeNotification = @"CPSiteModesDidChange";

static NSString * const CPDefaultSiteModeKey = @"CPDefaultSiteMode";
static NSString * const CPSiteModesKey       = @"CPSiteModes";

// Choices made during private browsing, forgotten when it ends.
static NSMutableDictionary *CPPrivateSiteModes = nil;

// "www.example.com", "m.example.com" and "example.com" are one site.
static NSString *CPSiteKey(NSURL *url)
{
    NSString *host = [[url host] lowercaseString];
    NSArray *prefixes = [NSArray arrayWithObjects:@"www.", @"m.", @"mobile.", @"wap.", nil];
    unsigned index;
    BOOL stripped = YES;

    if ([host length] == 0)
        return nil;
    while (stripped) {
        stripped = NO;
        for (index = 0; index < [prefixes count]; index++) {
            NSString *prefix = [prefixes objectAtIndex:index];
            NSString *rest;
            if (![host hasPrefix:prefix])
                continue;
            rest = [host substringFromIndex:[prefix length]];
            // Keep at least "example.com".
            if ([rest rangeOfString:@"."].location == NSNotFound)
                continue;
            host = rest;
            stripped = YES;
        }
    }
    return host;
}

// The site's own choice, looking at the site and then its parent domains, so
// a choice for example.com also covers news.example.com.
static NSNumber *CPStoredMode(NSDictionary *modes, NSString *key)
{
    while ([key length] > 0) {
        NSNumber *mode = [modes objectForKey:key];
        NSRange dot;
        if (mode != nil)
            return mode;
        dot = [key rangeOfString:@"."];
        if (dot.location == NSNotFound)
            break;
        key = [key substringFromIndex:dot.location + 1];
        if ([key rangeOfString:@"."].location == NSNotFound)
            break;  // no choice is ever kept for a bare "com"
    }
    return nil;
}

// WebKit's version, without the leading OS digit Leopard and later add
// ("5534.50.2" is WebKit 534).
static int CPWebKitMajorVersion(void)
{
    NSString *version = [[[NSBundle bundleForClass:[WebView class]] infoDictionary] objectForKey:@"CFBundleVersion"];
    int major = [version intValue];

    if (major >= 1000)
        major %= 1000;
    return major;
}

@interface CPSiteModes (Private)
+ (void)privateBrowsingChanged:(NSNotification *)notification;
+ (void)changed;
@end

@implementation CPSiteModes (Private)

+ (void)privateBrowsingChanged:(NSNotification *)notification
{
    [CPPrivateSiteModes removeAllObjects];
    [self changed];
}

+ (void)changed
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CPSiteModesDidChangeNotification object:self];
}

@end

@implementation CPSiteModes

+ (void)initialize
{
    if (self != [CPSiteModes class])
        return;
    CPPrivateSiteModes = [[NSMutableDictionary alloc] init];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
     [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:CPSiteModeDesktop] forKey:CPDefaultSiteModeKey]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(privateBrowsingChanged:)
                                                 name:CPPrivateBrowsingDidChangeNotification object:nil];
}

+ (CPSiteMode)defaultMode
{
    int mode = [[NSUserDefaults standardUserDefaults] integerForKey:CPDefaultSiteModeKey];
    if (mode < CPSiteModeDesktop || mode > CPSiteModeBasic)
        return CPSiteModeDesktop;
    return (CPSiteMode)mode;
}

+ (void)setDefaultMode:(CPSiteMode)mode
{
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:CPDefaultSiteModeKey];
    [self changed];
}

+ (BOOL)appliesToURL:(NSURL *)url
{
    NSString *scheme = [[url scheme] lowercaseString];
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && CPSiteKey(url) != nil;
}

+ (BOOL)hasModeForURL:(NSURL *)url
{
    NSString *key = CPSiteKey(url);

    if (key == nil)
        return NO;
    if (CPStoredMode(CPPrivateSiteModes, key) != nil)
        return YES;
    return CPStoredMode([[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteModesKey], key) != nil;
}

// Sites whose desktop version is too much for these Macs, or doesn't work
// on their engines, where the mobile one does: YouTube's desktop app never
// shows anything, its mobile site works. Below the person's own choice
// for a site, above the default for all sites.
static NSDictionary *CPBuiltInSiteModes(void)
{
    static NSDictionary *modes = nil;
    if (modes == nil)
        modes = [[NSDictionary alloc] initWithObjectsAndKeys:
                 [NSNumber numberWithInt:CPSiteModeMobile], @"youtube.com",
                 nil];
    return modes;
}

+ (CPSiteMode)defaultModeForURL:(NSURL *)url
{
    NSString *key = CPSiteKey(url);
    NSNumber *mode = key != nil ? CPStoredMode(CPBuiltInSiteModes(), key) : nil;
    CPSiteMode defaultMode = [self defaultMode];
    // A default of Mobile or Basic for every site already goes further.
    if (mode == nil || defaultMode != CPSiteModeDesktop)
        return defaultMode;
    return (CPSiteMode)[mode intValue];
}

+ (CPSiteMode)modeForURL:(NSURL *)url
{
    NSString *key = CPSiteKey(url);
    NSNumber *mode;

    if (key == nil)
        return CPSiteModeDesktop;
    mode = CPStoredMode(CPPrivateSiteModes, key);
    if (mode == nil)
        mode = CPStoredMode([[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteModesKey], key);
    if (mode == nil)
        return [self defaultModeForURL:url];
    return (CPSiteMode)[mode intValue];
}

+ (void)setMode:(CPSiteMode)mode forURL:(NSURL *)url
{
    NSString *key = CPSiteKey(url);
    NSMutableDictionary *modes;

    if (key == nil)
        return;
    if ([[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled]) {
        [CPPrivateSiteModes setObject:[NSNumber numberWithInt:mode] forKey:key];
    } else {
        modes = [NSMutableDictionary dictionaryWithDictionary:
                 [[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteModesKey]];
        [modes setObject:[NSNumber numberWithInt:mode] forKey:key];
        [[NSUserDefaults standardUserDefaults] setObject:modes forKey:CPSiteModesKey];
    }
    [self changed];
}

+ (NSArray *)configuredSites
{
    NSMutableSet *sites = [NSMutableSet set];
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteModesKey];
    if (saved != nil)
        [sites addObjectsFromArray:[saved allKeys]];
    if (CPPrivateSiteModes != nil)
        [sites addObjectsFromArray:[CPPrivateSiteModes allKeys]];
    return [[sites allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

+ (CPSiteMode)modeForSite:(NSString *)site
{
    NSNumber *mode = [CPPrivateSiteModes objectForKey:site];
    if (mode == nil)
        mode = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteModesKey]
                objectForKey:site];
    return mode != nil ? (CPSiteMode)[mode intValue] : [self defaultMode];
}

+ (void)removeModeForSite:(NSString *)site
{
    NSMutableDictionary *modes = [NSMutableDictionary dictionaryWithDictionary:
        [[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteModesKey]];

    [CPPrivateSiteModes removeObjectForKey:site];
    [modes removeObjectForKey:site];
    [[NSUserDefaults standardUserDefaults] setObject:modes forKey:CPSiteModesKey];
    [self changed];
}

+ (void)removeModeForURL:(NSURL *)url
{
    NSString *key = CPSiteKey(url);
    NSMutableDictionary *modes;

    if (key == nil)
        return;
    // A choice for a parent domain stays; "use the default" is about this site.
    [CPPrivateSiteModes removeObjectForKey:key];
    if (![[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled]) {
        modes = [NSMutableDictionary dictionaryWithDictionary:
                 [[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteModesKey]];
        [modes removeObjectForKey:key];
        [[NSUserDefaults standardUserDefaults] setObject:modes forKey:CPSiteModesKey];
    }
    [self changed];
}

// Sites choose which scripts to send by browser version, and a modern iPhone
// gets code this engine cannot run. So "Mobile" claims the iPhone Safari
// built on the same WebKit as the one running: Safari 11 for WebKit 604,
// Safari 5.1 for the WebKit that comes with Tiger and Leopard.
+ (NSString *)userAgentForMode:(CPSiteMode)mode
{
    switch (mode) {
    case CPSiteModeMobile:
        if (CPWebKitMajorVersion() >= 600)
            return @"Mozilla/5.0 (iPhone; CPU iPhone OS 11_4 like Mac OS X) AppleWebKit/605.1.15 "
                   @"(KHTML, like Gecko) Version/11.0 Mobile/15E148 Safari/604.1";
        return @"Mozilla/5.0 (iPhone; CPU iPhone OS 5_1_1 like Mac OS X) AppleWebKit/534.46 "
               @"(KHTML, like Gecko) Version/5.1 Mobile/9B206 Safari/7534.48.3";
    case CPSiteModeBasic:
        return @"Opera/9.80 (J2ME/MIDP; Opera Mini/5.1.21214/28.2725; U; en) Presto/2.8.119 Version/11.10";
    default:
        return nil;
    }
}

+ (NSString *)nameForMode:(CPSiteMode)mode
{
    switch (mode) {
    case CPSiteModeMobile: return @"Mobile";
    case CPSiteModeBasic:  return @"Basic";
    default:               return @"Desktop";
    }
}

@end
