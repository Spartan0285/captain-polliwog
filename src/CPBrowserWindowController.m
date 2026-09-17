/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPBrowserWindowController.h"
#import "CPAppDelegate.h"
#import "CPIcons.h"
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>

#define CPBarHeight     34.0f
#define CPStatusHeight  20.0f

static NSString * const CPSearchURLFormat = @"https://lite.duckduckgo.com/lite/?q=%@";

static NSString *CPEscapeHTML(NSString *text)
{
    NSMutableString *result = [NSMutableString stringWithString:(text != nil ? text : @"")];
    [result replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, [result length])];
    return result;
}

@interface CPBrowserWindowController (Private)
- (NSButton *)addButtonWithImage:(NSImage *)image frame:(NSRect)frame action:(SEL)action toolTip:(NSString *)toolTip;
- (NSBox *)addSeparatorWithFrame:(NSRect)frame autoresizingMask:(unsigned int)mask;
- (void)buildInterface;
- (void)updateNavigationButtons;
- (void)setLoading:(BOOL)flag;
- (void)setStatusText:(NSString *)text;
- (void)setAddressFromURL:(NSURL *)url;
- (BOOL)isEditingAddress;
- (NSURL *)URLFromUserInput:(NSString *)input;
- (void)showErrorPage:(NSError *)error forFrame:(WebFrame *)frame;
- (void)writeDebugSnapshot;
@end

@implementation CPBrowserWindowController (Private)

- (NSButton *)addButtonWithImage:(NSImage *)image frame:(NSRect)frame action:(SEL)action toolTip:(NSString *)toolTip
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setBezelStyle:NSTexturedSquareBezelStyle];
    [button setImage:image];
    [button setImagePosition:NSImageOnly];
    [button setTarget:self];
    [button setAction:action];
    [button setToolTip:toolTip];
    [button setAutoresizingMask:NSViewMinYMargin];
    [[[self window] contentView] addSubview:button];
    [button release];
    return button;
}

- (NSBox *)addSeparatorWithFrame:(NSRect)frame autoresizingMask:(unsigned int)mask
{
    NSBox *box = [[NSBox alloc] initWithFrame:frame];
    [box setBoxType:NSBoxSeparator];
    [box setAutoresizingMask:mask];
    [[[self window] contentView] addSubview:box];
    [box release];
    return box;
}

- (void)buildInterface
{
    NSView *content = [[self window] contentView];
    NSRect bounds = [content bounds];
    float width = NSWidth(bounds);
    float height = NSHeight(bounds);
    NSFont *smallFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];

    backButton = [self addButtonWithImage:[CPIcons backImage]
                                    frame:NSMakeRect(8.0f, height - 29.0f, 32.0f, 24.0f)
                                   action:@selector(goBack:)
                                  toolTip:@"Back"];
    forwardButton = [self addButtonWithImage:[CPIcons forwardImage]
                                       frame:NSMakeRect(41.0f, height - 29.0f, 32.0f, 24.0f)
                                      action:@selector(goForward:)
                                     toolTip:@"Forward"];
    reloadButton = [self addButtonWithImage:[CPIcons reloadImage]
                                      frame:NSMakeRect(80.0f, height - 29.0f, 32.0f, 24.0f)
                                     action:@selector(reloadOrStop:)
                                    toolTip:@"Reload"];

    addressField = [[NSTextField alloc] initWithFrame:NSMakeRect(120.0f, height - 28.0f, width - 130.0f, 22.0f)];
    [addressField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [[addressField cell] setScrollable:YES];
    [[addressField cell] setSendsActionOnEndEditing:NO];
    [addressField setTarget:self];
    [addressField setAction:@selector(addressEntered:)];
    [content addSubview:addressField];
    [addressField release];

    [self addSeparatorWithFrame:NSMakeRect(0.0f, height - CPBarHeight - 1.0f, width, 1.0f)
               autoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];

    webView = [[WebView alloc] initWithFrame:NSMakeRect(0.0f, CPStatusHeight + 1.0f, width,
                                                        height - CPBarHeight - CPStatusHeight - 2.0f)
                                   frameName:nil
                                   groupName:@"CaptainPolliwog"];
    [webView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [webView setFrameLoadDelegate:self];
    [webView setUIDelegate:self];
    [webView setApplicationNameForUserAgent:[CPAppDelegate userAgentApplicationName]];
    [content addSubview:webView];

    [self addSeparatorWithFrame:NSMakeRect(0.0f, CPStatusHeight, width, 1.0f)
               autoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];

    statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(6.0f, 3.0f, width - 150.0f, 14.0f)];
    [statusField setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [statusField setEditable:NO];
    [statusField setSelectable:NO];
    [statusField setBezeled:NO];
    [statusField setDrawsBackground:NO];
    [statusField setFont:smallFont];
    [[statusField cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [statusField setStringValue:@""];
    [content addSubview:statusField];
    [statusField release];

    progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(width - 136.0f, 4.0f, 128.0f, 12.0f)];
    [progressBar setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
    [progressBar setStyle:NSProgressIndicatorBarStyle];
    [progressBar setControlSize:NSSmallControlSize];
    [progressBar setIndeterminate:NO];
    [progressBar setMinValue:0.0];
    [progressBar setMaxValue:1.0];
    [progressBar setHidden:YES];
    [content addSubview:progressBar];
    [progressBar release];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(progressChanged:)
                                                 name:WebViewProgressStartedNotification object:webView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(progressChanged:)
                                                 name:WebViewProgressEstimateChangedNotification object:webView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(progressChanged:)
                                                 name:WebViewProgressFinishedNotification object:webView];

    [self updateNavigationButtons];
}

- (void)updateNavigationButtons
{
    [backButton setEnabled:[webView canGoBack]];
    [forwardButton setEnabled:[webView canGoForward]];
}

- (void)setLoading:(BOOL)flag
{
    if (loading == flag)
        return;
    loading = flag;
    [reloadButton setImage:(flag ? [CPIcons stopImage] : [CPIcons reloadImage])];
    [reloadButton setToolTip:(flag ? @"Stop" : @"Reload")];
}

// Mouse-over fires constantly; only redraw the status bar when the text changes.
- (void)setStatusText:(NSString *)text
{
    if (text == nil)
        text = @"";
    if (![[statusField stringValue] isEqualToString:text])
        [statusField setStringValue:text];
}

- (void)setAddressFromURL:(NSURL *)url
{
    if ([self isEditingAddress])
        return;
    if (url == nil || [url isEqual:[CPAppDelegate startPageURL]])
        [addressField setStringValue:@""];
    else
        [addressField setStringValue:[url absoluteString]];
}

- (BOOL)isEditingAddress
{
    id responder = [[self window] firstResponder];
    return [responder isKindOfClass:[NSTextView class]] &&
           [(NSTextView *)responder delegate] == (id)addressField;
}

- (NSURL *)URLFromUserInput:(NSString *)input
{
    NSString *text = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = nil;

    if ([text length] == 0)
        return nil;

    if ([text rangeOfString:@" "].location == NSNotFound) {
        if ([text rangeOfString:@"://"].location != NSNotFound ||
            [text hasPrefix:@"about:"] || [text hasPrefix:@"file:"] || [text hasPrefix:@"data:"])
            url = [NSURL URLWithString:text];
        else if ([text rangeOfString:@"."].location != NSNotFound || [text hasPrefix:@"localhost"])
            url = [NSURL URLWithString:[@"http://" stringByAppendingString:text]];
        if (url != nil)
            return url;
    }

    NSString *query = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)text, NULL,
                                                                          CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                          kCFStringEncodingUTF8);
    url = [NSURL URLWithString:[NSString stringWithFormat:CPSearchURLFormat, query]];
    [query release];
    return url;
}

- (void)showErrorPage:(NSError *)error forFrame:(WebFrame *)frame
{
    NSURL *failingURL = [[[frame provisionalDataSource] request] URL];
    NSString *hint = @"";

    // Tiger's built-in SSL predates TLS 1.2, which nearly every site now requires.
    if ([[error domain] isEqualToString:NSURLErrorDomain] &&
        [error code] <= -1200 && [error code] >= -1206)
        hint = @"<p class=\"hint\">This Mac's built-in encryption is too old for this site. "
               @"Modern encryption is coming in the next Captain Polliwog build.</p>";

    NSString *html = [NSString stringWithFormat:
        @"<html><head><title>Can't open page</title><style>"
        @"body{font:13px 'Lucida Grande',sans-serif;background:#f4f7f4;color:#223;margin:0}"
        @"div{max-width:520px;margin:80px auto;padding:24px 28px;background:#fff;border:1px solid #cdd}"
        @"h1{font-size:18px;margin:0 0 12px}code{word-wrap:break-word;color:#555}.hint{color:#735}"
        @"</style></head><body><div><h1>Captain Polliwog can't open this page</h1>"
        @"<p>%@</p><p><code>%@</code></p>%@</div></body></html>",
        CPEscapeHTML([error localizedDescription]),
        CPEscapeHTML([failingURL absoluteString]),
        hint];

    [frame loadAlternateHTMLString:html baseURL:nil forUnreachableURL:failingURL];
}

- (void)writeDebugSnapshot
{
    // When the scripts are photographing Preferences, stay out of the way.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugShowPreferences"])
        return;
    CPWriteWindowSnapshot([self window]);
}

@end

@implementation CPBrowserWindowController

- (id)init
{
    NSRect visible = [[NSScreen mainScreen] visibleFrame];
    NSRect contentRect = NSMakeRect(0.0f, 0.0f,
                                    MIN(1000.0f, NSWidth(visible) - 40.0f),
                                    MIN(760.0f, NSHeight(visible) - 60.0f));
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                                                              NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [window setReleasedWhenClosed:NO];
    [window setMinSize:NSMakeSize(420.0f, 300.0f)];
    [window setTitle:@"Captain Polliwog"];
    [window center];

    self = [super initWithWindow:window];
    [window release];
    if (self == nil)
        return nil;

    [window setDelegate:self];
    [self buildInterface];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [loadStarted release];
    [webView release];
    [super dealloc];
}

- (WebView *)webView
{
    return webView;
}

- (void)loadURL:(NSURL *)url
{
    if (url == nil)
        return;
    // Leave the address field so it can show where we are going.
    if ([self isEditingAddress])
        [[self window] makeFirstResponder:webView];
    [self setAddressFromURL:url];
    [[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)loadAddressString:(NSString *)address
{
    [self loadURL:[self URLFromUserInput:address]];
}

#pragma mark Actions

- (IBAction)goBack:(id)sender
{
    [webView goBack];
}

- (IBAction)goForward:(id)sender
{
    [webView goForward];
}

- (IBAction)goHome:(id)sender
{
    [self loadURL:[CPAppDelegate startPageURL]];
}

- (IBAction)reload:(id)sender
{
    [webView reload:sender];
}

- (IBAction)stopLoading:(id)sender
{
    [webView stopLoading:sender];
}

- (IBAction)reloadOrStop:(id)sender
{
    if (loading)
        [self stopLoading:sender];
    else
        [self reload:sender];
}

- (IBAction)openLocation:(id)sender
{
    [[self window] makeFirstResponder:addressField];
    [addressField selectText:sender];
}

- (IBAction)addressEntered:(id)sender
{
    NSString *address = [addressField stringValue];
    if ([[address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0)
        return;
    [[self window] makeFirstResponder:webView];
    [self loadAddressString:address];
}

- (IBAction)makeTextLarger:(id)sender
{
    [webView makeTextLarger:sender];
}

- (IBAction)makeTextSmaller:(id)sender
{
    [webView makeTextSmaller:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL action = [item action];
    if (action == @selector(goBack:))
        return [webView canGoBack];
    if (action == @selector(goForward:))
        return [webView canGoForward];
    if (action == @selector(stopLoading:))
        return loading;
    if (action == @selector(makeTextLarger:))
        return [webView canMakeTextLarger];
    if (action == @selector(makeTextSmaller:))
        return [webView canMakeTextSmaller];
    return YES;
}

#pragma mark Progress

- (void)progressChanged:(NSNotification *)notification
{
    if ([[notification name] isEqualToString:WebViewProgressFinishedNotification]) {
        [progressBar setHidden:YES];
        [progressBar setDoubleValue:0.0];
    } else {
        [progressBar setHidden:NO];
        [progressBar setDoubleValue:[webView estimatedProgress]];
    }
}

#pragma mark WebFrameLoadDelegate

- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
    if (frame != [sender mainFrame])
        return;
    [loadStarted release];
    loadStarted = [[NSDate date] retain];
    [self setAddressFromURL:[[[frame provisionalDataSource] request] URL]];
    [self setLoading:YES];
}

- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
    NSURL *unreachableURL;

    if (frame != [sender mainFrame])
        return;
    unreachableURL = [[frame dataSource] unreachableURL];
    [self setAddressFromURL:(unreachableURL != nil ? unreachableURL : [[[frame dataSource] request] URL])];
    [[self window] setTitle:@"Captain Polliwog"];
    [self setStatusText:nil];
    [self updateNavigationButtons];
}

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    if (frame == [sender mainFrame] && [title length] > 0)
        [[self window] setTitle:title];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame != [sender mainFrame])
        return;
    [self setLoading:NO];
    [self updateNavigationButtons];
    if (CPDebugSnapshotPath() != nil && loadStarted != nil)
        NSLog(@"Captain Polliwog: page-load %.1fs %@",
              -[loadStarted timeIntervalSinceNow], [[[frame dataSource] request] URL]);

    if (CPDebugSnapshotPath() != nil &&
        ![[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugShowPreferences"]) {
        NSLog(@"Captain Polliwog: finished %@", [[[frame dataSource] request] URL]);
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(writeDebugSnapshot) object:nil];
        [self performSelector:@selector(writeDebugSnapshot) withObject:nil afterDelay:2.0];
    }
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (frame != [sender mainFrame])
        return;
    [self setLoading:NO];
    [self updateNavigationButtons];

    if ([[error domain] isEqualToString:NSURLErrorDomain] && [error code] == NSURLErrorCancelled)
        return;
    if ([[error domain] isEqualToString:WebKitErrorDomain] &&
        [error code] == WebKitErrorFrameLoadInterruptedByPolicyChange)
        return;
    NSLog(@"Captain Polliwog: failed %@ (%@ %d: %@)", [[[frame provisionalDataSource] request] URL],
          [error domain], [error code], [error localizedDescription]);
    [self showErrorPage:error forFrame:frame];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (frame != [sender mainFrame])
        return;
    [self setLoading:NO];
    [self updateNavigationButtons];
}

#pragma mark WebUIDelegate

- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
    CPBrowserWindowController *controller = [(CPAppDelegate *)[NSApp delegate] openBrowserWindow];
    if (request != nil)
        [[[controller webView] mainFrame] loadRequest:request];
    return [controller webView];
}

- (void)webViewShow:(WebView *)sender
{
    [self showWindow:self];
}

- (void)webViewClose:(WebView *)sender
{
    [[self window] close];
}

- (void)webView:(WebView *)sender mouseDidMoveOverElement:(NSDictionary *)elementInformation
  modifierFlags:(unsigned int)modifierFlags
{
    NSURL *link = [elementInformation objectForKey:WebElementLinkURLKey];
    [self setStatusText:[link absoluteString]];
}

- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message
{
    NSRunInformationalAlertPanel([[self window] title], @"%@", @"OK", nil, nil, message);
}

- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message
{
    return NSRunAlertPanel([[self window] title], @"%@", @"OK", @"Cancel", nil, message) == NSAlertDefaultReturn;
}

- (void)webView:(WebView *)sender runOpenPanelForFileButtonWithResultListener:(id<WebOpenPanelResultListener>)resultListener
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    if ([panel runModalForTypes:nil] == NSOKButton)
        [resultListener chooseFilename:[panel filename]];
    else
        [resultListener cancel];
}

#pragma mark NSWindow delegate

- (void)windowWillClose:(NSNotification *)notification
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [webView stopLoading:nil];
    [webView setFrameLoadDelegate:nil];
    [webView setUIDelegate:nil];
    // -[WebView close] arrived with WebKit 3; Tiger's original WebKit lacks it.
    if ([webView respondsToSelector:@selector(close)])
        [webView performSelector:@selector(close)];
    [(CPAppDelegate *)[NSApp delegate] browserWindowWillClose:self];
}

@end
