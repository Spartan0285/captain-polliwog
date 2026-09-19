/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class WebView;

@protocol CPFindBarOwner
- (WebView *)webViewForFindBar;
- (void)findBarShouldClose;
@end

// Safari's find banner: a search field over the page that finds as you
// type, highlights every match, counts them, and steps through them.
@interface CPFindBar : NSView {
    id <CPFindBarOwner> owner;
    NSSearchField *field;
    NSTextField *countLabel;
    NSButton *previousButton;
    NSButton *nextButton;
}

- (id)initWithFrame:(NSRect)frame owner:(id <CPFindBarOwner>)anOwner;

- (NSSearchField *)field;
- (NSString *)searchString;
- (void)setSearchString:(NSString *)string;

// Finds the next (or previous) match after the selection, wrapping around.
- (void)findForward:(BOOL)forward;
// Highlights and counts the matches in the owner's page, and selects the
// first; for a new page or a change to the search string.
- (void)refreshMatches;
// Removes the highlights.
- (void)clearMatches;

@end
