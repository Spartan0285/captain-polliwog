/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPSiteSettings.h"
#import "CPSettings.h"
#import "CPPrivateBrowsing.h"

NSString * const CPSiteSettingsDidChangeNotification = @"CPSiteSettingsDidChange";

static NSString * const CPSiteSettingsKey = @"CPSiteSettings";
// Private browsing leaves no trace: its choices are kept only in memory.
static NSMutableDictionary *CPPrivateSettings = nil;

@implementation CPSiteSettings

+ (NSString *)siteNameForURL:(NSURL *)url
{
    NSString *scheme = [[url scheme] lowercaseString];
    NSString *host = [[url host] lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
        return nil;
    if ([host hasPrefix:@"www."])
        host = [host substringFromIndex:4];
    return [host length] ? host : nil;
}

+ (NSDictionary *)settingsForURL:(NSURL *)url
{
    NSString *site = [self siteNameForURL:url];
    NSDictionary *settings;
    if (site == nil)
        return nil;
    settings = [CPPrivateSettings objectForKey:site];
    if (settings == nil)
        settings = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteSettingsKey] objectForKey:site];
    return settings;
}

+ (void)setValue:(id)value forKey:(NSString *)key url:(NSURL *)url
{
    NSString *site = [self siteNameForURL:url];
    NSMutableDictionary *all, *settings;
    BOOL private = [[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled];

    if (site == nil)
        return;
    if (private) {
        if (CPPrivateSettings == nil)
            CPPrivateSettings = [[NSMutableDictionary alloc] init];
        all = CPPrivateSettings;
    } else
        all = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteSettingsKey]];
    settings = [NSMutableDictionary dictionaryWithDictionary:[self settingsForURL:url]];
    if (value != nil)
        [settings setObject:value forKey:key];
    else
        [settings removeObjectForKey:key];
    if ([settings count])
        [all setObject:settings forKey:site];
    else
        [all removeObjectForKey:site];
    if (!private)
        [[NSUserDefaults standardUserDefaults] setObject:all forKey:CPSiteSettingsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:CPSiteSettingsDidChangeNotification object:url];
}

+ (NSArray *)configuredSites
{
    NSMutableSet *sites = [NSMutableSet set];
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteSettingsKey];
    if (saved != nil)
        [sites addObjectsFromArray:[saved allKeys]];
    if (CPPrivateSettings != nil)
        [sites addObjectsFromArray:[CPPrivateSettings allKeys]];
    return [[sites allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSDictionary *)settingsForSite:(NSString *)site
{
    NSDictionary *settings = [CPPrivateSettings objectForKey:site];
    if (settings == nil)
        settings = [[[NSUserDefaults standardUserDefaults]
            dictionaryForKey:CPSiteSettingsKey] objectForKey:site];
    return settings;
}

+ (void)removeSettingsForSite:(NSString *)site
{
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:
        [[NSUserDefaults standardUserDefaults] dictionaryForKey:CPSiteSettingsKey]];

    [CPPrivateSettings removeObjectForKey:site];
    [all removeObjectForKey:site];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:CPSiteSettingsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:CPSiteSettingsDidChangeNotification
                                                        object:nil];
}

+ (float)textSizeForURL:(NSURL *)url
{
    NSNumber *size = [[self settingsForURL:url] objectForKey:@"textSize"];
    return size != nil ? [size floatValue] : 1.0f;
}

+ (void)setTextSize:(float)size forURL:(NSURL *)url
{
    [self setValue:(size > 0.99f && size < 1.01f) ? nil : [NSNumber numberWithFloat:size] forKey:@"textSize" url:url];
}

+ (BOOL)usesReaderForURL:(NSURL *)url
{
    return [[[self settingsForURL:url] objectForKey:@"reader"] boolValue];
}

+ (void)setUsesReader:(BOOL)flag forURL:(NSURL *)url
{
    [self setValue:(flag ? [NSNumber numberWithBool:YES] : nil) forKey:@"reader" url:url];
}

+ (BOOL)javaScriptEnabledForURL:(NSURL *)url
{
    NSNumber *enabled = [[self settingsForURL:url] objectForKey:@"javaScript"];
    return enabled != nil ? [enabled boolValue] : [[CPSettings sharedSettings] javaScriptEnabled];
}

+ (void)setJavaScriptEnabled:(BOOL)flag forURL:(NSURL *)url
{
    [self setValue:(flag == [[CPSettings sharedSettings] javaScriptEnabled] ? nil : [NSNumber numberWithBool:flag])
            forKey:@"javaScript" url:url];
}

+ (BOOL)imagesEnabledForURL:(NSURL *)url
{
    NSNumber *enabled = [[self settingsForURL:url] objectForKey:@"images"];
    return enabled != nil ? [enabled boolValue] : [[CPSettings sharedSettings] loadsImages];
}

+ (void)setImagesEnabled:(BOOL)flag forURL:(NSURL *)url
{
    [self setValue:(flag == [[CPSettings sharedSettings] loadsImages] ? nil : [NSNumber numberWithBool:flag])
            forKey:@"images" url:url];
}

@end
