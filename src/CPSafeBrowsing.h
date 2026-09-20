/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Warning before a page known for phishing or malware.
//
// The list is Google's Safe Browsing data, but this browser never talks to
// Google: asking Google about a URL would tell Google every site visited, and
// the protocol that avoids that (Update API v4, with its Rice-encoded
// incremental updates and its 32-bit-prefix set) is a lot of machinery for a
// G3. Instead the maintainer builds a plain sorted list of 4-byte hash
// prefixes on a modern Mac (scripts/make-safebrowsing-list.py) and publishes
// it alongside the releases; this reads that file and looks URLs up in it,
// entirely on this machine.
//
// A prefix match is not proof - four bytes of SHA-256 collide - so the
// warning says what it is: this address matches one on the list.
@interface CPSafeBrowsing : NSObject

// At launch. Loads the list if one has been downloaded.
+ (void)start;

+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;

// The heart of it: is this address on the list? Answered from memory, so it
// is safe to ask on the main thread before every navigation.
+ (BOOL)isDangerous:(NSURL *)url;

// After the user chooses to go on anyway, that site is not asked about again
// until the browser is next opened.
+ (void)allowOnce:(NSURL *)url;

// How many prefixes are loaded, and when the list was made: for Preferences.
+ (unsigned)entryCount;
+ (NSDate *)listDate;

// The page shown in place of the site.
+ (NSString *)warningPageHTMLForURL:(NSURL *)url;

@end
