/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Gives these systems an emoji font, because neither of them has one.
//
// Tiger and Leopard predate emoji entirely. A page with a heart or a smiling
// face in it has, until now, drawn an empty box - and on 10.4 it did worse
// than that: asking CoreText to find a fallback for a character no installed
// font maps dereferences null inside it and takes the browser with it. The
// engine no longer asks (see the CP_TIGER notes in FontCascade.cpp), which
// stopped the crash but left the boxes.
//
// This is the other half. Noto Emoji - the monochrome one, under the SIL
// Open Font License - is bundled and activated for this process alone, so
// the characters are mapped and the fallback CoreText used to fail at is
// never needed. Black and white on purpose: every colour emoji format
// postdates this engine by years and none of them would draw.
//
// Process-local activation, never the user's font book: a browser has no
// business installing fonts on someone's Mac.
@interface CPEmojiFont : NSObject

// Idempotent, and safe to call when the font is missing - a browser that
// cannot find its emoji font should still start.
+ (void)activateBundledFont;

// What activateBundledFont managed, for the About panel and for tests.
+ (BOOL)isActive;
+ (NSString *)activationReport;

@end
