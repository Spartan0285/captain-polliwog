/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class WebView;
@class CPTab;

// What a tab tells the window it lives in. The window implements these.
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

@end
