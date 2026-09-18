/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// A single memory budget drives every cache in the app. Swapping is the thing
// to avoid on these machines: once a 500MHz G3 starts paging, every scroll
// waits on the disk, so caches are kept small in RAM and generous on disk.
// A cache hit also skips the TLS handshake, which is real work at 500MHz.
typedef enum {
    CPMemoryProfileAuto = 0,    // chosen from the amount of RAM installed
    CPMemoryProfileSmall,       // 256MB machines, such as a stock Pismo
    CPMemoryProfileMedium,      // 512MB
    CPMemoryProfileLarge        // 1GB and up
} CPMemoryProfile;

extern NSString * const CPSettingsDidChangeNotification;

@interface CPSettings : NSObject

+ (CPSettings *)sharedSettings;

- (CPMemoryProfile)memoryProfile;
- (CPMemoryProfile)effectiveMemoryProfile;
- (void)setMemoryProfile:(CPMemoryProfile)profile;

// 0 means "pick a size to suit the memory profile".
- (unsigned)diskCacheMegabytes;
- (unsigned)effectiveDiskCacheMegabytes;
- (void)setDiskCacheMegabytes:(unsigned)megabytes;

// A folder chosen by the user (an SSD or a second drive), or nil for the
// standard location inside ~/Library/Caches.
- (NSString *)diskCacheLocation;
- (void)setDiskCacheLocation:(NSString *)path;
- (NSString *)resolvedDiskCachePath;

- (BOOL)loadsImages;
- (void)setLoadsImages:(BOOL)flag;

// Whether to empty WebKit's shared memory cache when this Mac runs low.
- (BOOL)releasesMemoryUnderPressure;
- (void)setReleasesMemoryUnderPressure:(BOOL)flag;

- (unsigned)memoryCacheBytes;
- (unsigned)maximumLiveTabs;
- (unsigned)maximumCachedResponseBytes;

- (void)apply;
- (void)clearCaches;
- (unsigned long long)diskCacheBytesInUse;

@end
