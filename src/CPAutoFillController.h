/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// The AutoFill window: saved passwords (Safari's included), the address
// forms are filled with, and cards.
@interface CPAutoFillController : NSWindowController
{
    NSTabView *tabs;
    NSTableView *loginTable;
    NSArray *logins;
    NSMutableDictionary *addressFields;   // autocomplete name -> NSTextField
    NSTableView *cardTable;
    NSArray *cards;
    NSTextField *cardName, *cardNumber, *cardMonth, *cardYear;
    BOOL cardsUnlocked;
}

+ (CPAutoFillController *)sharedController;

@end
