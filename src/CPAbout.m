/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAbout.h"
#import "CPAppDelegate.h"
#import "CPWelcome.h"
#import <WebKit/WebKit.h>

#define ABOUT_W 460.0
#define ABOUT_H 430.0
#define PAD     28.0

// Cytrus Software's lime, from the site, and the purple sampled from the
// app's own icon. Lime takes near-black and purple takes white; the other way
// round is unreadable on a CRT, and these are CRTs.
static NSColor *CPLime(void)      { return [NSColor colorWithCalibratedRed:0.659 green:0.847 blue:0.102 alpha:1]; }
static NSColor *CPLimeInk(void)   { return [NSColor colorWithCalibratedRed:0.102 green:0.165 blue:0.0   alpha:1]; }
static NSColor *CPPurple(void)    { return [NSColor colorWithCalibratedRed:0.435 green:0.180 blue:0.494 alpha:1]; }
static NSColor *CPSubtleText(void) { return [NSColor colorWithCalibratedWhite:0.42 alpha:1]; }

// 10.4 has no -bezierPathWithRoundedRect:.
static NSBezierPath *CPRoundRect(NSRect r, float radius)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    float x = NSMinX(r), y = NSMinY(r), w = NSWidth(r), h = NSHeight(r);

    if (radius > w / 2) radius = w / 2;
    if (radius > h / 2) radius = h / 2;
    [path moveToPoint:NSMakePoint(x + radius, y)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(x + w, y) toPoint:NSMakePoint(x + w, y + h) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(x + w, y + h) toPoint:NSMakePoint(x, y + h) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(x, y + h) toPoint:NSMakePoint(x, y) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(x, y) toPoint:NSMakePoint(x + w, y) radius:radius];
    [path closePath];
    return path;
}

// An image, the right way up, in a view that draws top-down.
//
// -drawInRect: in a flipped view lands the image upside down: text drawing
// accounts for flippedness and image drawing does not. Flipping the
// transform about the destination rectangle puts it back without touching
// the NSImage, which matters because one of these can be the shared
// application icon and setting -setFlipped: on that would follow it
// everywhere else it is drawn.
static void CPDrawImage(NSImage *image, NSRect r)
{
    NSAffineTransform *flip = [NSAffineTransform transform];

    if (image == nil)
        return;
    [NSGraphicsContext saveGraphicsState];
    [flip translateXBy:0.0f yBy:NSMaxY(r) + NSMinY(r)];
    [flip scaleXBy:1.0f yBy:-1.0f];
    [flip concat];
    [image drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
    [NSGraphicsContext restoreGraphicsState];
}

static void CPDrawText(NSString *text, NSRect r, NSFont *font, NSColor *colour)
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        font, NSFontAttributeName, colour, NSForegroundColorAttributeName, nil];
    [text drawInRect:r withAttributes:attributes];
}

// A paragraph at a given width, as tall as this system sets it - Tiger sets
// Lucida Grande a little taller than Leopard does, so fixed boxes sized by
// eye on one clip the last line on the other. Draws only when asked, so the
// same pass can size the window before anything is on screen.
static float CPParagraph(NSString *text, float x, float y, float width, NSFont *font, BOOL draw)
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        font, NSFontAttributeName, [NSColor blackColor], NSForegroundColorAttributeName, nil];
    float height = ceilf(NSHeight([text boundingRectWithSize:NSMakeSize(width, 10000.0f)
                                                     options:NSStringDrawingUsesLineFragmentOrigin
                                                  attributes:attributes]));
    if (draw)
        [text drawInRect:NSMakeRect(x, y, width, height + 2) withAttributes:attributes];
    return height;
}

#pragma mark A button with a colour of its own

// NSButton will not fill itself with an arbitrary colour on 10.4, so this
// draws the whole thing.
@interface CPColorButton : NSButton
{
    NSColor *fill, *ink;
}
- (void)setFill:(NSColor *)aFill ink:(NSColor *)anInk;
@end

@implementation CPColorButton

- (void)setFill:(NSColor *)aFill ink:(NSColor *)anInk
{
    [fill autorelease]; fill = [aFill retain];
    [ink autorelease];  ink = [anInk retain];
    [self setNeedsDisplay:YES];
}

- (void)dealloc { [fill release]; [ink release]; [super dealloc]; }

- (void)drawRect:(NSRect)dirty
{
    NSRect r = NSInsetRect([self bounds], 0.5f, 0.5f);
    NSColor *colour = fill != nil ? fill : [NSColor grayColor];
    NSDictionary *attributes;
    NSSize size;

    // NSButton has no -isHighlighted; its cell does.
    if ([[self cell] isHighlighted])
        colour = [colour blendedColorWithFraction:0.25f ofColor:[NSColor blackColor]];
    [colour set];
    [CPRoundRect(r, 6.0f) fill];
    [[colour blendedColorWithFraction:0.35f ofColor:[NSColor blackColor]] set];
    [CPRoundRect(r, 6.0f) stroke];

    attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize:12], NSFontAttributeName,
        ink != nil ? ink : [NSColor whiteColor], NSForegroundColorAttributeName, nil];
    size = [[self title] sizeWithAttributes:attributes];
    [[self title] drawAtPoint:NSMakePoint(NSMidX(r) - size.width / 2, NSMidY(r) - size.height / 2)
               withAttributes:attributes];
}

@end

#pragma mark The window's contents

@interface CPAboutView : NSView
{
    NSImage *appIcon, *logo;
}
- (float)layout:(BOOL)draw width:(float)w;
@end

@implementation CPAboutView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]) == nil)
        return nil;
    appIcon = [CPApplicationIcon() retain];
    // The whole lockup, rasterised where the brand's typeface exists. The
    // artwork's wordmark is live text in Ariana Pro, which no Mac here has,
    // so anything rendered on these machines would substitute a fallback
    // face - which is why this arrives as a finished image rather than a
    // mark to assemble a name beside.
    logo = [[NSImage alloc] initWithContentsOfFile:
               [[NSBundle mainBundle] pathForResource:@"cytruslogo" ofType:@"png"]];
    return self;
}

- (void)dealloc { [appIcon release]; [logo release]; [super dealloc]; }

// Drawing top-down reads in the order the text is written. Note that this
// also lays out subviews top-down, so the two buttons measure themselves
// from the bottom of the window by hand.
- (BOOL)isFlipped { return YES; }

- (float)layout:(BOOL)draw width:(float)w
{
    float y = PAD, column = w - 2 * PAD;
    NSString *stage = [CPAbout stage];

    if (draw) {
        CPDrawImage(appIcon, NSMakeRect(PAD, y, 56, 56));
        CPDrawText(@"Captain Polliwog", NSMakeRect(PAD + 70, y + 2, w - PAD - 70, 26),
                   [NSFont boldSystemFontOfSize:18], [NSColor blackColor]);
        CPDrawText([CPAbout versionLine], NSMakeRect(PAD + 70, y + 30, w - PAD - 70, 16),
                   [NSFont systemFontOfSize:11], CPSubtleText());
        // Which WebKit is actually answering. The bundled one reads the
        // modern web; if this says the Mac's own, pages will struggle, and
        // that one line explains why before anyone has to ask.
        CPDrawText([CPAbout engineLine], NSMakeRect(PAD + 70, y + 46, w - PAD - 70, 16),
                   [NSFont systemFontOfSize:11],
                   [CPAbout usesBundledEngine] ? CPSubtleText()
                       : [NSColor colorWithCalibratedRed:0.72f green:0.20f blue:0.05f alpha:1]);
        if ([stage length] > 0) {
            NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSFont boldSystemFontOfSize:10], NSFontAttributeName,
                [NSColor whiteColor], NSForegroundColorAttributeName, nil];
            NSSize size = [stage sizeWithAttributes:attributes];
            NSRect badge = NSMakeRect(PAD + 70, y + 64, size.width + 16, 16);
            [[NSColor colorWithCalibratedRed:0.80f green:0.35f blue:0.04f alpha:1] set];
            [CPRoundRect(badge, 8.0f) fill];
            [stage drawAtPoint:NSMakePoint(badge.origin.x + 8, badge.origin.y + 1) withAttributes:attributes];
        }
    }
    y += 94;

    if (draw) {
        [[NSColor colorWithCalibratedWhite:0.87f alpha:1] set];
        NSRectFill(NSMakeRect(PAD, y, column, 1));
    }
    y += 14;

    y += CPParagraph(@"This is an alpha build. Expect rough edges, and please say when you find one.",
                     PAD, y, column, [NSFont boldSystemFontOfSize:11], draw) + 10;

    // What it is not, plainly and early.
    y += CPParagraph(@"Captain Polliwog is not made by Apple and is not Safari. It is built on "
                      "WebKit, the same engine Safari uses, brought forward to a version that can "
                      "still read the modern web - and it will not always agree with the browser "
                      "on your other computer.",
                     PAD, y, column, [NSFont systemFontOfSize:11], draw) + 10;

    y += CPParagraph(@"Cytrus Software (a.k.a. Cytrus Retro) is a personal side project by me, "
                      "Adam Cipoletti, a Creative Director and Career Coach. You can find more of "
                      "my vintage software and hardware projects at cytrusretro.com.",
                     PAD, y, column, [NSFont systemFontOfSize:11], draw) + 14;

    // The lockup, centred, at the artwork's own proportions.
    if (logo != nil) {
        NSSize size = [logo size];
        float logoWidth = 260.0f;
        float logoHeight = size.width > 0 ? logoWidth * size.height / size.width : 68.0f;

        if (draw)
            CPDrawImage(logo, NSMakeRect((w - logoWidth) / 2, y, logoWidth, logoHeight));
        y += logoHeight;
    }
    return y;
}

- (void)drawRect:(NSRect)dirty
{
    [[NSColor whiteColor] set];
    NSRectFill(dirty);
    [self layout:YES width:NSWidth([self bounds])];
}

@end

#pragma mark The window

@interface CPAbout (Private)
- (void)showWindow;
@end

static CPAbout *sharedAbout = nil;

@implementation CPAbout

+ (NSString *)stage
{
    NSString *stage = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CPBuildStage"];
    return [stage length] > 0 ? stage : nil;
}

+ (NSString *)versionLine
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    return [NSString stringWithFormat:@"Version %@ (build %@)",
            version != nil ? version : @"?", build != nil ? build : @"?"];
}

// The WebKit that was actually loaded, not the one in the bundle: on Tiger
// the bundled engine may not load, and then everything is quietly the
// system's own, from 2009.
+ (BOOL)usesBundledEngine
{
    NSString *loaded = [[NSBundle bundleForClass:[WebView class]] bundlePath];
    return [loaded hasPrefix:[[NSBundle mainBundle] bundlePath]];
}

// "WebKit 604.5.6", from the framework's own version. Apple's builds put the
// operating system in front as a fourth digit - 5604 is WebKit 604 for 10.5,
// 4533 is WebKit 533 for 10.4 - and that digit is not part of the answer.
+ (NSString *)engineVersion
{
    NSString *raw = [[NSBundle bundleForClass:[WebView class]] objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSMutableArray *parts = [NSMutableArray arrayWithArray:[raw componentsSeparatedByString:@"."]];

    if ([parts count] > 0 && [[parts objectAtIndex:0] length] == 4)
        [parts replaceObjectAtIndex:0 withObject:[[parts objectAtIndex:0] substringFromIndex:1]];
    return [parts componentsJoinedByString:@"."];
}

+ (NSString *)engineLine
{
    return [CPAbout usesBundledEngine]
        ? [NSString stringWithFormat:@"Engine: WebKit %@, bundled", [self engineVersion]]
        : [NSString stringWithFormat:@"Engine: WebKit %@, this Mac's own - older", [self engineVersion]];
}

+ (void)show
{
    if (sharedAbout == nil)
        sharedAbout = [[self alloc] init];
    [sharedAbout showWindow];
}

- (void)showWindow
{
    if (window == nil) {
        NSRect frame = NSMakeRect(0, 0, ABOUT_W, ABOUT_H);
        CPAboutView *view;
        CPColorButton *cytrus, *coach;
        float buttonWidth = (ABOUT_W - 2 * PAD - 16) / 2;

        float height;

        // Measured before the window exists: the text above the buttons is
        // as tall as this system sets it, and the window follows.
        view = [[[CPAboutView alloc] initWithFrame:frame] autorelease];
        height = [view layout:NO width:ABOUT_W] + 24 + 34 + 24;
        if (height < ABOUT_H)
            height = ABOUT_H;
        frame = NSMakeRect(0, 0, ABOUT_W, height);
        [view setFrame:frame];

        window = [[NSWindow alloc] initWithContentRect:frame
                      styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                        backing:NSBackingStoreBuffered defer:NO];
        [window setTitle:@"About Captain Polliwog"];
        [window setReleasedWhenClosed:NO];
        [window setContentView:view];

        // The view draws top-down, which places subviews top-down too, so a
        // button at y = 24 would land over the icon. Measured from the
        // bottom by hand.
        cytrus = [[[CPColorButton alloc] initWithFrame:
                      NSMakeRect(PAD, height - 24 - 34, buttonWidth, 34)] autorelease];
        [cytrus setBordered:NO];
        [cytrus setTitle:@"cytrusretro.com"];
        [cytrus setFill:CPLime() ink:CPLimeInk()];
        [cytrus setTarget:self];
        [cytrus setAction:@selector(openCytrus:)];
        [view addSubview:cytrus];

        coach = [[[CPColorButton alloc] initWithFrame:
                     NSMakeRect(PAD + buttonWidth + 16, height - 24 - 34, buttonWidth, 34)] autorelease];
        [coach setBordered:NO];
        [coach setTitle:@"amcreativecoach.com"];
        [coach setFill:CPPurple() ink:[NSColor whiteColor]];
        [coach setTarget:self];
        [coach setAction:@selector(openCoach:)];
        [view addSubview:coach];

        [window center];
    }
    [window makeKeyAndOrderFront:nil];
}

// Every other app in this family has to ask where a link should open, because
// the browser the Mac came with stops at TLS 1.0 and these sites refuse it.
// This one is that browser, so it just opens a tab.
- (void)openCytrus:(id)sender
{
    [(CPAppDelegate *)[NSApp delegate] openAddress:@"https://www.cytrusretro.com/"];
}

- (void)openCoach:(id)sender
{
    [(CPAppDelegate *)[NSApp delegate] openAddress:@"https://www.amcreativecoach.com/"];
}

@end
