/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPEmojiFont.h"
#import "CPDebugSnapshot.h"
#import <ApplicationServices/ApplicationServices.h>

static BOOL gActive = NO;
static NSString *gReport = nil;

@implementation CPEmojiFont

+ (void)activateBundledFont
{
    NSString *path;
    NSData *font;
    ATSFontContainerRef container = 0;
    OSStatus status;

    if (gActive)
        return;

    path = [[NSBundle mainBundle] pathForResource:@"NotoEmoji-Regular" ofType:@"ttf"];
    if (path == nil) {
        gReport = [@"no emoji font in this build" retain];
        return;
    }
    font = [NSData dataWithContentsOfFile:path];
    if ([font length] == 0) {
        gReport = [@"the emoji font would not read" retain];
        return;
    }

    // From memory rather than from the file, and deliberately.
    //
    // The file-based calls are split across the two systems this has to run
    // on: ATSFontActivateFromFileSpecification wants an FSSpec and is gone
    // from later SDKs, ATSFontActivateFromFileReference wants an FSRef and
    // arrived in 10.5. ATSFontActivateFromMemory has been there since 10.2
    // and behaves the same on both, so there is one code path instead of two
    // and no deprecated struct to build.
    //
    // kATSFontContextLocal is the important argument: the font belongs to
    // this process and disappears with it. A browser has no business
    // installing anything in someone's font book.
    status = ATSFontActivateFromMemory((void *)[font bytes], (ByteCount)[font length],
                                       kATSFontContextLocal, kATSFontFormatUnspecified,
                                       NULL, kATSOptionFlagsDefault, &container);
    if (status != noErr || container == 0) {
        gReport = [[NSString stringWithFormat:@"the emoji font would not activate (%d)",
                    (int)status] retain];
        NSLog(@"Captain Polliwog: %@", gReport);
        return;
    }

    gActive = YES;
    gReport = [[NSString stringWithFormat:@"Noto Emoji active (%lu KB)",
                (unsigned long)([font length] / 1024)] retain];
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: %@", gReport);
}

+ (BOOL)isActive
{
    return gActive;
}

+ (NSString *)activationReport
{
    return gReport != nil ? gReport : @"the emoji font has not been asked for yet";
}

@end
