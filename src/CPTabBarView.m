/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPTabBarView.h"
#import "CPTab.h"
#import "CPPrivateBrowsing.h"

#define CPTabMaximumWidth  200.0f
#define CPTabMinimumWidth   60.0f
#define CPNewTabWidth       26.0f
#define CPCloseBoxSize       9.0f
#define CPTabInset           6.0f

@interface CPTabBarView (Private)
- (float)tabWidthForCount:(unsigned)count;
- (NSRect)frameForTabAtIndex:(unsigned)index count:(unsigned)count;
- (NSRect)closeBoxInTabFrame:(NSRect)tabFrame;
- (NSRect)newTabFrame;
@end

@implementation CPTabBarView (Private)

- (float)tabWidthForCount:(unsigned)count
{
    float available = NSWidth([self bounds]) - CPNewTabWidth;
    float width;

    if (count == 0)
        return CPTabMaximumWidth;
    width = floorf(available / (float)count);
    if (width > CPTabMaximumWidth)
        width = CPTabMaximumWidth;
    if (width < CPTabMinimumWidth)
        width = CPTabMinimumWidth;
    return width;
}

- (NSRect)frameForTabAtIndex:(unsigned)index count:(unsigned)count
{
    float width = [self tabWidthForCount:count];
    return NSMakeRect(index * width, 0.0f, width, NSHeight([self bounds]));
}

- (NSRect)closeBoxInTabFrame:(NSRect)tabFrame
{
    return NSMakeRect(NSMinX(tabFrame) + CPTabInset,
                      floorf(NSMidY(tabFrame) - CPCloseBoxSize / 2.0f),
                      CPCloseBoxSize, CPCloseBoxSize);
}

- (NSRect)newTabFrame
{
    unsigned count = [[controller tabsForTabBar] count];
    float x = count * [self tabWidthForCount:count];

    if (x > NSWidth([self bounds]) - CPNewTabWidth)
        x = NSWidth([self bounds]) - CPNewTabWidth;
    return NSMakeRect(x, 0.0f, CPNewTabWidth, NSHeight([self bounds]));
}

@end

@implementation CPTabBarView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(privateBrowsingChanged:)
                                                     name:CPPrivateBrowsingDidChangeNotification object:nil];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)privateBrowsingChanged:(NSNotification *)notification
{
    [self setNeedsDisplay:YES];
}

- (void)setController:(id)aController
{
    controller = aController;
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSArray *tabs = [controller tabsForTabBar];
    CPTab *selected = [controller selectedTabForTabBar];
    unsigned count = [tabs count];
    unsigned index;
    NSMutableParagraphStyle *truncating = [[[NSMutableParagraphStyle alloc] init] autorelease];
    NSDictionary *activeText;
    NSDictionary *idleText;
    NSRect plus;
    BOOL isPrivate;

    [truncating setLineBreakMode:NSLineBreakByTruncatingTail];
    activeText = [NSDictionary dictionaryWithObjectsAndKeys:
                  [NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
                  [NSColor blackColor], NSForegroundColorAttributeName,
                  truncating, NSParagraphStyleAttributeName, nil];
    idleText = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
                [NSColor colorWithCalibratedWhite:0.45f alpha:1.0f], NSForegroundColorAttributeName,
                truncating, NSParagraphStyleAttributeName, nil];

    // Private browsing turns the strip dark, so it is obvious in every window.
    isPrivate = [[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled];
    [(isPrivate ? [NSColor colorWithCalibratedWhite:0.28f alpha:1.0f]
                : [NSColor colorWithCalibratedWhite:0.78f alpha:1.0f]) set];
    NSRectFill([self bounds]);

    for (index = 0; index < count; index++) {
        CPTab *tab = [tabs objectAtIndex:index];
        NSRect frame = [self frameForTabAtIndex:index count:count];
        NSRect closeBox = [self closeBoxInTabFrame:frame];
        NSRect textFrame;
        NSBezierPath *cross;
        BOOL isSelected = (tab == selected);

        if (!NSIntersectsRect(frame, dirtyRect))
            continue;

        [(isSelected ? [NSColor colorWithCalibratedWhite:0.95f alpha:1.0f]
                     : [NSColor colorWithCalibratedWhite:(isPrivate ? 0.55f : 0.84f) alpha:1.0f]) set];
        NSRectFill(NSInsetRect(frame, 0.5f, 0.0f));
        [[NSColor colorWithCalibratedWhite:0.55f alpha:1.0f] set];
        NSRectFill(NSMakeRect(NSMaxX(frame) - 1.0f, 0.0f, 1.0f, NSHeight(frame)));

        cross = [NSBezierPath bezierPath];
        [cross moveToPoint:NSMakePoint(NSMinX(closeBox), NSMinY(closeBox))];
        [cross lineToPoint:NSMakePoint(NSMaxX(closeBox), NSMaxY(closeBox))];
        [cross moveToPoint:NSMakePoint(NSMinX(closeBox), NSMaxY(closeBox))];
        [cross lineToPoint:NSMakePoint(NSMaxX(closeBox), NSMinY(closeBox))];
        [cross setLineWidth:1.5f];
        [[NSColor colorWithCalibratedWhite:0.35f alpha:1.0f] set];
        [cross stroke];

        textFrame = NSMakeRect(NSMaxX(closeBox) + CPTabInset, NSMinY(frame) + 4.0f,
                               NSMaxX(frame) - NSMaxX(closeBox) - 2.0f * CPTabInset,
                               NSHeight(frame) - 6.0f);
        [[tab displayTitle] drawInRect:textFrame
                        withAttributes:([tab isDiscarded] || [tab isLoading]) ? idleText : activeText];
    }

    // The bottom edge, left open under the selected tab so it reads as joined
    // to the page below.
    [[NSColor colorWithCalibratedWhite:0.55f alpha:1.0f] set];
    NSRectFill(NSMakeRect(0.0f, 0.0f, NSWidth([self bounds]), 1.0f));
    for (index = 0; index < count; index++) {
        if ([tabs objectAtIndex:index] == selected) {
            NSRect frame = [self frameForTabAtIndex:index count:count];
            [[NSColor colorWithCalibratedWhite:0.95f alpha:1.0f] set];
            NSRectFill(NSMakeRect(NSMinX(frame), 0.0f, NSWidth(frame) - 1.0f, 1.0f));
        }
    }

    plus = [self newTabFrame];
    [@"+" drawAtPoint:NSMakePoint(NSMidX(plus) - 4.0f, NSMinY(plus) + 3.0f)
       withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                       [NSFont boldSystemFontOfSize:13.0f], NSFontAttributeName,
                       [NSColor colorWithCalibratedWhite:(isPrivate ? 0.85f : 0.3f) alpha:1.0f],
                       NSForegroundColorAttributeName, nil]];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSArray *tabs = [controller tabsForTabBar];
    unsigned count = [tabs count];
    unsigned index;

    if (NSPointInRect(point, [self newTabFrame])) {
        [controller tabBarNewTab];
        return;
    }
    for (index = 0; index < count; index++) {
        NSRect frame = [self frameForTabAtIndex:index count:count];
        if (!NSPointInRect(point, frame))
            continue;
        // A slightly larger target than the drawn cross: it is small.
        if (NSPointInRect(point, NSInsetRect([self closeBoxInTabFrame:frame], -4.0f, -4.0f)))
            [controller tabBarCloseTab:[tabs objectAtIndex:index]];
        else
            [controller tabBarSelectTab:[tabs objectAtIndex:index]];
        return;
    }
}

@end
