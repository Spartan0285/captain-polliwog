/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPTab.h"
#import "CPAppDelegate.h"
#import "CPDebugSnapshot.h"
#import "CPDownloadsController.h"
#import "CPReader.h"
#import "CPAutoFill.h"
#import "CPSiteModes.h"
#import "CPScriptWatchdog.h"
#import "CPUserScripts.h"
#import <WebKit/WebKit.h>

// How long a loading page may go without progress before the debug log
// lists what it is still waiting for.
#define CPStallReportDelay 20.0

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
- (BOOL)applySiteModeForURL:(NSURL *)aURL;
@end

@implementation CPTab (Private)

- (void)createWebView
{
    [CPUserScripts installForGroup:@"CaptainPolliwog"];
    webView = [[WebView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 400.0f, 300.0f)
                                   frameName:nil
                                   groupName:@"CaptainPolliwog"];
    [webView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [webView setFrameLoadDelegate:self];
    [webView setUIDelegate:self];
    [webView setPolicyDelegate:self];
    [webView setApplicationNameForUserAgent:[CPAppDelegate userAgentApplicationName]];
    if (CPDebugLogging()) {
        [webView setResourceLoadDelegate:self];
        if (pendingResources == nil)
            pendingResources = [[NSMutableDictionary alloc] init];
    }
    [CPScriptWatchdog installForWebView:webView];

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
    [webView setResourceLoadDelegate:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reportStall) object:nil];
    [pendingResources removeAllObjects];
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

// Gives the WebView the identity the page's site version calls for: the
// browser's own, or a phone's. Returns YES if it changed.
- (BOOL)applySiteModeForURL:(NSURL *)aURL
{
    NSString *wanted;
    NSString *current;

    if (webView == nil || ![CPSiteModes appliesToURL:aURL])
        return NO;
    wanted = [CPSiteModes userAgentForMode:[CPSiteModes modeForURL:aURL]];
    current = [webView customUserAgent];
    if ([current length] == 0)
        current = nil;
    if (wanted == current || [wanted isEqualToString:current])
        return NO;
    [webView setCustomUserAgent:wanted];
    return YES;
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
    [reader cancel];
    [reader release];
    [self destroyWebView];
    [URL release];
    [title release];
    [lastSelected release];
    [loadStarted release];
    [pendingResources release];
    [super dealloc];
}

- (WebView *)webView
{
    if (webView == nil) {
        [self createWebView];
        // Coming back from being discarded: reload what was showing.
        if (URL != nil) {
            [self applySiteModeForURL:URL];
            [[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:URL]];
        }
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
    // Coming back reloads the page itself, not its reader version.
    showingReader = NO;
    [self destroyWebView];
    [self setLoading:NO];
    if (CPDebugLogging())
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
    [self applySiteModeForURL:[request URL]];
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

- (void)reloadForSiteMode
{
    NSURL *current = URL;

    if (current == nil || ![CPSiteModes appliesToURL:current])
        return;
    if (webView == nil)
        [self createWebView];
    // A fresh load rather than -reload:, which would resend the request
    // with the identity it was first made with.
    [self applySiteModeForURL:current];
    [[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:current]];
}

#pragma mark Progress

- (BOOL)isShowingReader
{
    return showingReader || reader != nil;
}

- (BOOL)canShowReader
{
    NSString *scheme = [[URL scheme] lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

- (void)showReaderHTML:(NSString *)html forURL:(NSURL *)aURL
{
    if (html == nil)
        html = [NSString stringWithFormat:
                @"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Reader</title></head>"
                @"<body style=\"font: 13px 'Lucida Grande', Helvetica, sans-serif; margin: 3em auto; max-width: 30em; color: #444\">"
                @"<p><b>Reader found no article on this page.</b></p>"
                @"<p>Some pages build their text with scripts, which Reader leaves out. "
                @"<a href=\"%@\">Show the original page</a>.</p></body></html>",
                CPEscapeHTML([aURL absoluteString])];
    readerLoadPending = YES;
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: reader page for %@ (%u characters)", aURL, [html length]);
    [[[self webView] mainFrame] loadHTMLString:html baseURL:aURL];
}

- (void)toggleReader
{
    NSString *html;

    if ([self isShowingReader]) {
        BOOL wasShowing = showingReader;
        [reader cancel];
        [reader release];
        reader = nil;
        showingReader = NO;
        if (wasShowing && URL != nil)
            [self loadURL:URL];
        [self changed];
        return;
    }
    if (![self canShowReader])
        return;

    // A page that has finished loading is read as it stands, scripts' work
    // included, and at once.
    if (webView != nil && !loading) {
        html = [CPReader readerHTMLForDocument:[[webView mainFrame] DOMDocument] URL:URL];
        if (html != nil) {
            [self showReaderHTML:html forURL:URL];
            return;
        }
    }

    // Otherwise stop the page and fetch its HTML alone.
    [[self webView] stopLoading:nil];
    reader = [[CPReader alloc] initWithDelegate:self];
    [(CPReader *)reader loadURL:URL userAgent:[webView customUserAgent]];
    [self setLoading:YES];
    [self changed];
}

- (void)reader:(CPReader *)aReader didMakeHTML:(NSString *)html forURL:(NSURL *)aURL
{
    if (aReader != reader)
        return;
    [reader autorelease];
    reader = nil;
    [self setLoading:NO];
    [self showReaderHTML:html forURL:aURL];
    [self changed];
}

- (void)progressChanged:(NSNotification *)notification
{
    BOOL finished = [[notification name] isEqualToString:WebViewProgressFinishedNotification];

    if (finished)
        progress = 0.0;
    else
        progress = [webView estimatedProgress];
    if (pendingResources != nil) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reportStall) object:nil];
        if (!finished)
            [self performSelector:@selector(reportStall) withObject:nil afterDelay:CPStallReportDelay];
    }
    [self changed];
}

// Debug log: a page has made no progress for a while; say what it waits on.
- (void)reportStall
{
    NSArray *waiting;

    if (!loading)
        return;
    waiting = [pendingResources allValues];
    NSLog(@"Captain Polliwog: stalled %@ (%.0fs since progress), waiting for %u: %@", URL,
          CPStallReportDelay, [waiting count],
          [[waiting subarrayWithRange:NSMakeRange(0, MIN([waiting count], 8U))] componentsJoinedByString:@" "]);
}

#pragma mark WebResourceLoadDelegate (debug logging only)

- (id)webView:(WebView *)sender identifierForInitialRequest:(NSURLRequest *)request
fromDataSource:(WebDataSource *)dataSource
{
    NSNumber *identifier = [NSNumber numberWithUnsignedInt:++nextResourceID];
    NSString *address = [[request URL] absoluteString];
    [pendingResources setObject:(address != nil ? address : @"(no URL)") forKey:identifier];
    return identifier;
}

- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource
{
    NSString *address = [[request URL] absoluteString];
    if (address != nil && [pendingResources objectForKey:identifier] != nil)
        [pendingResources setObject:address forKey:identifier];
    return request;
}

- (void)webView:(WebView *)sender resource:(id)identifier didFinishLoadingFromDataSource:(WebDataSource *)dataSource
{
    [pendingResources removeObjectForKey:identifier];
}

- (void)webView:(WebView *)sender resource:(id)identifier didFailLoadingWithError:(NSError *)error
 fromDataSource:(WebDataSource *)dataSource
{
    NSString *address = [pendingResources objectForKey:identifier];
    if (address != nil && [error code] != NSURLErrorCancelled)
        NSLog(@"Captain Polliwog: resource failed %@ (%@ %d)", address, [error domain], [error code]);
    [pendingResources removeObjectForKey:identifier];
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
    // Anything that replaces the reader page (a link, Back) leaves Reader.
    showingReader = readerLoadPending;
    readerLoadPending = NO;
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: committed %@%@", [[[frame dataSource] request] URL], showingReader ? @" (reader)" : @"");
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

    if (CPDebugLogging() && loadStarted != nil)
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

    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: provisional load failed (%@ %d)", [error domain], [error code]);
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

    // Leaving a page where a password was typed: offer to save it.
    if (frame == [sender mainFrame] && !readerLoadPending && type != WebNavigationTypeBackForward)
        [CPAutoFill captureLoginInTab:self];

    if (type == WebNavigationTypeLinkClicked && (modifiers & NSCommandKeyMask) &&
        [owner respondsToSelector:@selector(tab:openTabWithRequest:inBackground:)]) {
        [owner tab:self openTabWithRequest:request inBackground:YES];
        [listener ignore];
        return;
    }

    // Moving to a site with a different site version: switch identity. If
    // WebKit has already written the old one into this request, load it
    // again so the site sees the new one (except when going back or forward,
    // where a fresh load would disturb the history). The reader page is
    // local HTML, never reloaded.
    if (frame == [sender mainFrame] && !readerLoadPending && [self applySiteModeForURL:[request URL]] &&
        type != WebNavigationTypeBackForward) {
        NSString *sent = [request valueForHTTPHeaderField:@"User-Agent"];
        if (sent != nil && ![sent isEqualToString:[sender userAgentForURL:[request URL]]]) {
            NSMutableURLRequest *again = [[request mutableCopy] autorelease];
            [again setValue:nil forHTTPHeaderField:@"User-Agent"];
            [listener ignore];
            [frame loadRequest:again];
            return;
        }
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

// Anything WebKit cannot display, or that the server marks as an attachment,
// is saved through the downloads window instead.
- (void)webView:(WebView *)sender decidePolicyForMIMEType:(NSString *)type
        request:(NSURLRequest *)request
          frame:(WebFrame *)frame
decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSURLResponse *response = [[frame provisionalDataSource] response];
    NSString *disposition = nil;
    NSDictionary *headers;
    NSEnumerator *names;
    NSString *name;

    if ([response respondsToSelector:@selector(allHeaderFields)]) {
        headers = [(NSHTTPURLResponse *)response allHeaderFields];
        names = [headers keyEnumerator];
        while ((name = [names nextObject]) != nil) {
            if ([name caseInsensitiveCompare:@"Content-Disposition"] == NSOrderedSame)
                disposition = [headers objectForKey:name];
        }
    }
    if (!(disposition != nil && [[disposition lowercaseString] hasPrefix:@"attachment"]) &&
        [WebView canShowMIMEType:type]) {
        [listener use];
        return;
    }

    [listener ignore];
    [[CPDownloadsController sharedController] startDownloadWithRequest:request
                                                     suggestedFilename:[response suggestedFilename]];
    // A tab opened only to fetch this file has nothing to show, so it goes;
    // deferred, since its WebView is in the middle of this callback.
    if ([[sender backForwardList] currentItem] == nil && [owner respondsToSelector:@selector(tabWantsToClose:)])
        [owner performSelector:@selector(tabWantsToClose:) withObject:self afterDelay:0.0];
}

#pragma mark WebUIDelegate

// WebKit's own "new window" and "download" items bypass the tabs and the
// bundled network stack, so they are swapped for ones that use both.
- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element
    defaultMenuItems:(NSArray *)defaultMenuItems
{
    NSMutableArray *items = [NSMutableArray array];
    NSURL *link = [element objectForKey:WebElementLinkURLKey];
    NSURL *image = [element objectForKey:WebElementImageURLKey];
    unsigned index;

    for (index = 0; index < [defaultMenuItems count]; index++) {
        NSMenuItem *item = [defaultMenuItems objectAtIndex:index];
        NSString *itemTitle = nil;
        SEL action = NULL;
        NSURL *target = nil;

        switch ([item tag]) {
        case WebMenuItemTagOpenLinkInNewWindow:
            itemTitle = @"Open Link in New Tab"; action = @selector(openInNewTab:); target = link;
            break;
        case WebMenuItemTagDownloadLinkToDisk:
            itemTitle = @"Download Linked File"; action = @selector(downloadURL:); target = link;
            break;
        case WebMenuItemTagOpenImageInNewWindow:
            itemTitle = @"Open Image in New Tab"; action = @selector(openInNewTab:); target = image;
            break;
        case WebMenuItemTagDownloadImageToDisk:
            itemTitle = @"Download Image"; action = @selector(downloadURL:); target = image;
            break;
        default:
            break;
        }
        if (action != NULL && target != nil) {
            NSMenuItem *replacement = [[[NSMenuItem alloc] initWithTitle:itemTitle action:action keyEquivalent:@""] autorelease];
            [replacement setTarget:self];
            [replacement setRepresentedObject:target];
            [items addObject:replacement];
        } else {
            [items addObject:item];
        }
    }
    return items;
}

- (void)openInNewTab:(id)sender
{
    if ([owner respondsToSelector:@selector(tab:openTabWithRequest:inBackground:)])
        [owner tab:self openTabWithRequest:[NSURLRequest requestWithURL:[sender representedObject]]
      inBackground:YES];
}

- (void)downloadURL:(id)sender
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[sender representedObject]];

    // Some servers only hand files to visitors who came from their own pages.
    if (URL != nil && ![URL isFileURL])
        [request setValue:[URL absoluteString] forHTTPHeaderField:@"Referer"];
    [[CPDownloadsController sharedController] startDownloadWithRequest:request
                                                     suggestedFilename:[[[sender representedObject] path] lastPathComponent]];
}

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

// Page JavaScript errors and console output, for the debug log. Not in the
// public delegate protocol, but WebKit calls it on Tiger and later.
- (void)webView:(WebView *)sender addMessageToConsole:(NSDictionary *)message
{
    if (!CPDebugLogging())
        return;
    NSLog(@"Captain Polliwog: console %@ line %@: %@", [message objectForKey:@"sourceURL"],
          [message objectForKey:@"lineNumber"], [message objectForKey:@"message"]);
}

- (void)webView:(WebView *)sender addMessageToConsole:(NSDictionary *)message withSource:(NSString *)source
{
    [self webView:sender addMessageToConsole:message];
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
