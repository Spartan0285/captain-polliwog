/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// The same page, years ago, out of the Internet Archive.
//
// A browser this old is in an odd position: the live web is largely too heavy
// for it, while the web it was built for is still sitting in the Wayback
// Machine, and renders here exactly as it did. apple.com from January 2005
// draws on a PowerBook G4 in full, and spends 1.7 seconds running its scripts
// where the present-day one spends ten.
//
// No API is involved and none is needed. web.archive.org answers
//   https://web.archive.org/web/YYYYMMDD/<address>
// with a redirect to whichever capture is nearest that date, so this is URL
// building rather than a protocol. The archive's own availability endpoint
// exists, returns JSON, and rate-limits; asking it would buy nothing.
@interface CPTimeMachine : NSObject

// The archive's address for a page on a date. nil for an address the archive
// cannot hold - a file, a blob, our own start page.
+ (NSURL *)archiveURLForURL:(NSURL *)url onDate:(NSDate *)date;

// Whether an address is already inside the archive, and the parts of it: the
// page it is a copy of, and when the copy was taken. Used so that opening
// Time Machine on an archived page offers the original page and the date
// showing, rather than an archive of an archive.
+ (BOOL)isArchiveURL:(NSURL *)url;
+ (NSURL *)originalURLFromArchiveURL:(NSURL *)url;
+ (NSDate *)dateFromArchiveURL:(NSURL *)url;

// The date the sheet opens at: the one being looked at if this is already an
// archived page, else the preference, else a date far enough back to be worth
// travelling to.
+ (NSDate *)startingDate;
+ (NSDate *)preferredDate;
+ (void)setPreferredDate:(NSDate *)date;

// How a date reads on this Mac, in this person's language and region - for
// the status line and the button. NSDatePicker handles entry itself, which is
// why there is no format preference: it follows the system, and a setting
// could only disagree with it.
+ (NSString *)describeDate:(NSDate *)date;

@end
