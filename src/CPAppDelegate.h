#import <Cocoa/Cocoa.h>

@class CPBrowserWindowController;

@interface CPAppDelegate : NSObject
{
    NSMutableArray *browserWindows;
}

+ (NSString *)userAgentApplicationName;
+ (NSURL *)startPageURL;

- (void)buildMainMenu;
- (CPBrowserWindowController *)openBrowserWindow;
- (void)browserWindowWillClose:(CPBrowserWindowController *)controller;

- (IBAction)newWindow:(id)sender;

@end
