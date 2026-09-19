/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// The start page: a search field, Favorites, and Top Sites (the sites most
// visited lately, from history). Made afresh each time it is shown; plain
// HTML with no scripts.
@interface CPStartPage : NSObject

+ (NSString *)HTML;

@end
