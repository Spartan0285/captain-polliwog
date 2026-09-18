/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPTab.h"
#import "CPAppDelegate.h"
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>

static NSString *CPEscapeHTML(NSString *text)
{
    NSMutableString *result = [NSMutableString stringWithString:(text != nil ? text : @"")];
    [result replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, [result length])];
    return result;
}

@interface CPTab (Private)
- (void)createWebView;
- (void)destroyWebView;
- (void)setURL:(NSURL *)aURL;
- (void)setTitle:(NSString *)aTitle;
- (void)setLoading:(BOOL)flag;
- (void)changed;
- (void)showErrorPage:(NSError *)error forFrame:(WebFrame *)frame;
@end

@implementation CPTab (Private)

- (void)createWebView
{
    webView = [[WebView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 400.0f, 300.0f)
                                   frameName:nil
                                   groupName:@"CaptainPolliwog"];
    [webView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [webView setFrameLoadDelegate:self];
    [webView setUIDelegate:self];
    [webView setPolicyDelegate:self];
    [webView setApplicationNameForUserAgent:[CPAppDelegate userAgentApplicationName]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(progressChanged:)
                                                 name:WebViewProgressStartedNotification object:webView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(progressChanged:)
                                                 name:WebViewProgressEstimateChangedNotification object:webView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(progressChanged:)
                                                 name:WebViewProgressFinishedNotification object:webView];
}

- (void)destroyWebView
{
    if (webView == nil)
        return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:webView];
    [webView stopLoading:nil];
    [webView setFrameLoadDelegate:nil];
    [webView setUIDelegate:nil];
    [webView setPolicyDelegate:nil];
    [webView removeFromSuperview];
    // -[WebView close] arrived with WebKit 3; Tiger's original WebKit lacks it.
    if ([webView respondsToSelector:@selector(close)])
        [webView performSelector:@selector(close)];
    [webView release];
    webView = nil;
}

- (void)setURL:(NSURL *)aURL
{
    if (aURL == URL)
        return;
    [URL release];
    URL = [aURL retain];
}

- (void)setTitle:(NSString *)aTitle
{
    if (aTitle == title)
        return;
    [title release];
    title = [aTitle copy];
}

- (void)setLoading:(BOOL)flag
{
    loading = flag;
    if (!flag)
        progress = 0.0;
}

- (void)changed
{
    if ([owner respondsToSelector:@selector(tabDidChange:)])
        [owner tabDidChange:self];
}

- (void)showErrorPage:(NSError *)error forFrame:(WebFrame *)frame
{
    NSURL *failingURL = [[[frame provisionalDataSource] request] URL];
    NSString *hint = @"";
    NSString *html;
    int code = [error code];

    if ([[error domain] isEqualToString:NSURLErrorDomain]) {
        if (code == NSURLErrorServerCertificateUntrusted || code == -1202)
            hint = @"<p class=\"hint\">The site's security certificate could not be verified, "
                   @"so Captain Polliwog did not connect. Check that this Mac's date is right.</p>";
        else if (code == NSURLErrorSecureConnectionFailed)
            hint = @"<p class=\"hint\">A secure connection could not be set up with this site.</p>";
        else if (code == NSURLErrorTimedOut)
            hint = @"<p class=\"hint\">The site took too long to answer. Try reloading.</p>";
    }

    html = [NSString stringWithFormat:
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

@end

@implementation CPTab

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self == nil)
        return nil;
    owner = anOwner;
    lastSelected = [[NSDate date] retain];
    return self;
}

- (void)dealloc
{
    [self destroyWebView];
    [URL release];
    [title release];
    [lastSelected release];
    [loadStarted release];
    [super dealloc];
}

- (WebView *)webView
{
    if (webView == nil) {
        [self createWebView];
        // Coming back from being discarded: reload what was showing.
        if (URL != nil)
            [[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:URL]];
    }
    return webView;
}

- (BOOL)isDiscarded
{
    return (webView == nil);
}

- (void)discard
{
    if (webView == nil)
        return;
    savedScrollOffset = [[webView stringByEvaluatingJavaScriptFromString:@"window.pageYOffset"] floatValue];
    [self destroyWebView];
    [self setLoading:NO];
    if (CPDebugSnapshotPath() != nil)
        NSLog(@"Captain Polliwog: discarded tab %@", URL);
    [self changed];
}

- (void)close
{
    owner = nil;
    [self destroyWebView];
}

- (void)loadURL:(NSURL *)aURL
{
    if (aURL == nil)
        return;
    [self loadRequest:[NSURLRequest requestWithURL:aURL]];
}

- (void)loadRequest:(NSURLRequest *)request
{
    savedScrollOffset = 0.0f;
    [self setURL:[request URL]];
    if (webView == nil)
        [self createWebView];
    [[webView mainFrame] loadRequest:request];
    [self changed];
}

- (NSURL *)URL
{
    return URL;
}

- (NSString *)title
{
    return title;
}

- (NSString *)displayTitle
{
    if ([title length] > 0)
        return title;
    if (loading)
        return @"Loading...";
    if ([[URL host] length] > 0)
        return [URL host];
    return @"Untitled";
}

- (BOOL)isLoading
{
    return loading;
}

- (double)progress
{
    return progress;
}

- (BOOL)canGoBack
{
    return (webView != nil && [webView canGoBack]);
}

- (BOOL)canGoForward
{
    return (webView != nil && [webView canGoForward]);
}

- (NSDate *)lastSelected
{
    return lastSelected;
}

- (void)noteSelected
{
    [lastSelected release];
    lastSelected = [[NSDate date] retain];
}

- (void)goBack
{
    [webView goBack];
}

- (void)goForward
{
    [webView goForward];
}

- (void)reload
{
    if (webView == nil) {
        [self webView];
        return;
    }
    [webView reload:nil];
}

- (void)stopLoading
{
    [webView stopLoading:nil];
}

#pragma mark Progress

- (void)progressChanged:(NSNotification *)notification
{
    if ([[notification name] isEqualToString:WebViewProgressFinishedNotification])
        progress = 0.0;
    else
        progress = [webView estimatedProgress];
    [self changed];
}

#pragma mark WebFrameLoadDelegate

- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
    if (frame != [sender mainFrame])
        return;
    [loadStarted release];
    loadStarted = [[NSDate date] retain];
    [self setURL:[[[frame provisionalDataSource] request] URL]];
    [self setLoading:YES];
    [self changed];
}

- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
    NSURL *unreachableURL;

    if (frame != [sender mainFrame])
        return;
    unreachableURL = [[frame dataSource] unreachableURL];
    [self setURL:(unreachableURL != nil ? unreachableURL : [[[frame dataSource] request] URL])];
    [self setTitle:nil];
    [self changed];
}

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)aTitle forFrame:(WebFrame *)frame
{
    if (frame != [sender mainFrame])
        return;
    [self setTitle:aTitle];
    [self changed];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame != [sender mainFrame])
        return;
    [self setLoading:NO];

    // Put a page that was discarded back where the reader left it.
    if (savedScrollOffset > 0.0f) {
        [sender stringByEvaluatingJavaScriptFromString:
         [NSString stringWithFormat:@"window.scrollTo(0, %.0f)", savedScrollOffset]];
        savedScrollOffset = 0.0f;
    }

    if (CPDebugSnapshotPath() != nil && loadStarted != nil)
        NSLog(@"Captain Polliwog: page-load %.1fs %@",
              -[loadStarted timeIntervalSinceNow], [[[frame dataSource] request] URL]);
    [self changed];
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (frame != [sender mainFrame])
        return;
    [self setLoading:NO];
    [self changed];

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
    [self changed];
}

#pragma mark WebPolicyDelegate

// Command-click opens a link in a background tab, as in Safari.
- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)action
        request:(NSURLRequest *)request
          frame:(WebFrame *)frame
decisionListener:(id<WebPolicyDecisionListener>)listener
{
    int type = [[action objectForKey:WebActionNavigationTypeKey] intValue];
    unsigned int modifiers = [[action objectForKey:WebActionModifierFlagsKey] unsignedIntValue];

    if (type == WebNavigationTypeLinkClicked && (modifiers & NSCommandKeyMask) &&
        [owner respondsToSelector:@selector(tab:openTabWithRequest:inBackground:)]) {
        [owner tab:self openTabWithRequest:request inBackground:YES];
        [listener ignore];
        return;
    }
    [listener use];
}

// Links that ask for a new window (target="_blank") open in a new tab instead.
- (void)webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)action
        request:(NSURLRequest *)request
   newFrameName:(NSString *)frameName
decisionListener:(id<WebPolicyDecisionListener>)listener
{
    unsigned int modifiers = [[action objectForKey:WebActionModifierFlagsKey] unsignedIntValue];

    if ([owner respondsToSelector:@selector(tab:openTabWithRequest:inBackground:)]) {
        [owner tab:self openTabWithRequest:request inBackground:((modifiers & NSCommandKeyMask) != 0)];
        [listener ignore];
        return;
    }
    [listener use];
}

#pragma mark WebUIDelegate

// Script-opened windows (window.open) become tabs too.
- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
    CPTab *tab;

    if (![owner respondsToSelector:@selector(tab:openTabWithRequest:inBackground:)])
        return nil;
    tab = [owner tab:self openTabWithRequest:request inBackground:NO];
    return [tab webView];
}

- (void)webViewClose:(WebView *)sender
{
    if ([owner respondsToSelector:@selector(tabWantsToClose:)])
        [owner tabWantsToClose:self];
}

- (void)webView:(WebView *)sender mouseDidMoveOverElement:(NSDictionary *)elementInformation
  modifierFlags:(unsigned int)modifierFlags
{
    NSURL *link = [elementInformation objectForKey:WebElementLinkURLKey];
    if ([owner respondsToSelector:@selector(tab:showStatusText:)])
        [owner tab:self showStatusText:[link absoluteString]];
}

- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message
{
    NSRunInformationalAlertPanel([self displayTitle], @"%@", @"OK", nil, nil, message);
}

- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message
{
    return NSRunAlertPanel([self displayTitle], @"%@", @"OK", @"Cancel", nil, message) == NSAlertDefaultReturn;
}

- (void)webView:(WebView *)sender runOpenPanelForFileButtonWithResultListener:(id<WebOpenPanelResultListener>)resultListener
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    if ([panel runModalForTypes:nil] == NSOKButton)
        [resultListener chooseFilename:[panel filename]];
    else
        [resultListener cancel];
}

@end
