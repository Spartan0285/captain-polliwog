/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPFindBar.h"
#import <WebKit/WebKit.h>

// Highlighting and counting every match are WebKit SPI, present in Tiger's
// Safari 4 WebKit and in the bundled engine alike; checked before use.
@interface WebView (CPFindBarSPI)
- (unsigned)markAllMatchesForText:(NSString *)string caseSensitive:(BOOL)caseFlag highlight:(BOOL)highlight limit:(unsigned)limit;
- (void)unmarkAllTextMatches;
@end

static const unsigned CPFindMatchLimit = 1000;

@interface CPFindBar (Private)
- (NSButton *)addButtonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action;
- (void)setCount:(unsigned)count;
@end

@implementation CPFindBar

- (id)initWithFrame:(NSRect)frame owner:(id <CPFindBarOwner>)anOwner
{
    float width = NSWidth(frame);
    float height = NSHeight(frame);
    NSFont *small = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    NSButton *done;

    self = [super initWithFrame:frame];
    if (self == nil)
        return nil;
    owner = anOwner;

    done = [self addButtonWithTitle:@"Done" frame:NSMakeRect(width - 62.0f, floorf((height - 20.0f) / 2.0f), 54.0f, 20.0f)
                             action:@selector(done:)];
    [done setKeyEquivalent:@"\033"];
    [done setAutoresizingMask:NSViewMinXMargin];

    nextButton = [self addButtonWithTitle:@"›" frame:NSMakeRect(width - 96.0f, floorf((height - 20.0f) / 2.0f), 28.0f, 20.0f)
                                   action:@selector(findNext:)];
    [nextButton setToolTip:@"Next match"];
    [nextButton setAutoresizingMask:NSViewMinXMargin];
    previousButton = [self addButtonWithTitle:@"‹" frame:NSMakeRect(width - 126.0f, floorf((height - 20.0f) / 2.0f), 28.0f, 20.0f)
                                       action:@selector(findPrevious:)];
    [previousButton setToolTip:@"Previous match"];
    [previousButton setAutoresizingMask:NSViewMinXMargin];

    field = [[NSSearchField alloc] initWithFrame:NSMakeRect(width - 346.0f, floorf((height - 19.0f) / 2.0f), 212.0f, 19.0f)];
    [[field cell] setControlSize:NSSmallControlSize];
    [field setFont:small];
    [[field cell] setPlaceholderString:@"Find on Page"];
    [[field cell] setSendsWholeSearchString:NO];
    [[field cell] setScrollable:YES];
    [field setTarget:self];
    [field setAction:@selector(searchChanged:)];
    [field setDelegate:(id)self];
    [field setAutoresizingMask:NSViewMinXMargin];
    [self addSubview:field];
    [field release];

    countLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(8.0f, floorf((height - 14.0f) / 2.0f), width - 362.0f, 14.0f)];
    [countLabel setEditable:NO];
    [countLabel setSelectable:NO];
    [countLabel setBezeled:NO];
    [countLabel setDrawsBackground:NO];
    [countLabel setFont:small];
    [countLabel setAlignment:NSRightTextAlignment];
    [countLabel setTextColor:[NSColor colorWithCalibratedWhite:0.35f alpha:1.0f]];
    [countLabel setAutoresizingMask:NSViewWidthSizable];
    [countLabel setStringValue:@""];
    [self addSubview:countLabel];
    [countLabel release];

    [self setCount:0];
    return self;
}

- (NSSearchField *)field
{
    return field;
}

- (NSString *)searchString
{
    return [field stringValue];
}

- (void)setSearchString:(NSString *)string
{
    [field setStringValue:(string != nil ? string : @"")];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = [self bounds];
    [[NSColor colorWithCalibratedWhite:0.88f alpha:1.0f] set];
    NSRectFill(dirtyRect);
    [[NSColor colorWithCalibratedWhite:0.62f alpha:1.0f] set];
    NSRectFill(NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), 1.0f));
}

- (void)findForward:(BOOL)forward
{
    WebView *page = [owner webViewForFindBar];
    NSString *string = [field stringValue];

    if (page == nil || [string length] == 0) {
        NSBeep();
        return;
    }
    if (![page searchFor:string direction:forward caseSensitive:NO wrap:YES])
        NSBeep();
}

- (void)refreshMatches
{
    WebView *page = [owner webViewForFindBar];
    NSString *string = [field stringValue];
    unsigned count = 0;

    if (page == nil)
        return;
    if ([page respondsToSelector:@selector(unmarkAllTextMatches)])
        [page unmarkAllTextMatches];
    if ([string length] == 0) {
        [self setCount:0];
        [countLabel setStringValue:@""];
        return;
    }
    if ([page respondsToSelector:@selector(markAllMatchesForText:caseSensitive:highlight:limit:)])
        count = [page markAllMatchesForText:string caseSensitive:NO highlight:YES limit:CPFindMatchLimit];
    else
        count = [page searchFor:string direction:YES caseSensitive:NO wrap:YES] ? 1 : 0;
    [self setCount:count];
    // Select the first match from the top of the page, as Safari does while
    // typing.
    if (count > 0) {
        [page setSelectedDOMRange:nil affinity:NSSelectionAffinityDownstream];
        [page searchFor:string direction:YES caseSensitive:NO wrap:YES];
    }
}

- (void)clearMatches
{
    WebView *page = [owner webViewForFindBar];
    if ([page respondsToSelector:@selector(unmarkAllTextMatches)])
        [page unmarkAllTextMatches];
}

- (IBAction)searchChanged:(id)sender
{
    [self refreshMatches];
}

- (IBAction)findNext:(id)sender
{
    [self findForward:YES];
}

- (IBAction)findPrevious:(id)sender
{
    [self findForward:NO];
}

- (IBAction)done:(id)sender
{
    [owner findBarShouldClose];
}

// Return finds the next match, shift-Return the previous one; Escape closes
// the bar.
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
    if (command == @selector(insertNewline:)) {
        [self findForward:!([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask)];
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        [owner findBarShouldClose];
        return YES;
    }
    return NO;
}

@end

@implementation CPFindBar (Private)

- (NSButton *)addButtonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setBezelStyle:NSRoundRectBezelStyle];
    [[button cell] setControlSize:NSSmallControlSize];
    [button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [button setTitle:title];
    [button setTarget:self];
    [button setAction:action];
    [self addSubview:button];
    [button release];
    return button;
}

- (void)setCount:(unsigned)count
{
    NSString *string = [field stringValue];

    [previousButton setEnabled:count > 0];
    [nextButton setEnabled:count > 0];
    if ([string length] == 0)
        [countLabel setStringValue:@""];
    else if (count == 0)
        [countLabel setStringValue:@"Not found"];
    else if (count >= CPFindMatchLimit)
        [countLabel setStringValue:[NSString stringWithFormat:@"More than %u matches", CPFindMatchLimit - 1]];
    else if (count == 1)
        [countLabel setStringValue:@"1 match"];
    else
        [countLabel setStringValue:[NSString stringWithFormat:@"%u matches", count]];
}

@end
