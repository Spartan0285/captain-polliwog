/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPDownload;

// The Downloads window. Rows are plain views stacked in a scroll view rather
// than a table: Tiger's NSTableView has no way to host a progress bar.
@interface CPDownloadsController : NSWindowController
{
    NSMutableArray *downloads;
    NSView         *list;
    NSTextField    *emptyLabel;
}

+ (CPDownloadsController *)sharedController;

// Saves the response to request into the downloads folder.
- (CPDownload *)startDownloadWithRequest:(NSURLRequest *)request suggestedFilename:(NSString *)filename;

- (BOOL)hasActiveDownloads;

- (IBAction)clearFinished:(id)sender;

@end
