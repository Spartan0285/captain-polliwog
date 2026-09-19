/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Toolbar glyphs drawn in code: Tiger's fonts lack reliable arrow symbols,
// and bundling image files would cost disk reads at launch on slow drives.
@interface CPIcons : NSObject

+ (NSImage *)backImage;
+ (NSImage *)forwardImage;
+ (NSImage *)reloadImage;
+ (NSImage *)stopImage;
+ (NSImage *)shareImage;
+ (NSImage *)starImage;
+ (NSImage *)filledStarImage;
+ (NSImage *)downloadsImage;
// The downloads glyph over a progress bar; fraction < 0 when sizes are unknown.
+ (NSImage *)downloadsImageWithProgress:(double)fraction;
+ (NSImage *)plusImage;
+ (NSImage *)globeImage;
+ (NSImage *)pageSettingsImage;

@end
