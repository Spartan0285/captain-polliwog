/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// What this is, which build of it, and who made it.
//
// -orderFrontStandardAboutPanel: cannot carry the build number, the stage
// badge or the two links, so the window is drawn here. The build number
// earns its place: it is what a feedback report carries and what you will
// ask someone for when one arrives.
@interface CPAbout : NSObject
{
    NSWindow *window;
}

+ (void)show;

// "Alpha", from CPBuildStage in the bundle, or nil once that is emptied in
// the Makefile. The badge, the feedback report and the window title all read
// it from here so there is one place to change.
+ (NSString *)stage;

// "Version 0.3 (build 8)".
+ (NSString *)versionLine;

@end
