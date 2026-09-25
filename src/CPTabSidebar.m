/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPTabSidebar.h"

#import "CPPrivateBrowsing.h"
#import "CPTab.h"
#import "CPTabBarView.h"

const float CPTabSidebarWidth = 190.0f;

static const float CPRowHeight = 26.0f;
static const float CPIconSize = 16.0f;
static const float CPCloseSize = 9.0f;

@implementation CPTabSidebar

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
        trackingRow = -1;
    return self;
}

- (void)setController:(id)aController
{
    controller = aController;
    [self setNeedsDisplay:YES];
}

- (float)heightForTabCount:(unsigned)count
{
    return CPRowHeight * count;
}

// Rows run down from the top, which is the opposite of the coordinate
// system, so the view is flipped rather than doing the arithmetic at
// every use.
- (BOOL)isFlipped
{
    return YES;
}

- (NSRect)frameForRow:(unsigned)row
{
    return NSMakeRect(0.0f, CPRowHeight * row, NSWidth([self bounds]), CPRowHeight);
}

- (NSRect)closeBoxInRow:(NSRect)row
{
    return NSMakeRect(NSMaxX(row) - CPCloseSize - 8.0f,
                      NSMinY(row) + floorf((CPRowHeight - CPCloseSize) / 2.0f),
                      CPCloseSize, CPCloseSize);
}

- (int)rowAtPoint:(NSPoint)point
{
    int row;
    unsigned count = [[controller tabsForTabBar] count];
    if (point.y < 0.0f)
        return -1;
    row = (int)(point.y / CPRowHeight);
    return (row >= 0 && (unsigned)row < count) ? row : -1;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSArray *tabs = [controller tabsForTabBar];
    CPTab *selected = [controller selectedTabForTabBar];
    unsigned count = [tabs count];
    unsigned index;
    BOOL isPrivate = [[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled];
    NSMutableParagraphStyle *truncating = [[[NSMutableParagraphStyle alloc] init] autorelease];
    NSDictionary *activeText;
    NSDictionary *idleText;

    [truncating setLineBreakMode:NSLineBreakByTruncatingTail];
    activeText = [NSDictionary dictionaryWithObjectsAndKeys:
                  [NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
                  (isPrivate ? [NSColor whiteColor] : [NSColor blackColor]), NSForegroundColorAttributeName,
                  truncating, NSParagraphStyleAttributeName, nil];
    idleText = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
                [NSColor colorWithCalibratedWhite:(isPrivate ? 0.75f : 0.35f) alpha:1.0f], NSForegroundColorAttributeName,
                truncating, NSParagraphStyleAttributeName, nil];

    // Flat fills and text only. Every redraw costs real time on a G3, and
    // this one happens on each tab title change.
    [(isPrivate ? [NSColor colorWithCalibratedWhite:0.24f alpha:1.0f]
                : [NSColor colorWithCalibratedWhite:0.91f alpha:1.0f]) set];
    NSRectFill(dirtyRect);

    for (index = 0; index < count; index++) {
        CPTab *tab = [tabs objectAtIndex:index];
        NSRect row = [self frameForRow:index];
        NSRect closeBox = [self closeBoxInRow:row];
        NSRect textFrame;
        NSImage *icon;
        NSString *title;
        BOOL isSelected = (tab == selected);

        if (!NSIntersectsRect(row, dirtyRect))
            continue;

        if (isSelected) {
            [(isPrivate ? [NSColor colorWithCalibratedWhite:0.42f alpha:1.0f]
                        : [NSColor colorWithCalibratedWhite:1.0f alpha:1.0f]) set];
            NSRectFill(row);
        }

        icon = [tab favicon];
        if (icon != nil) {
            NSRect iconFrame = NSMakeRect(NSMinX(row) + 7.0f,
                                          NSMinY(row) + floorf((CPRowHeight - CPIconSize) / 2.0f),
                                          CPIconSize, CPIconSize);
            // The view is flipped and NSImage is not, so the icon is
            // drawn through a transform rather than upside down.
            [NSGraphicsContext saveGraphicsState];
            {
                NSAffineTransform *flip = [NSAffineTransform transform];
                [flip translateXBy:0.0f yBy:NSMaxY(iconFrame) + NSMinY(iconFrame)];
                [flip scaleXBy:1.0f yBy:-1.0f];
                [flip concat];
                [icon drawInRect:iconFrame fromRect:NSZeroRect
                       operation:NSCompositeSourceOver fraction:1.0f];
            }
            [NSGraphicsContext restoreGraphicsState];
        }

        title = [tab title];
        if ([title length] == 0)
            title = [tab isLoading] ? @"Loading..." : @"Untitled";
        textFrame = NSMakeRect(NSMinX(row) + 7.0f + CPIconSize + 6.0f,
                               NSMinY(row) + floorf((CPRowHeight - 14.0f) / 2.0f),
                               NSWidth(row) - (7.0f + CPIconSize + 6.0f) - (CPCloseSize + 14.0f),
                               14.0f);
        [title drawInRect:textFrame withAttributes:(isSelected ? activeText : idleText)];

        // The close cross appears on the selected row and on the row being
        // pressed, rather than on hover: tracking every mouse move over the
        // list is not worth the redraws here.
        if (isSelected || (int)index == trackingRow) {
            NSBezierPath *cross = [NSBezierPath bezierPath];
            [cross moveToPoint:NSMakePoint(NSMinX(closeBox), NSMinY(closeBox))];
            [cross lineToPoint:NSMakePoint(NSMaxX(closeBox), NSMaxY(closeBox))];
            [cross moveToPoint:NSMakePoint(NSMinX(closeBox), NSMaxY(closeBox))];
            [cross lineToPoint:NSMakePoint(NSMaxX(closeBox), NSMinY(closeBox))];
            [cross setLineWidth:1.5f];
            [[NSColor colorWithCalibratedWhite:(isPrivate ? 0.85f : 0.35f) alpha:1.0f] set];
            [cross stroke];
        }
    }

    // The edge against the page.
    [[NSColor colorWithCalibratedWhite:(isPrivate ? 0.10f : 0.68f) alpha:1.0f] set];
    NSRectFill(NSMakeRect(NSWidth([self bounds]) - 1.0f, NSMinY(dirtyRect), 1.0f, NSHeight(dirtyRect)));
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    int row = [self rowAtPoint:point];
    NSArray *tabs;

    if (row < 0)
        return;
    tabs = [controller tabsForTabBar];
    if ((unsigned)row >= [tabs count])
        return;

    if (NSPointInRect(point, [self closeBoxInRow:[self frameForRow:row]])) {
        trackingRow = row;
        [self setNeedsDisplay:YES];
        return;
    }
    [controller tabBarSelectTab:[tabs objectAtIndex:row]];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    int row = trackingRow;
    NSArray *tabs = [controller tabsForTabBar];

    trackingRow = -1;
    if (row < 0 || (unsigned)row >= [tabs count])
        return;
    // Only close if the mouse is still on the same close box, the way a
    // button behaves.
    if (NSPointInRect(point, [self closeBoxInRow:[self frameForRow:row]]))
        [controller tabBarCloseTab:[tabs objectAtIndex:row]];
    [self setNeedsDisplay:YES];
}

@end
