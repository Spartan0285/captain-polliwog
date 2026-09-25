/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// The address field as Safari draws it: one rounded field holding the
// site's icon, the address, and buttons for Favorites, the page's settings
// (aA) and reload or stop. Loading progress runs along its bottom edge.
@interface CPAddressBar : NSView
{
    NSImageView *iconView;
    NSTextField *textField;
    NSButton    *readerButton;
    BOOL         readerAvailable;
    NSButton    *favoriteButton;
    NSButton    *pageButton;
    NSButton    *reloadButton;
    double       progress;          // 0 when not loading
}

- (NSTextField *)textField;
- (NSButton *)readerButton;
// Shown only when the page has an article in it, as Safari does.
- (void)setReaderAvailable:(BOOL)available;
- (NSButton *)favoriteButton;
- (NSButton *)pageButton;
- (NSButton *)reloadButton;
- (void)setIcon:(NSImage *)icon;
- (void)setProgress:(double)value;

@end
