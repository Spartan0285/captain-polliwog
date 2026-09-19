/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// What AutoFill keeps, in the Mac's Keychain.
//
// Logins are internet passwords, the kind Safari saves, so Safari's saved
// passwords are there too: nothing to import. The first time a password
// Safari saved is read, the Mac asks whether Captain Polliwog may.
//
// Cards are Keychain items of Captain Polliwog's own: name, number and
// expiry. Never the security code.
@interface CPKeychain : NSObject

// Usernames saved for a site (for "www.example.com", "example.com" too).
+ (NSArray *)accountsForHost:(NSString *)host;
+ (NSString *)passwordForHost:(NSString *)host account:(NSString *)account;
+ (BOOL)savePassword:(NSString *)password forHost:(NSString *)host account:(NSString *)account;
// Every saved login: dictionaries with "host" and "account".
+ (NSArray *)allLogins;
+ (void)removeLoginForHost:(NSString *)host account:(NSString *)account;

// Cards: dictionaries with "label", "name", "number", "month", "year".
+ (NSArray *)cards;
+ (void)saveCard:(NSDictionary *)card;
+ (void)removeCardWithLabel:(NSString *)label;

@end
