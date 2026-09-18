/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class DOMDocument;
@class WebView;

// Reader: a page's article on its own, as plain, light HTML with no
// scripts. It is found as Readability finds it: paragraphs score their
// containers by how much prose they hold, and the container that scores
// best, with its related siblings, is the article. Images are shown small,
// each a link to the full-size image.
@interface CPReader : NSObject
{
    id       delegate;          // not retained
    WebView *loaderView;        // loads pages without scripts, images or styles
    NSURL   *requestedURL;
    id       mainResource;      // the identifier of the page itself
}

// The reader page for a document that has already loaded, or nil when no
// article stands out.
+ (NSString *)readerHTMLForDocument:(DOMDocument *)document URL:(NSURL *)url;

- (id)initWithDelegate:(id)aDelegate;

// Fetches the page's HTML alone (no scripts run, no images or style sheets
// load), then tells the delegate -reader:didMakeHTML:forURL:, with nil HTML
// if the page failed to load or had no article.
- (void)loadURL:(NSURL *)url userAgent:(NSString *)userAgent;
- (void)cancel;

@end

@interface NSObject (CPReaderDelegate)
- (void)reader:(CPReader *)reader didMakeHTML:(NSString *)html forURL:(NSURL *)url;
@end
