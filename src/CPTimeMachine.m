/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPTimeMachine.h"

static NSString * const CPTimeMachinePreferredDateKey = @"CPTimeMachineDate";
static NSString * const CPArchivePrefix = @"https://web.archive.org/web/";

// Far enough back that the web still fitted on these machines, and a date
// anyone can picture. Used when nothing has been chosen.
#define CPDefaultArchiveYear  2005
#define CPDefaultArchiveMonth 1
#define CPDefaultArchiveDay   1

@implementation CPTimeMachine

+ (NSURL *)archiveURLForURL:(NSURL *)url onDate:(NSDate *)date
{
    NSString *scheme = [[url scheme] lowercaseString];
    NSString *address;
    NSCalendarDate *calendar;

    if (url == nil || date == nil)
        return nil;
    // Only what the archive could have fetched. A file on this disk, a blob
    // made by a script, our own start page: there is nothing to look up.
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
        return nil;

    // Already an archived page: go to the same original on the new date
    // rather than asking the archive for a copy of itself.
    if ([self isArchiveURL:url]) {
        NSURL *original = [self originalURLFromArchiveURL:url];
        if (original != nil)
            url = original;
    }

    address = [url absoluteString];
    // NSCalendarDate rather than NSDateFormatter: this is the machine-facing
    // stamp the archive wants, fixed as YYYYMMDD whatever the region, and it
    // must not follow anyone's locale.
    calendar = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate:
                [date timeIntervalSinceReferenceDate]];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@%04d%02d%02d/%@",
        CPArchivePrefix, (int)[calendar yearOfCommonEra], (int)[calendar monthOfYear],
        (int)[calendar dayOfMonth], address]];
}

+ (BOOL)isArchiveURL:(NSURL *)url
{
    NSString *host = [[url host] lowercaseString];
    return host != nil && [host hasSuffix:@"web.archive.org"];
}

// .../web/20050116072556/http://www.apple.com/ - the part after the stamp is
// the original address, and it keeps its own slashes, so this takes
// everything from where the scheme begins rather than splitting on them.
+ (NSURL *)originalURLFromArchiveURL:(NSURL *)url
{
    NSString *path = [url absoluteString];
    NSRange http;

    if (![self isArchiveURL:url])
        return nil;
    http = [path rangeOfString:@"/http"];
    if (http.location == NSNotFound)
        return nil;
    return [NSURL URLWithString:[path substringFromIndex:http.location + 1]];
}

+ (NSDate *)dateFromArchiveURL:(NSURL *)url
{
    NSString *path = [url path];
    NSArray *parts;
    NSString *stamp = nil;
    NSEnumerator *pieces;
    NSString *piece;
    int year, month, day;

    if (![self isArchiveURL:url])
        return nil;
    parts = [path pathComponents];
    pieces = [parts objectEnumerator];
    while ((piece = [pieces nextObject]) != nil) {
        // The stamp is fourteen digits, sometimes with a suffix like id_ or
        // if_ that says how the archive should serve it.
        NSString *digits = piece;
        NSRange underscore = [piece rangeOfString:@"_"];
        if (underscore.location != NSNotFound)
            digits = [piece substringToIndex:underscore.location];
        if ([digits length] >= 8 && [digits length] <= 14
            && [digits rangeOfCharacterFromSet:
                [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
            stamp = digits;
            break;
        }
    }
    if (stamp == nil)
        return nil;
    year = [[stamp substringToIndex:4] intValue];
    month = [[stamp substringWithRange:NSMakeRange(4, 2)] intValue];
    day = [[stamp substringWithRange:NSMakeRange(6, 2)] intValue];
    if (year < 1996 || month < 1 || month > 12 || day < 1 || day > 31)
        return nil;    // the archive did not exist before 1996
    return [NSCalendarDate dateWithYear:year month:month day:day
                                   hour:12 minute:0 second:0
                               timeZone:[NSTimeZone localTimeZone]];
}

+ (NSDate *)preferredDate
{
    NSDate *stored = [[NSUserDefaults standardUserDefaults]
                      objectForKey:CPTimeMachinePreferredDateKey];
    if ([stored isKindOfClass:[NSDate class]])
        return stored;
    return [NSCalendarDate dateWithYear:CPDefaultArchiveYear month:CPDefaultArchiveMonth
                                    day:CPDefaultArchiveDay hour:12 minute:0 second:0
                               timeZone:[NSTimeZone localTimeZone]];
}

+ (void)setPreferredDate:(NSDate *)date
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (date == nil)
        [defaults removeObjectForKey:CPTimeMachinePreferredDateKey];
    else
        [defaults setObject:date forKey:CPTimeMachinePreferredDateKey];
    [defaults synchronize];
}

+ (NSDate *)startingDate
{
    return [self preferredDate];
}

+ (NSString *)describeDate:(NSDate *)date
{
    // The system's own long form, so a German Mac reads "15. Januar 2005" and
    // an American one "January 15, 2005" without this file knowing either.
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    if ([formatter respondsToSelector:@selector(setFormatterBehavior:)])
        [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [formatter setDateStyle:NSDateFormatterLongStyle];
    [formatter setTimeStyle:NSDateFormatterNoStyle];
    return [formatter stringFromDate:date];
}

@end
