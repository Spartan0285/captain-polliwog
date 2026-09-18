/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@interface CPPreferencesController : NSWindowController
{
    NSPopUpButton *memoryPopUp;
    NSTextField   *memoryExplanation;
    NSTextField   *diskSizeField;
    NSTextField   *diskSizeNote;
    NSTextField   *locationField;
    NSButton      *imagesCheckbox;
    NSButton      *memoryReliefCheckbox;
    NSTextField   *downloadsField;
}

+ (CPPreferencesController *)sharedController;

- (void)writeDebugSnapshot;

- (IBAction)memoryProfileChanged:(id)sender;
- (IBAction)diskSizeChanged:(id)sender;
- (IBAction)chooseCacheLocation:(id)sender;
- (IBAction)useDefaultCacheLocation:(id)sender;
- (IBAction)clearCacheNow:(id)sender;
- (IBAction)imagesChanged:(id)sender;
- (IBAction)memoryReliefChanged:(id)sender;
- (IBAction)chooseDownloadsFolder:(id)sender;

@end
