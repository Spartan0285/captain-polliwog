/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPSettings.h"
#import <WebKit/WebKit.h>
#import "CPHTTPCache.h"
#include <string.h>
#include <sys/types.h>
#include <sys/sysctl.h>

NSString * const CPSettingsDidChangeNotification = @"CPSettingsDidChange";

static NSString * const CPMemoryProfileKey     = @"CPMemoryProfile";
static NSString * const CPDiskCacheMegaKey     = @"CPDiskCacheMegabytes";
static NSString * const CPDiskCacheLocationKey = @"CPDiskCacheLocation";
static NSString * const CPLoadsImagesKey       = @"CPLoadsImages";

static unsigned long long CPPhysicalMemory(void)
{
    unsigned long long memsize = 0;
    size_t length = sizeof(memsize);
    if (sysctlbyname("hw.memsize", &memsize, &length, NULL, 0) != 0)
        return 0;
    return memsize;
}

// Calls a WebPreferences method that the 10.4 SDK does not declare but the
// installed WebKit may still implement. The argument has to be passed in the
// type the method actually takes: a BOOL is a char, and handing it four bytes
// stores the wrong value.
static void CPCallWithArgument(id target, NSString *selectorName, unsigned value)
{
    SEL selector = NSSelectorFromString(selectorName);
    NSMethodSignature *signature;
    NSInvocation *invocation;
    const char *argumentType;

    if (![target respondsToSelector:selector]) {
        NSLog(@"Captain Polliwog: %@ unavailable in this WebKit", selectorName);
        return;
    }
    signature = [target methodSignatureForSelector:selector];
    invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:target];
    [invocation setSelector:selector];

    argumentType = [signature getArgumentTypeAtIndex:2];
    if (strcmp(argumentType, @encode(BOOL)) == 0 || strcmp(argumentType, @encode(char)) == 0) {
        BOOL flag = (value != 0);
        [invocation setArgument:&flag atIndex:2];
    } else {
        [invocation setArgument:&value atIndex:2];
    }
    [invocation invoke];
}

@implementation CPSettings

+ (void)initialize
{
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];

    [defaults setObject:[NSNumber numberWithInt:CPMemoryProfileAuto] forKey:CPMemoryProfileKey];
    [defaults setObject:[NSNumber numberWithInt:0] forKey:CPDiskCacheMegaKey];
    [defaults setObject:[NSNumber numberWithBool:YES] forKey:CPLoadsImagesKey];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

+ (CPSettings *)sharedSettings
{
    static CPSettings *settings = nil;
    if (settings == nil)
        settings = [[CPSettings alloc] init];
    return settings;
}

- (CPMemoryProfile)memoryProfile
{
    return (CPMemoryProfile)[[NSUserDefaults standardUserDefaults] integerForKey:CPMemoryProfileKey];
}

- (CPMemoryProfile)effectiveMemoryProfile
{
    CPMemoryProfile profile = [self memoryProfile];
    unsigned long long ram;

    if (profile != CPMemoryProfileAuto)
        return profile;

    ram = CPPhysicalMemory();
    if (ram == 0 || ram <= 320ULL * 1024 * 1024)
        return CPMemoryProfileSmall;
    if (ram <= 768ULL * 1024 * 1024)
        return CPMemoryProfileMedium;
    return CPMemoryProfileLarge;
}

- (void)setMemoryProfile:(CPMemoryProfile)profile
{
    [[NSUserDefaults standardUserDefaults] setInteger:profile forKey:CPMemoryProfileKey];
    [self apply];
}

- (unsigned)diskCacheMegabytes
{
    return (unsigned)[[NSUserDefaults standardUserDefaults] integerForKey:CPDiskCacheMegaKey];
}

- (unsigned)effectiveDiskCacheMegabytes
{
    unsigned configured = [self diskCacheMegabytes];

    if (configured > 0)
        return configured;

    // Disk is cheap next to a re-download plus a TLS handshake, so these are
    // deliberately larger than the RAM figures.
    switch ([self effectiveMemoryProfile]) {
    case CPMemoryProfileSmall:  return 150;
    case CPMemoryProfileMedium: return 300;
    default:                    return 500;
    }
}

- (void)setDiskCacheMegabytes:(unsigned)megabytes
{
    [[NSUserDefaults standardUserDefaults] setInteger:megabytes forKey:CPDiskCacheMegaKey];
    [self apply];
}

- (NSString *)diskCacheLocation
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:CPDiskCacheLocationKey];
}

- (void)setDiskCacheLocation:(NSString *)path
{
    if ([path length] > 0)
        [[NSUserDefaults standardUserDefaults] setObject:path forKey:CPDiskCacheLocationKey];
    else
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:CPDiskCacheLocationKey];
    [self apply];
}

- (NSString *)resolvedDiskCachePath
{
    NSString *location = [self diskCacheLocation];

    if ([location length] > 0)
        return [location stringByAppendingPathComponent:@"Captain Polliwog Cache"];
    // A folder of our own inside the app's cache directory, kept away from the
    // one CFNetwork manages for plain http loads.
    return [[[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"]
             stringByAppendingPathComponent:@"org.captainpolliwog.browser"]
            stringByAppendingPathComponent:@"Captain Polliwog HTTP"];
}

- (BOOL)loadsImages
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:CPLoadsImagesKey];
}

- (void)setLoadsImages:(BOOL)flag
{
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:CPLoadsImagesKey];
    [self apply];
}

- (unsigned)memoryCacheBytes
{
    switch ([self effectiveMemoryProfile]) {
    case CPMemoryProfileSmall:  return 2 * 1024 * 1024;
    case CPMemoryProfileMedium: return 6 * 1024 * 1024;
    default:                    return 12 * 1024 * 1024;
    }
}

// Tabs beyond this many give up their pages (keeping address, title and
// scroll position) until they are selected again.
- (unsigned)maximumLiveTabs
{
    switch ([self effectiveMemoryProfile]) {
    case CPMemoryProfileSmall:  return 2;
    case CPMemoryProfileMedium: return 4;
    default:                    return 8;
    }
}

// Responses larger than this stream straight to the page without being kept
// for the cache, so one big download cannot push the browser into swap.
- (unsigned)maximumCachedResponseBytes
{
    switch ([self effectiveMemoryProfile]) {
    case CPMemoryProfileSmall:  return 1024 * 1024;
    case CPMemoryProfileMedium: return 2 * 1024 * 1024;
    default:                    return 4 * 1024 * 1024;
    }
}

- (void)apply
{
    CPMemoryProfile profile = [self effectiveMemoryProfile];
    WebPreferences *preferences = [WebPreferences standardPreferences];
    NSString *path = [self resolvedDiskCachePath];

    [preferences setAutosaves:YES];
    [preferences setJavaScriptCanOpenWindowsAutomatically:NO];
    [preferences setJavaEnabled:NO];
    [preferences setPlugInsEnabled:NO];
    [preferences setLoadsImagesAutomatically:[self loadsImages]];

    // Neither selector is in the 10.4 SDK, but WebKit 3 and later have both.
    // WebCacheModelDocumentBrowser keeps the page cache small; the primary
    // browser model is Safari's own, and only makes sense with RAM to spare.
    CPCallWithArgument(preferences, @"setCacheModel:",
                       (profile == CPMemoryProfileSmall) ? 1 : 2);
    CPCallWithArgument(preferences, @"setUsesPageCache:",
                       (profile == CPMemoryProfileSmall) ? 0 : 1);

    [CPHTTPCache configureWithMemoryCapacity:[self memoryCacheBytes]
                                diskCapacity:([self effectiveDiskCacheMegabytes] * 1024 * 1024)
                                        path:path];

    [[NSNotificationCenter defaultCenter] postNotificationName:CPSettingsDidChangeNotification
                                                        object:self];
}

- (void)clearCaches
{
    [CPHTTPCache removeAllCachedResponses];
}

- (unsigned long long)diskCacheBytesInUse
{
    NSString *path = [self resolvedDiskCachePath];
    NSDirectoryEnumerator *files = [[NSFileManager defaultManager] enumeratorAtPath:path];
    unsigned long long total = 0;
    NSString *name;

    while ((name = [files nextObject]) != nil)
        total += [[[files fileAttributes] objectForKey:NSFileSize] unsignedLongLongValue];
    return total;
}

@end
