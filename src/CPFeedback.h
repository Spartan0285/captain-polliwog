/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Telling whoever makes this what went wrong.
//
// A window with a topic, a description, optionally a picture of the browser's
// own window, and the few facts about this Mac that make a report actionable.
// Everything that will be sent is shown before it is sent; nothing is
// collected in the background, and nothing is sent unless Send is pressed.
//
// It goes as JSON to one endpoint that serves every Cytrus Software app - the
// "app" field says which one. When that cannot be reached, the report is kept
// in an outbox on disk and sent at the next launch, because somebody who
// writes three paragraphs and gets "could not connect" does not write them
// again.
@interface CPFeedback : NSObject
{
    NSWindow      *window;
    NSPopUpButton *topic;
    NSTextView    *message;
    NSTextField   *email;
    NSButton      *includeShot;
    NSImageView   *shotView;
    NSTextField   *status;
    NSButton      *sendButton;
    NSImage       *shot;
    NSString      *page;         // where they were, in words
    NSString      *reportID;     // kept across retries, so one report is one issue
    NSString      *queuedPath;   // the outbox file this came from, when retrying
    NSURLConnection *connection;
    NSMutableData   *response;
    int              statusCode;
}

// Opens the window, with a picture of the given window ready to attach and
// the address of the page being looked at.
+ (void)openForWindow:(NSWindow *)aWindow page:(NSString *)pageDescription;

// At launch: anything in the outbox that could not be sent before.
+ (void)sendQueuedReports;

@end
