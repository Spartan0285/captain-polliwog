/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAddressBar.h"
#import "CPIcons.h"

#define CPButtonSize 20.0f

// A rounded rectangle; NSBezierPath's own arrived with 10.5.
static NSBezierPath *CPRoundedRect(NSRect rect, float radius)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(NSMinX(rect) + radius, NSMinY(rect))];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect)) toPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect)) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect)) toPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect)) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect)) toPoint:NSMakePoint(NSMinX(rect), NSMinY(rect)) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(NSMinX(rect), NSMinY(rect)) toPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect)) radius:radius];
    [path closePath];
    return path;
}

static NSButton *CPInlineButton(NSView *parent, NSRect frame, NSImage *image, NSString *toolTip)
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setBordered:NO];
    [button setImage:image];
    [button setImagePosition:NSImageOnly];
    [[button cell] setHighlightsBy:NSContentsCellMask];
    [button setToolTip:toolTip];
    [button setAutoresizingMask:NSViewMinXMargin];
    [parent addSubview:button];
    [button release];
    return button;
}

@implementation CPAddressBar

- (id)initWithFrame:(NSRect)frame
{
    float height = NSHeight(frame), width = NSWidth(frame);
    float buttonY = floorf((height - CPButtonSize) / 2.0f);

    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;

    iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(8.0f, floorf((height - 16.0f) / 2.0f), 16.0f, 16.0f)];
    [iconView setImageFrameStyle:NSImageFrameNone];
    [iconView setImageScaling:NSScaleProportionally];
    [iconView setImage:[CPIcons globeImage]];
    [self addSubview:iconView];
    [iconView release];

    textField = [[NSTextField alloc] initWithFrame:NSMakeRect(30.0f, floorf((height - 17.0f) / 2.0f), width - 30.0f - 3.0f * CPButtonSize - 10.0f, 17.0f)];
    [textField setBezeled:NO];
    [textField setBordered:NO];
    [textField setDrawsBackground:NO];
    [textField setFocusRingType:NSFocusRingTypeNone];
    [textField setAutoresizingMask:NSViewWidthSizable];
    [[textField cell] setScrollable:YES];
    [[textField cell] setSendsActionOnEndEditing:NO];
    [self addSubview:textField];
    [textField release];

    favoriteButton = CPInlineButton(self, NSMakeRect(width - 3.0f * CPButtonSize - 8.0f, buttonY, CPButtonSize, CPButtonSize),
                                    [CPIcons starImage], @"Add to Favorites");
    pageButton = CPInlineButton(self, NSMakeRect(width - 2.0f * CPButtonSize - 6.0f, buttonY, CPButtonSize, CPButtonSize),
                                [CPIcons pageSettingsImage], @"Text size, Reader and settings for this website");
    reloadButton = CPInlineButton(self, NSMakeRect(width - CPButtonSize - 4.0f, buttonY, CPButtonSize, CPButtonSize),
                                  [CPIcons reloadImage], @"Reload");
    return self;
}

- (NSTextField *)textField { return textField; }
- (NSButton *)favoriteButton { return favoriteButton; }
- (NSButton *)pageButton { return pageButton; }
- (NSButton *)reloadButton { return reloadButton; }

- (void)setIcon:(NSImage *)icon
{
    [iconView setImage:(icon != nil ? icon : [CPIcons globeImage])];
}

- (void)setProgress:(double)value
{
    if (value == progress)
        return;
    progress = value;
    [self setNeedsDisplayInRect:NSMakeRect(0.0f, 0.0f, NSWidth([self bounds]), 4.0f)];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect field = NSInsetRect([self bounds], 0.5f, 0.5f);
    NSBezierPath *outline = CPRoundedRect(field, 6.0f);
    BOOL editing = [[self window] firstResponder] == [textField currentEditor] && [textField currentEditor] != nil;

    [[NSColor colorWithCalibratedWhite:(editing ? 1.0f : 0.93f) alpha:1.0f] set];
    [outline fill];
    if (progress > 0.0 && progress < 1.0) {
        // Safari's blue line, filling as the page loads.
        [NSGraphicsContext saveGraphicsState];
        [outline addClip];
        [[NSColor colorWithCalibratedRed:0.25f green:0.55f blue:0.95f alpha:1.0f] set];
        NSRectFill(NSMakeRect(NSMinX(field), NSMinY(field), NSWidth(field) * progress, 2.5f));
        [NSGraphicsContext restoreGraphicsState];
    }
    [[NSColor colorWithCalibratedWhite:(editing ? 0.55f : 0.72f) alpha:1.0f] set];
    [outline setLineWidth:1.0f];
    [outline stroke];
}

@end
