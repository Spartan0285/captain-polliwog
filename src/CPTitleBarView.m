/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPTitleBarView.h"

@interface CPTitleBarView (Private)
- (void)layoutWindowButtons;
- (void)windowButtonMoved:(NSNotification *)notification;
- (void)windowStateChanged:(NSNotification *)notification;
@end

static const NSWindowButton CPWindowButtons[] = {
    NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton
};

@implementation CPTitleBarView

+ (CPTitleBarView *)installInWindow:(NSWindow *)window height:(float)height
{
    NSView *frameView = [[window contentView] superview];
    NSRect bounds = [frameView bounds];
    CPTitleBarView *bar = [[CPTitleBarView alloc] initWithFrame:NSMakeRect(0.0f, NSHeight(bounds) - height,
                                                                           NSWidth(bounds), height)];
    NSArray *siblings = [frameView subviews];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    unsigned index;

    [bar setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    // Behind everything else in the frame view: the window's buttons stay on
    // top, and the content view (which leaves this band alone) doesn't overlap.
    if ([siblings count] > 0)
        [frameView addSubview:bar positioned:NSWindowBelow relativeTo:[siblings objectAtIndex:0]];
    else
        [frameView addSubview:bar];
    [bar release];

    // The frame view puts its buttons back at the top whenever it lays them
    // out again (after resizing, among other times); follow them.
    for (index = 0; index < sizeof(CPWindowButtons) / sizeof(CPWindowButtons[0]); index++) {
        NSButton *button = [window standardWindowButton:CPWindowButtons[index]];
        [button setPostsFrameChangedNotifications:YES];
        [center addObserver:bar selector:@selector(windowButtonMoved:)
                       name:NSViewFrameDidChangeNotification object:button];
    }
    [center addObserver:bar selector:@selector(windowButtonMoved:)
                   name:NSWindowDidResizeNotification object:window];
    [center addObserver:bar selector:@selector(windowStateChanged:)
                   name:NSWindowDidBecomeMainNotification object:window];
    [center addObserver:bar selector:@selector(windowStateChanged:)
                   name:NSWindowDidResignMainNotification object:window];
    [bar layoutWindowButtons];
    return bar;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (float)windowButtonsMaxX
{
    NSButton *zoom = [[self window] standardWindowButton:NSWindowZoomButton];
    if (zoom == nil)
        return 70.0f;
    return NSMaxX([self convertRect:[zoom bounds] fromView:zoom]);
}

- (BOOL)isOpaque
{
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = [self bounds];
    BOOL active = [[self window] isMainWindow];
    // Light, as Safari's bar is, running down into the tab strip's gray.
    float top = active ? 0.92f : 0.965f;
    float bottom = active ? 0.80f : 0.91f;
    float radius = 5.0f;
    NSBezierPath *shape = [NSBezierPath bezierPath];
    int row;
    int rows = (int)NSHeight(bounds);

    // Square below, rounded at the top like the window's own title bar.
    [shape moveToPoint:NSMakePoint(NSMinX(bounds), NSMinY(bounds))];
    [shape lineToPoint:NSMakePoint(NSMaxX(bounds), NSMinY(bounds))];
    [shape appendBezierPathWithArcFromPoint:NSMakePoint(NSMaxX(bounds), NSMaxY(bounds))
                                    toPoint:NSMakePoint(NSMidX(bounds), NSMaxY(bounds)) radius:radius];
    [shape appendBezierPathWithArcFromPoint:NSMakePoint(NSMinX(bounds), NSMaxY(bounds))
                                    toPoint:NSMakePoint(NSMinX(bounds), NSMinY(bounds)) radius:radius];
    [shape closePath];

    [NSGraphicsContext saveGraphicsState];
    [shape addClip];
    // A gradient by rows: NSGradient only arrived with Leopard.
    for (row = 0; row < rows; row++) {
        float fraction = rows > 1 ? (float)row / (float)(rows - 1) : 0.0f;
        [[NSColor colorWithCalibratedWhite:(bottom + (top - bottom) * fraction) alpha:1.0f] set];
        NSRectFill(NSIntersectionRect(NSMakeRect(NSMinX(bounds), NSMinY(bounds) + row, NSWidth(bounds), 1.0f),
                                      dirtyRect));
    }
    // A highlight along the top edge and a line under the bar.
    [[NSColor colorWithCalibratedWhite:(active ? 0.98f : 0.99f) alpha:1.0f] set];
    NSRectFill(NSMakeRect(NSMinX(bounds), NSMaxY(bounds) - 1.0f, NSWidth(bounds), 1.0f));
    [NSGraphicsContext restoreGraphicsState];

    [[NSColor colorWithCalibratedWhite:(active ? 0.58f : 0.72f) alpha:1.0f] set];
    NSRectFill(NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), 1.0f));
}

// Dragging the bar moves the window; a double-click minimizes it (or zooms
// it, if the user has turned off "Double-click a window's title bar to
// minimize").
- (void)mouseDown:(NSEvent *)event
{
    NSWindow *window = [self window];
    NSPoint start;
    NSPoint origin;

    if ([event clickCount] == 2) {
        id setting = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleMiniaturizeOnDoubleClick"];
        if (setting == nil || [setting boolValue])
            [window performMiniaturize:self];
        else
            [window performZoom:self];
        return;
    }

    start = [window convertBaseToScreen:[event locationInWindow]];
    origin = [window frame].origin;
    for (;;) {
        NSEvent *next = [window nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
        NSPoint now;
        NSRect frame;
        NSRect limit;

        if ([next type] == NSLeftMouseUp)
            break;
        now = [window convertBaseToScreen:[next locationInWindow]];
        frame = [window frame];
        frame.origin = NSMakePoint(origin.x + now.x - start.x, origin.y + now.y - start.y);
        // Like a title bar, it can't go up under the menu bar.
        limit = [[window screen] visibleFrame];
        if ([window screen] != nil && NSMaxY(frame) > NSMaxY(limit))
            frame.origin.y = NSMaxY(limit) - NSHeight(frame);
        [window setFrameOrigin:frame.origin];
    }
}

@end

@implementation CPTitleBarView (Private)

// Centers the window's buttons vertically in the bar, keeping their
// positions across.
- (void)layoutWindowButtons
{
    static BOOL laying = NO;
    NSWindow *window = [self window];
    NSView *frameView = [self superview];
    unsigned index;

    if (laying || window == nil || frameView == nil)
        return;
    laying = YES;
    for (index = 0; index < sizeof(CPWindowButtons) / sizeof(CPWindowButtons[0]); index++) {
        NSButton *button = [window standardWindowButton:CPWindowButtons[index]];
        NSRect frame;
        float y;

        if (button == nil || [button superview] != frameView)
            continue;
        frame = [button frame];
        y = floorf(NSMinY([self frame]) + (NSHeight([self frame]) - NSHeight(frame)) / 2.0f);
        if (NSMinY(frame) != y) {
            [button setFrameOrigin:NSMakePoint(NSMinX(frame), y)];
            [frameView setNeedsDisplayInRect:NSUnionRect(frame, [button frame])];
        }
    }
    laying = NO;
}

- (void)windowButtonMoved:(NSNotification *)notification
{
    [self layoutWindowButtons];
}

- (void)windowStateChanged:(NSNotification *)notification
{
    [self setNeedsDisplay:YES];
}

@end

@implementation CPUnifiedContentView

// Control-Tab and Shift-Control-Tab cycle tabs, as in Safari. This cannot
// be a menu key equivalent: a Tab key equivalent draws as a stray glyph in
// the menu and fights the key view loop. It belongs on the content view
// rather than the window controller, which AppKit never asks - a window
// hands performKeyEquivalent: to its content view and down the subviews,
// and stops at the window itself.
//
// Taken before super so that a focused WebView does not spend it on its
// own focus navigation first.
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    NSString *characters = [event charactersIgnoringModifiers];
    unsigned modifiers = [event modifierFlags];

    if ([characters length] == 1 && [characters characterAtIndex:0] == '\t'
        && (modifiers & NSControlKeyMask) != 0
        && (modifiers & (NSCommandKeyMask | NSAlternateKeyMask)) == 0) {
        id controller = [[self window] windowController];
        SEL action = ((modifiers & NSShiftKeyMask) != 0) ? @selector(selectPreviousTab:)
                                                         : @selector(selectNextTab:);
        if ([controller respondsToSelector:action]) {
            [controller performSelector:action withObject:self];
            return YES;
        }
    }
    return [super performKeyEquivalent:event];
}

- (void)setOverlap:(float)height
{
    overlap = height;
}

- (NSView *)hitTest:(NSPoint)point
{
    // point is in the superview's coordinates.
    if (point.y >= NSMaxY([self frame]) - overlap)
        return nil;
    return [super hitTest:point];
}

@end
