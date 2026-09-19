/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPDebugSnapshot.h"
#include <dlfcn.h>

// CGWindowListCreateImage (10.5 and later): the window as it is on screen,
// with any layers the engine composites. Looked up at run time, since the
// 10.4 SDK lacks it; Tiger falls back to redrawing the view into a bitmap,
// which misses composited layers.
typedef CGImageRef (*CPWindowImageFunction)(CGRect, uint32_t, uint32_t, uint32_t);

static NSBitmapImageRep *CPScreenImageOfWindow(NSWindow *window)
{
    static CPWindowImageFunction createImage = NULL;
    static BOOL looked = NO;
    CGImageRef image;
    NSBitmapImageRep *bitmap;

    if (!looked) {
        looked = YES;
        createImage = (CPWindowImageFunction)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
    }
    if (createImage == NULL || ![window isVisible])
        return nil;
    // kCGWindowListOptionIncludingWindow (8), kCGWindowImageBoundsIgnoreFraming (1)
    image = createImage(CGRectNull, 8, (uint32_t)[window windowNumber], 1);
    if (image == NULL)
        return nil;
    // -initWithCGImage: is 10.5's too, like the function that made the image.
    bitmap = [[[NSBitmapImageRep alloc] performSelector:@selector(initWithCGImage:) withObject:(id)image] autorelease];
    CGImageRelease(image);
    return bitmap;
}

NSString *CPDebugSnapshotPath(void)
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugSnapshotPath"];
}

BOOL CPDebugLogging(void)
{
    return CPDebugSnapshotPath() != nil ||
           [[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugLog"];
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
    bitmap = CPScreenImageOfWindow(window);
    if (bitmap == nil) {
        bitmap = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
        [view cacheDisplayInRect:[view bounds] toBitmapImageRep:bitmap];
    }
    [[bitmap representationUsingType:NSPNGFileType properties:nil] writeToFile:path atomically:YES];
}
