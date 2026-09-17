#import <Cocoa/Cocoa.h>

// Toolbar glyphs drawn in code: Tiger's fonts lack reliable arrow symbols,
// and bundling image files would cost disk reads at launch on slow drives.
@interface CPIcons : NSObject

+ (NSImage *)backImage;
+ (NSImage *)forwardImage;
+ (NSImage *)reloadImage;
+ (NSImage *)stopImage;

@end
