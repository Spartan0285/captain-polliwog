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
    NSMutableArray *switchBoxes;       // the Performance tab's switches, by tag
    NSTextField   *homePageField;
    NSPopUpButton *newTabPopUp;
    NSTextField   *downloadsField;
    NSPopUpButton *siteModePopUp;
    NSButton      *acceleratorBox;
    NSButton      *updatesBox;
    NSButton      *defaultBrowserButton;
    NSTextField   *defaultBrowserStatus;
    NSTableView   *websitesTable;
    NSArray       *configuredSites;     // the rows of that table
    NSTextField   *acceleratorStatus;
    NSTextField   *pairingField;
}

+ (CPPreferencesController *)sharedController;

- (void)writeDebugSnapshot;

- (IBAction)memoryProfileChanged:(id)sender;
- (IBAction)diskSizeChanged:(id)sender;
- (IBAction)chooseCacheLocation:(id)sender;
- (IBAction)useDefaultCacheLocation:(id)sender;
- (IBAction)clearCacheNow:(id)sender;
- (IBAction)switchChanged:(id)sender;
- (IBAction)homePageChanged:(id)sender;
- (IBAction)useCurrentPageAsHome:(id)sender;
- (IBAction)newTabPageChanged:(id)sender;
- (IBAction)chooseDownloadsFolder:(id)sender;
- (IBAction)siteModeChanged:(id)sender;

@end
