/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class WebView;
@class CPTab;

// What a tab tells the window it lives in. The window implements these.
@class WebPreferences;

@interface NSObject (CPTabOwner)
- (void)tabDidChange:(CPTab *)tab;
- (void)tab:(CPTab *)tab showStatusText:(NSString *)text;
- (CPTab *)tab:(CPTab *)tab openTabWithRequest:(NSURLRequest *)request inBackground:(BOOL)background;
- (void)tabWantsToClose:(CPTab *)tab;
@end

// One page in a browser window. A tab that has not been looked at for a while
// can be discarded: its WebView, and the memory the page held, are released,
// and only the address, title and scroll position are kept. Selecting it
// again reloads the page, which the disk cache makes cheap. On a 256MB G3
// this is what lets more than a couple of tabs stay open at all.
@interface CPTab : NSObject
{
    id        owner;            // the window controller; not retained
    WebView  *webView;          // nil while discarded
    NSURL    *URL;
    NSString *title;
    BOOL      loading;
    double    progress;
    float     savedScrollOffset;
    NSDate   *lastSelected;
    NSDate   *loadStarted;
    // With debug logging on: what each resource request is for, until it
    // finishes, so a page that stops making progress can say what it waits on.
    NSMutableDictionary *pendingResources;
    unsigned  nextResourceID;
    // Reader: showing a page's article on its own (see CPReader).
    id        reader;           // a CPReader fetching the page, if any
    BOOL      showingReader;
    BOOL      readerLoadPending;
    BOOL      warningLoadPending;   // the safe browsing page is going up
    NSImage  *favicon;
    WebPreferences *preferences; // this tab's own: sites differ in JavaScript and images
}

- (id)initWithOwner:(id)anOwner;

// The tab's WebView, created (and the page reloaded) if it was discarded.
- (WebView *)webView;
- (BOOL)isDiscarded;
- (void)discard;
- (void)close;

- (void)loadURL:(NSURL *)aURL;
- (void)loadRequest:(NSURLRequest *)request;

- (NSURL *)URL;
- (NSString *)title;
- (NSString *)displayTitle;
- (BOOL)isShowingPDF;
- (NSData *)pageData;          // the main frame's bytes as they came
- (BOOL)isLoading;
- (double)progress;
- (BOOL)canGoBack;
- (BOOL)canGoForward;

- (NSDate *)lastSelected;
- (void)noteSelected;

- (void)goBack;
- (void)goForward;
- (void)reload;
// Loads the page again as its site version (desktop, mobile or basic) now
// says; used after the choice for this site changes.
- (void)reloadForSiteMode;
- (void)stopLoading;

// Reader: the page's article alone, with no scripts and small images. From
// the page as loaded when it has finished; otherwise the page's HTML is
// fetched on its own, which is the quick way through a heavy page.
- (BOOL)isShowingReader;
// The site's icon, or nil.
- (NSImage *)favicon;
// Applies the page's site settings (text size, JavaScript, images) again.
- (void)applySiteSettings;
// Opens an address straight in Reader, fetching only its HTML.
- (void)openReaderForURL:(NSURL *)aURL;
- (BOOL)canShowReader;
- (void)toggleReader;

@end
