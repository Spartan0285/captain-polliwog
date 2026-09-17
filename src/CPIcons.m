/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPIcons.h"

typedef enum {
    CPIconBack,
    CPIconForward,
    CPIconReload,
    CPIconStop
} CPIconKind;

static NSImage *CPDrawIcon(CPIconKind kind)
{
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16.0f, 16.0f)];
    NSBezierPath *path = [NSBezierPath bezierPath];

    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.22f alpha:1.0f] set];

    switch (kind) {
    case CPIconBack:
        [path moveToPoint:NSMakePoint(11.5f, 2.5f)];
        [path lineToPoint:NSMakePoint(3.5f, 8.0f)];
        [path lineToPoint:NSMakePoint(11.5f, 13.5f)];
        [path closePath];
        [path fill];
        break;

    case CPIconForward:
        [path moveToPoint:NSMakePoint(4.5f, 2.5f)];
        [path lineToPoint:NSMakePoint(12.5f, 8.0f)];
        [path lineToPoint:NSMakePoint(4.5f, 13.5f)];
        [path closePath];
        [path fill];
        break;

    case CPIconReload:
        [path appendBezierPathWithArcWithCenter:NSMakePoint(8.0f, 8.0f)
                                         radius:5.0f
                                     startAngle:80.0f
                                       endAngle:355.0f
                                      clockwise:NO];
        [path setLineWidth:1.8f];
        [path stroke];
        path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(10.3f, 7.2f)];
        [path lineToPoint:NSMakePoint(15.7f, 7.2f)];
        [path lineToPoint:NSMakePoint(13.0f, 10.8f)];
        [path closePath];
        [path fill];
        break;

    case CPIconStop:
        [path moveToPoint:NSMakePoint(4.0f, 4.0f)];
        [path lineToPoint:NSMakePoint(12.0f, 12.0f)];
        [path moveToPoint:NSMakePoint(4.0f, 12.0f)];
        [path lineToPoint:NSMakePoint(12.0f, 4.0f)];
        [path setLineWidth:2.0f];
        [path setLineCapStyle:NSRoundLineCapStyle];
        [path stroke];
        break;
    }

    [image unlockFocus];
    return image;
}

@implementation CPIcons

+ (NSImage *)backImage
{
    static NSImage *image = nil;
    if (image == nil)
        image = CPDrawIcon(CPIconBack);
    return image;
}

+ (NSImage *)forwardImage
{
    static NSImage *image = nil;
    if (image == nil)
        image = CPDrawIcon(CPIconForward);
    return image;
}

+ (NSImage *)reloadImage
{
    static NSImage *image = nil;
    if (image == nil)
        image = CPDrawIcon(CPIconReload);
    return image;
}

+ (NSImage *)stopImage
{
    static NSImage *image = nil;
    if (image == nil)
        image = CPDrawIcon(CPIconStop);
    return image;
}

@end
