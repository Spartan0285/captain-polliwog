/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPTab;

// AutoFill: saved logins, an address and cards, filled into web forms.
//
// Passwords and cards are only filled after the Mac's own password dialog
// (Authorization Services, as for an administrator change); AutoFill then
// stays unlocked until it has gone unused for ten minutes. Addresses fill
// without asking. Logins are offered for saving when a page with a typed
// password is left. See CPKeychain for where things are kept.
@interface CPAutoFill : NSObject

// Edit > AutoFill Form: the page's login, card or address fields.
+ (void)fillFormInTab:(CPTab *)tab;

// Called just before a page is left: offers to save a login typed there.
+ (void)captureLoginInTab:(CPTab *)tab;

// Asks for the Mac's password unless unlocked recently; YES if unlocked.
+ (BOOL)unlockWithPrompt:(NSString *)prompt;

// The address filled into forms: saved, or else from the Address Book's
// "Me" card. Keys are autocomplete names (given-name, postal-code, ...).
+ (NSDictionary *)address;
+ (NSDictionary *)addressFromMeCard;
+ (void)setAddress:(NSDictionary *)address;

@end
