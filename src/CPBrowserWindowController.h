/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class WebView;

@interface CPBrowserWindowController : NSWindowController
{
    WebView             *webView;
    NSButton            *backButton;
    NSButton            *forwardButton;
    NSButton            *reloadButton;
    NSTextField         *addressField;
    NSTextField         *statusField;
    NSProgressIndicator *progressBar;
    BOOL                 loading;
}

- (id)init;

- (WebView *)webView;
- (void)loadURL:(NSURL *)url;
- (void)loadAddressString:(NSString *)address;

- (IBAction)goBack:(id)sender;
- (IBAction)goForward:(id)sender;
- (IBAction)goHome:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)stopLoading:(id)sender;
- (IBAction)reloadOrStop:(id)sender;
- (IBAction)openLocation:(id)sender;
- (IBAction)addressEntered:(id)sender;
- (IBAction)makeTextLarger:(id)sender;
- (IBAction)makeTextSmaller:(id)sender;

@end
