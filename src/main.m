/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// Captain Polliwog - a web browser for Mac OS X 10.4 Tiger and later.

#import <Cocoa/Cocoa.h>
#import "CPAppDelegate.h"

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *app = [NSApplication sharedApplication];

    // No nib: the menu bar is built in code so the same sources work with
    // Xcode 2.5 (Tiger) and Xcode 3.1 (Leopard) without Interface Builder files.
    CPAppDelegate *delegate = [[CPAppDelegate alloc] init];
    [app setDelegate:delegate];
    [delegate buildMainMenu];

    [app run];

    [delegate release];
    [pool release];
    return 0;
}
