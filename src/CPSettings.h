/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class WebPreferences;

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

typedef enum {
    CPNewTabShowsStartPage = 0,
    CPNewTabShowsHomePage = 1,
    CPNewTabShowsBlankPage = 2
} CPNewTabPage;

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

// Performance: what can be turned off when a Mac is slow or short of
// memory. Each has a site-by-site counterpart where that makes sense (see
// CPSiteSettings).
- (BOOL)javaScriptEnabled;
- (void)setJavaScriptEnabled:(BOOL)flag;
// Resources/polyfills.js, run in every page (takes effect on relaunch).
- (BOOL)usesCompatibilityScripts;
- (void)setUsesCompatibilityScripts:(BOOL)flag;
- (BOOL)blocksAdsAndTrackers;
- (void)setBlocksAdsAndTrackers:(BOOL)flag;
// Video and audio in pages (through the media relay).
- (BOOL)playsVideo;
- (void)setPlaysVideo:(BOOL)flag;
- (BOOL)autoplaysVideo;

// Whether the polyfills draw a "Play in <player>" button over a video the
// pointer is on. The player itself is chosen in CPExternalPlayer.
- (BOOL)showsVideoPlayButton;
- (void)setShowsVideoPlayButton:(BOOL)flag;

// View > Show Page Activity: the status bar says what the page is doing -
// connecting, how many of its pieces have arrived, which site it is still
// waiting on, and when its scripts held everything up. Off by default.
- (BOOL)showsPageActivity;
// Whether the tab sidebar is open, so a window opens the way the
// last one was left.
- (BOOL)showsTabSidebar;
- (void)setShowsTabSidebar:(BOOL)flag;
- (void)setShowsPageActivity:(BOOL)flag;
- (void)setAutoplaysVideo:(BOOL)flag;
- (BOOL)showsAnimatedImages;
- (void)setShowsAnimatedImages:(BOOL)flag;
// WebGL: off by default. On a G3 or G4 it mostly fails, and costs a lot
// of memory and processor time where it doesn't.
- (BOOL)webGLEnabled;
- (void)setWebGLEnabled:(BOOL)flag;
// Stop a script that runs 15 seconds without a break.
- (BOOL)stopsLongScripts;
- (void)setStopsLongScripts:(BOOL)flag;

// The home page: an address, or empty for the start page (Favorites and
// Top Sites).
- (NSString *)homePage;
- (void)setHomePage:(NSString *)page;
- (CPNewTabPage)newTabPage;
- (void)setNewTabPage:(CPNewTabPage)page;

// Whether to empty WebKit's shared memory cache when this Mac runs low.
- (BOOL)releasesMemoryUnderPressure;
- (void)setReleasesMemoryUnderPressure:(BOOL)flag;

- (unsigned)memoryCacheBytes;
- (unsigned)maximumLiveTabs;
- (unsigned)maximumCachedResponseBytes;

// Where downloads are saved: ~/Downloads when it exists (Leopard and later
// create one), otherwise the Desktop, as Safari did on Tiger.
- (NSString *)downloadsFolder;
- (void)setDownloadsFolder:(NSString *)path;

// ~/Library/Application Support/Captain Polliwog, created on first use.
- (NSString *)supportDirectory;

// How much browsing history to keep in memory; every entry stays in RAM.
- (unsigned)historyItemLimit;

- (void)apply;
// Features our WebKit has but leaves off by default (display: contents,
// isSecureContext, <a download>), and WebGL as the setting says. Global in WebKit, but each WebPreferences
// object carries them, so every one a WebView uses must say the same.
+ (void)enableModernFeatures:(WebPreferences *)preferences;
- (void)clearCaches;
- (unsigned long long)diskCacheBytesInUse;

@end
