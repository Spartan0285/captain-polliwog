/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPDebugSnapshot.h"

NSString *CPDebugSnapshotPath(void)
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugSnapshotPath"];
}

void CPWriteWindowSnapshot(NSWindow *window)
{
    NSString *path = CPDebugSnapshotPath();
    NSView *view = [[window contentView] superview];
    NSBitmapImageRep *bitmap;

    if (path == nil || window == nil) {
        NSLog(@"Captain Polliwog: snapshot skipped (path %@, window %@)", path, window);
        return;
    }
    NSLog(@"Captain Polliwog: snapshot of \"%@\" -> %@", [window title], path);
    if (view == nil)
        view = [window contentView];
    bitmap = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
    [view cacheDisplayInRect:[view bounds] toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSPNGFileType properties:nil] writeToFile:path atomically:YES];
}
