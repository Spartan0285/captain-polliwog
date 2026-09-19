/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPIcons.h"

typedef enum {
    CPIconBack,
    CPIconForward,
    CPIconReload,
    CPIconStop,
    CPIconShare,
    CPIconStar,
    CPIconStarFilled,
    CPIconDownloads,
    CPIconPlus,
    CPIconGlobe,
    CPIconPageSettings,
    CPIconCount
} CPIconKind;

static NSBezierPath *CPStarPath(void)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    int i;
    for (i = 0; i < 10; i++) {
        float angle = (float)(M_PI / 2.0 + i * M_PI / 5.0);
        float radius = (i % 2) ? 2.9f : 6.6f;
        NSPoint point = NSMakePoint(8.0f + radius * cosf(angle), 7.6f + radius * sinf(angle));
        if (i == 0)
            [path moveToPoint:point];
        else
            [path lineToPoint:point];
    }
    [path closePath];
    return path;
}

static NSImage *CPDrawIcon(CPIconKind kind)
{
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16.0f, 16.0f)];
    NSBezierPath *path = [NSBezierPath bezierPath];

    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.25f alpha:1.0f] set];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineJoinStyle:NSRoundLineJoinStyle];

    switch (kind) {
    case CPIconBack:
        // Chevrons, as Safari draws them since version 7.
        [path moveToPoint:NSMakePoint(10.5f, 2.5f)];
        [path lineToPoint:NSMakePoint(5.0f, 8.0f)];
        [path lineToPoint:NSMakePoint(10.5f, 13.5f)];
        [path setLineWidth:2.0f];
        [path stroke];
        break;

    case CPIconForward:
        [path moveToPoint:NSMakePoint(5.5f, 2.5f)];
        [path lineToPoint:NSMakePoint(11.0f, 8.0f)];
        [path lineToPoint:NSMakePoint(5.5f, 13.5f)];
        [path setLineWidth:2.0f];
        [path stroke];
        break;

    case CPIconReload:
        [path appendBezierPathWithArcWithCenter:NSMakePoint(8.0f, 8.0f) radius:5.0f startAngle:80.0f endAngle:355.0f clockwise:NO];
        [path setLineWidth:1.6f];
        [path stroke];
        path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(10.3f, 7.2f)];
        [path lineToPoint:NSMakePoint(15.7f, 7.2f)];
        [path lineToPoint:NSMakePoint(13.0f, 10.8f)];
        [path closePath];
        [path fill];
        break;

    case CPIconStop:
        [path moveToPoint:NSMakePoint(4.5f, 4.5f)];
        [path lineToPoint:NSMakePoint(11.5f, 11.5f)];
        [path moveToPoint:NSMakePoint(4.5f, 11.5f)];
        [path lineToPoint:NSMakePoint(11.5f, 4.5f)];
        [path setLineWidth:1.8f];
        [path stroke];
        break;

    case CPIconShare:
        // A box with an arrow leaving it.
        [path moveToPoint:NSMakePoint(5.5f, 10.0f)];
        [path lineToPoint:NSMakePoint(3.5f, 10.0f)];
        [path lineToPoint:NSMakePoint(3.5f, 1.5f)];
        [path lineToPoint:NSMakePoint(12.5f, 1.5f)];
        [path lineToPoint:NSMakePoint(12.5f, 10.0f)];
        [path lineToPoint:NSMakePoint(10.5f, 10.0f)];
        [path moveToPoint:NSMakePoint(8.0f, 5.0f)];
        [path lineToPoint:NSMakePoint(8.0f, 14.5f)];
        [path moveToPoint:NSMakePoint(5.5f, 12.0f)];
        [path lineToPoint:NSMakePoint(8.0f, 14.5f)];
        [path lineToPoint:NSMakePoint(10.5f, 12.0f)];
        [path setLineWidth:1.4f];
        [path stroke];
        break;

    case CPIconStar:
        path = CPStarPath();
        [path setLineWidth:1.3f];
        [path setLineJoinStyle:NSRoundLineJoinStyle];
        [path stroke];
        break;

    case CPIconStarFilled:
        [[NSColor colorWithCalibratedRed:0.95f green:0.65f blue:0.1f alpha:1.0f] set];
        path = CPStarPath();
        [path fill];
        break;

    case CPIconDownloads:
        // An arrow into a tray.
        [path moveToPoint:NSMakePoint(8.0f, 14.5f)];
        [path lineToPoint:NSMakePoint(8.0f, 5.0f)];
        [path moveToPoint:NSMakePoint(4.5f, 8.5f)];
        [path lineToPoint:NSMakePoint(8.0f, 5.0f)];
        [path lineToPoint:NSMakePoint(11.5f, 8.5f)];
        [path moveToPoint:NSMakePoint(2.5f, 4.0f)];
        [path lineToPoint:NSMakePoint(2.5f, 1.5f)];
        [path lineToPoint:NSMakePoint(13.5f, 1.5f)];
        [path lineToPoint:NSMakePoint(13.5f, 4.0f)];
        [path setLineWidth:1.5f];
        [path stroke];
        break;

    case CPIconPlus:
        [path moveToPoint:NSMakePoint(8.0f, 2.5f)];
        [path lineToPoint:NSMakePoint(8.0f, 13.5f)];
        [path moveToPoint:NSMakePoint(2.5f, 8.0f)];
        [path lineToPoint:NSMakePoint(13.5f, 8.0f)];
        [path setLineWidth:1.6f];
        [path stroke];
        break;

    case CPIconGlobe:
        // For pages with no icon of their own.
        [[NSColor colorWithCalibratedWhite:0.55f alpha:1.0f] set];
        [path appendBezierPathWithOvalInRect:NSMakeRect(2.0f, 2.0f, 12.0f, 12.0f)];
        [path appendBezierPathWithOvalInRect:NSMakeRect(5.5f, 2.0f, 5.0f, 12.0f)];
        [path moveToPoint:NSMakePoint(2.0f, 8.0f)];
        [path lineToPoint:NSMakePoint(14.0f, 8.0f)];
        [path setLineWidth:1.0f];
        [path stroke];
        break;

    case CPIconPageSettings: {
        // "aA", for the page's text size, Reader and site settings.
        NSDictionary *small = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSFont boldSystemFontOfSize:8.0f], NSFontAttributeName,
            [NSColor colorWithCalibratedWhite:0.25f alpha:1.0f], NSForegroundColorAttributeName, nil];
        NSDictionary *large = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSFont boldSystemFontOfSize:12.0f], NSFontAttributeName,
            [NSColor colorWithCalibratedWhite:0.25f alpha:1.0f], NSForegroundColorAttributeName, nil];
        [@"a" drawAtPoint:NSMakePoint(0.5f, 1.5f) withAttributes:small];
        [@"A" drawAtPoint:NSMakePoint(6.0f, 0.5f) withAttributes:large];
        break;
    }

    default:
        break;
    }

    [image unlockFocus];
    return image;
}

static NSImage *CPIcon(CPIconKind kind)
{
    static NSImage *icons[CPIconCount];
    if (icons[kind] == nil)
        icons[kind] = CPDrawIcon(kind);
    return icons[kind];
}

@implementation CPIcons

+ (NSImage *)downloadsImageWithProgress:(double)fraction
{
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(16.0f, 16.0f)] autorelease];
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    NSRect track = NSMakeRect(1.5f, 0.5f, 13.0f, 3.0f);

    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.25f alpha:1.0f] set];
    [arrow setLineCapStyle:NSRoundLineCapStyle];
    [arrow setLineJoinStyle:NSRoundLineJoinStyle];
    [arrow moveToPoint:NSMakePoint(8.0f, 15.0f)];
    [arrow lineToPoint:NSMakePoint(8.0f, 6.5f)];
    [arrow moveToPoint:NSMakePoint(4.5f, 10.0f)];
    [arrow lineToPoint:NSMakePoint(8.0f, 6.5f)];
    [arrow lineToPoint:NSMakePoint(11.5f, 10.0f)];
    [arrow setLineWidth:1.5f];
    [arrow stroke];

    [[NSColor colorWithCalibratedWhite:0.8f alpha:1.0f] set];
    NSRectFill(track);
    [[NSColor colorWithCalibratedRed:0.25f green:0.55f blue:0.95f alpha:(fraction < 0.0 ? 0.5f : 1.0f)] set];
    track.size.width *= (fraction < 0.0 ? 1.0 : MIN(fraction, 1.0));
    NSRectFill(track);
    [image unlockFocus];
    return image;
}

+ (NSImage *)backImage { return CPIcon(CPIconBack); }
+ (NSImage *)forwardImage { return CPIcon(CPIconForward); }
+ (NSImage *)reloadImage { return CPIcon(CPIconReload); }
+ (NSImage *)stopImage { return CPIcon(CPIconStop); }
+ (NSImage *)shareImage { return CPIcon(CPIconShare); }
+ (NSImage *)starImage { return CPIcon(CPIconStar); }
+ (NSImage *)filledStarImage { return CPIcon(CPIconStarFilled); }
+ (NSImage *)downloadsImage { return CPIcon(CPIconDownloads); }
+ (NSImage *)plusImage { return CPIcon(CPIconPlus); }
+ (NSImage *)globeImage { return CPIcon(CPIconGlobe); }
+ (NSImage *)pageSettingsImage { return CPIcon(CPIconPageSettings); }

@end
