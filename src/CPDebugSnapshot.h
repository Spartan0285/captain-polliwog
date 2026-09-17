/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Testing aid. Screenshots taken over SSH come back black on these systems,
// so the app draws its own window into a file instead:
//
//   defaults write org.captainpolliwog.browser CPDebugSnapshotPath /tmp/x.png
//
// The scripts in scripts/ rely on this. Does nothing when unset.
NSString *CPDebugSnapshotPath(void);
void CPWriteWindowSnapshot(NSWindow *window);
