/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPTabOverview.h"
#import "CPTab.h"
#import <WebKit/WebKit.h>

#define CPCardWidth      196.0f
#define CPCardHeight     160.0f     // including the title strip
#define CPTitleHeight    20.0f
#define CPCardGap        18.0f
#define CPTopMargin      54.0f      // room for the buttons along the top
#define CPCloseBoxSize   16.0f

@interface CPTabOverview (Private)
- (void)takeThumbnails;
- (NSRect)frameForCardAtIndex:(int)index;
- (NSRect)closeBoxForCard:(NSRect)card;
- (int)indexAtPoint:(NSPoint)point;
- (void)layoutButtons;
- (void)closeAll:(id)sender;
- (void)newTab:(id)sender;
@end

@implementation CPTabOverview

+ (CPTabOverview *)overviewInWindow:(NSWindow *)window
{
    NSArray *children = [[window contentView] subviews];
    unsigned index;

    for (index = 0; index < [children count]; index++) {
        if ([[children objectAtIndex:index] isKindOfClass:[CPTabOverview class]])
            return [children objectAtIndex:index];
    }
    return nil;
}

+ (BOOL)isShowingInWindow:(NSWindow *)window
{
    return [self overviewInWindow:window] != nil;
}

+ (void)hideInWindow:(NSWindow *)window
{
    CPTabOverview *overview = [self overviewInWindow:window];

    if (overview == nil)
        return;
    [overview removeFromSuperview];
    // The page was under the overview all along; let it draw again.
    [[window contentView] setNeedsDisplay:YES];
}

+ (BOOL)toggleInWindow:(NSWindow *)window controller:(id)aController
{
    CPTabOverview *overview;
    NSView *content = [window contentView];

    if ([self isShowingInWindow:window]) {
        [self hideInWindow:window];
        return NO;
    }

    overview = [[[CPTabOverview alloc] initWithFrame:[content bounds]] autorelease];
    [overview setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    overview->controller = aController;
    [overview takeThumbnails];
    [content addSubview:overview];
    [window makeFirstResponder:overview];
    return YES;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil) {
        hoveredIndex = -1;      // zero would mean "the first card"
        hoveredClose = -1;
    }
    return self;
}

- (void)dealloc
{
    [shownTabs release];
    [thumbnails release];
    [super dealloc];
}

- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

#pragma mark Thumbnails

// Taken once, when the overview opens. cacheDisplayInRect: draws the view as
// it is, without waiting for the page to do anything, which is what makes
// this affordable here: no layout, no script, just the pixels already there.
- (void)takeThumbnails
{
    NSArray *tabs = [controller tabsForTabBar];
    unsigned index;

    [shownTabs release];
    shownTabs = [tabs copy];
    [thumbnails release];
    thumbnails = [[NSMutableArray alloc] initWithCapacity:[tabs count]];

    for (index = 0; index < [tabs count]; index++) {
        CPTab *tab = [tabs objectAtIndex:index];
        WebView *webView = [tab isDiscarded] ? nil : [tab webView];
        NSRect bounds = webView != nil ? [webView bounds] : NSZeroRect;
        NSBitmapImageRep *shot;
        NSImage *thumbnail;
        NSSize size;

        if (webView == nil || bounds.size.width < 1.0f || bounds.size.height < 1.0f) {
            [thumbnails addObject:[NSNull null]];
            continue;
        }
        shot = [webView bitmapImageRepForCachingDisplayInRect:bounds];
        if (shot == nil) {
            [thumbnails addObject:[NSNull null]];
            continue;
        }
        [webView cacheDisplayInRect:bounds toBitmapImageRep:shot];

        // Scaled down now rather than at every redraw: the card is small and
        // a full-size page image is several megabytes. The top of the page is
        // what the card shows, in the card's proportions.
        {
            NSImage *page = [[[NSImage alloc] initWithSize:bounds.size] autorelease];
            float sourceHeight;
            NSRect source;

            [page addRepresentation:shot];
            size = NSMakeSize(CPCardWidth, CPCardHeight - CPTitleHeight);
            sourceHeight = bounds.size.width * size.height / size.width;
            if (sourceHeight > bounds.size.height)
                sourceHeight = bounds.size.height;
            source = NSMakeRect(0.0f, bounds.size.height - sourceHeight,
                                bounds.size.width, sourceHeight);

            thumbnail = [[[NSImage alloc] initWithSize:size] autorelease];
            [thumbnail lockFocus];
            [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationLow];
            [page drawInRect:NSMakeRect(0.0f, 0.0f, size.width, size.height)
                    fromRect:source
                   operation:NSCompositeCopy
                    fraction:1.0f];
            [thumbnail unlockFocus];
            [thumbnails addObject:thumbnail];
        }
    }
    [self layoutButtons];
}

#pragma mark Layout

- (int)columns
{
    int columns = (int)((NSWidth([self bounds]) - CPCardGap) / (CPCardWidth + CPCardGap));
    return columns > 0 ? columns : 1;
}

- (NSRect)frameForCardAtIndex:(int)index
{
    int columns = [self columns];
    int row = index / columns;
    int column = index % columns;
    float totalWidth = columns * CPCardWidth + (columns - 1) * CPCardGap;
    float left = (NSWidth([self bounds]) - totalWidth) / 2.0f;

    if (left < CPCardGap)
        left = CPCardGap;
    return NSMakeRect(left + column * (CPCardWidth + CPCardGap),
                      NSHeight([self bounds]) - CPTopMargin - (row + 1) * CPCardHeight - row * CPCardGap,
                      CPCardWidth, CPCardHeight);
}

- (NSRect)closeBoxForCard:(NSRect)card
{
    return NSMakeRect(NSMinX(card) + 4.0f, NSMaxY(card) - CPCloseBoxSize - 4.0f,
                      CPCloseBoxSize, CPCloseBoxSize);
}

- (int)indexAtPoint:(NSPoint)point
{
    unsigned index;

    for (index = 0; index < [shownTabs count]; index++) {
        if (NSPointInRect(point, [self frameForCardAtIndex:(int)index]))
            return (int)index;
    }
    return -1;
}

- (void)layoutButtons
{
    if (closeAllButton != nil)
        return;
    closeAllButton = [[NSButton alloc] initWithFrame:
        NSMakeRect(NSWidth([self bounds]) - 130.0f, NSHeight([self bounds]) - 40.0f, 116.0f, 26.0f)];
    [closeAllButton setTitle:@"Close All Tabs"];
    [closeAllButton setBezelStyle:NSRoundedBezelStyle];
    [[closeAllButton cell] setControlSize:NSSmallControlSize];
    [closeAllButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [closeAllButton setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
    [closeAllButton setTarget:self];
    [closeAllButton setAction:@selector(closeAll:)];
    [self addSubview:closeAllButton];
    [closeAllButton release];

    newTabButton = [[NSButton alloc] initWithFrame:
        NSMakeRect(14.0f, NSHeight([self bounds]) - 40.0f, 100.0f, 26.0f)];
    [newTabButton setTitle:@"New Tab"];
    [newTabButton setBezelStyle:NSRoundedBezelStyle];
    [[newTabButton cell] setControlSize:NSSmallControlSize];
    [newTabButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [newTabButton setAutoresizingMask:NSViewMinYMargin];
    [newTabButton setTarget:self];
    [newTabButton setAction:@selector(newTab:)];
    [self addSubview:newTabButton];
    [newTabButton release];
}

#pragma mark Drawing

- (void)drawRect:(NSRect)rect
{
    CPTab *selected = [controller selectedTabForTabBar];
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    NSDictionary *titleAttributes;
    unsigned index;

    [[NSColor colorWithCalibratedWhite:0.22f alpha:1.0f] set];
    NSRectFill(rect);

    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    [style setAlignment:NSCenterTextAlignment];
    titleAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont systemFontOfSize:11.0f], NSFontAttributeName,
        [NSColor whiteColor], NSForegroundColorAttributeName,
        style, NSParagraphStyleAttributeName, nil];

    for (index = 0; index < [shownTabs count]; index++) {
        CPTab *tab = [shownTabs objectAtIndex:index];
        NSRect card = [self frameForCardAtIndex:(int)index];
        NSRect picture = NSMakeRect(NSMinX(card), NSMinY(card) + CPTitleHeight,
                                    NSWidth(card), NSHeight(card) - CPTitleHeight);
        id thumbnail = index < [thumbnails count] ? [thumbnails objectAtIndex:index] : [NSNull null];
        NSRect closeBox;

        if (!NSIntersectsRect(rect, NSInsetRect(card, -6.0f, -6.0f)))
            continue;

        // The page itself, or a plain card for a tab that has been discarded.
        if (thumbnail != (id)[NSNull null]) {
            [thumbnail drawInRect:picture fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0f];
        } else {
            [[NSColor colorWithCalibratedWhite:0.40f alpha:1.0f] set];
            NSRectFill(picture);
        }

        // The current tab, and whichever the mouse is over, get a border.
        if (tab == selected || (int)index == hoveredIndex) {
            [(tab == selected ? [NSColor whiteColor]
                              : [NSColor colorWithCalibratedWhite:0.65f alpha:1.0f]) set];
            NSFrameRectWithWidth(NSInsetRect(picture, -2.0f, -2.0f), 2.0f);
        }

        [[tab displayTitle] drawInRect:NSMakeRect(NSMinX(card) + 2.0f, NSMinY(card) + 2.0f,
                                                  NSWidth(card) - 4.0f, CPTitleHeight - 4.0f)
                        withAttributes:titleAttributes];

        // A close box in the corner, shown once the mouse is on the card.
        if ((int)index == hoveredIndex) {
            closeBox = [self closeBoxForCard:picture];
            [[NSColor colorWithCalibratedWhite:0.15f alpha:0.85f] set];
            NSRectFill(closeBox);
            [((int)index == hoveredClose ? [NSColor whiteColor]
                                         : [NSColor colorWithCalibratedWhite:0.8f alpha:1.0f]) set];
            NSFrameRect(closeBox);
            [[NSBezierPath bezierPathWithRect:NSZeroRect] stroke];
            {
                NSBezierPath *cross = [NSBezierPath bezierPath];
                NSRect inner = NSInsetRect(closeBox, 4.0f, 4.0f);
                [cross moveToPoint:NSMakePoint(NSMinX(inner), NSMinY(inner))];
                [cross lineToPoint:NSMakePoint(NSMaxX(inner), NSMaxY(inner))];
                [cross moveToPoint:NSMakePoint(NSMinX(inner), NSMaxY(inner))];
                [cross lineToPoint:NSMakePoint(NSMaxX(inner), NSMinY(inner))];
                [cross setLineWidth:1.5f];
                [cross stroke];
            }
        }
    }

    if ([shownTabs count] == 0) {
        [@"No tabs" drawInRect:NSMakeRect(0.0f, NSHeight([self bounds]) / 2.0f, NSWidth([self bounds]), 20.0f)
               withAttributes:titleAttributes];
    }
}

#pragma mark Events

- (void)mouseMoved:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    int index = [self indexAtPoint:point];
    int close = -1;

    if (index >= 0) {
        NSRect card = [self frameForCardAtIndex:index];
        NSRect picture = NSMakeRect(NSMinX(card), NSMinY(card) + CPTitleHeight,
                                    NSWidth(card), NSHeight(card) - CPTitleHeight);
        if (NSPointInRect(point, [self closeBoxForCard:picture]))
            close = index;
    }
    if (index != hoveredIndex || close != hoveredClose) {
        hoveredIndex = index;
        hoveredClose = close;
        [self setNeedsDisplay:YES];
    }
}

- (void)updateTrackingAreas
{
    // 10.4 has no tracking areas; the window sends mouseMoved: instead.
}

- (void)viewDidMoveToWindow
{
    [[self window] setAcceptsMouseMovedEvents:[self window] != nil];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    int index = [self indexAtPoint:point];
    CPTab *tab;
    NSRect card, picture;

    if (index < 0) {
        [CPTabOverview hideInWindow:[self window]];
        return;
    }
    tab = [shownTabs objectAtIndex:index];
    card = [self frameForCardAtIndex:index];
    picture = NSMakeRect(NSMinX(card), NSMinY(card) + CPTitleHeight,
                         NSWidth(card), NSHeight(card) - CPTitleHeight);

    if (NSPointInRect(point, [self closeBoxForCard:picture])) {
        [controller tabBarCloseTab:tab];
        // The window may have closed with its last tab.
        if ([self window] == nil)
            return;
        [self takeThumbnails];
        hoveredIndex = -1;
        hoveredClose = -1;
        [self setNeedsDisplay:YES];
        return;
    }
    [controller tabBarSelectTab:tab];
    [CPTabOverview hideInWindow:[self window]];
}

- (void)keyDown:(NSEvent *)event
{
    NSString *characters = [event charactersIgnoringModifiers];

    if ([characters length] > 0 && [characters characterAtIndex:0] == 27) {  // Escape
        [CPTabOverview hideInWindow:[self window]];
        return;
    }
    [super keyDown:event];
}

- (void)closeAll:(id)sender
{
    NSArray *tabs = [[shownTabs copy] autorelease];
    unsigned index;

    for (index = 0; index < [tabs count]; index++)
        [controller tabBarCloseTab:[tabs objectAtIndex:index]];
    if ([self window] != nil)
        [CPTabOverview hideInWindow:[self window]];
}

- (void)newTab:(id)sender
{
    NSWindow *window = [self window];

    [controller tabBarNewTab];
    [CPTabOverview hideInWindow:window];
}

@end
