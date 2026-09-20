/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Being the browser that http and https links open in.
//
// Two halves, and both are needed: Launch Services has to be told that this
// application handles those schemes (CFBundleURLTypes in Info.plist, then
// LSSetDefaultHandlerForURLScheme), and the application has to answer the
// GetURL Apple Event that arrives when someone clicks a link in Mail.
@interface CPDefaultBrowser : NSObject

// Whether Captain Polliwog is the current handler for http.
+ (BOOL)isDefault;
// The name of whichever application is ("Safari"), or nil.
+ (NSString *)currentDefaultName;
// Asks Launch Services to make this copy the handler for http and https.
+ (BOOL)makeDefault;

@end
