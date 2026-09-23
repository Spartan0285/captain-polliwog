/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// NSTrackingArea, which arrived in Leopard: cursor and mouse-moved
// tracking. Tiger tracks a rectangle instead, through
// -addTrackingRect:owner:userData:assumeInside:, so an area remembers what
// it was made with and the category here adds the 10.5 way of putting one
// on a view.
//
// Only the headers that do not declare NSTrackingArea are imported, since
// the 10.5 SDK declares it and this file defines it.

#import <Foundation/NSObject.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <AppKit/NSView.h>

@interface NSTrackingArea : NSObject
{
    NSRect       rect;
    NSUInteger   options;
    id           owner;          // not retained, as AppKit does not
    NSDictionary *userInfo;
    NSTrackingRectTag tag;
}
- (id)initWithRect:(NSRect)aRect options:(NSUInteger)someOptions owner:(id)anOwner userInfo:(NSDictionary *)info;
- (NSRect)rect;
- (NSUInteger)options;
- (id)owner;
- (NSDictionary *)userInfo;
@end

@implementation NSTrackingArea

- (id)initWithRect:(NSRect)aRect options:(NSUInteger)someOptions owner:(id)anOwner userInfo:(NSDictionary *)info
{
    self = [super init];
    if (self == nil)
        return nil;
    rect = aRect;
    options = someOptions;
    owner = anOwner;
    userInfo = [info retain];
    tag = 0;
    return self;
}

- (void)dealloc
{
    [userInfo release];
    [super dealloc];
}

- (NSRect)rect { return rect; }
- (NSUInteger)options { return options; }
- (id)owner { return owner; }
- (NSDictionary *)userInfo { return userInfo; }
- (NSTrackingRectTag)trackingTag { return tag; }
- (void)setTrackingTag:(NSTrackingRectTag)aTag { tag = aTag; }

@end

// -addTrackingArea: is 10.5's; Tiger tracks a rectangle. The area remembers
// the tag it was given so it can be taken off again.
@implementation NSView (CPTrackingAreas)

- (void)addTrackingArea:(NSTrackingArea *)area
{
    NSTrackingRectTag tag = [self addTrackingRect:[area rect] owner:[area owner]
                                         userData:NULL assumeInside:NO];
    [area setTrackingTag:tag];
}

- (void)removeTrackingArea:(NSTrackingArea *)area
{
    if ([area trackingTag] != 0)
        [self removeTrackingRect:[area trackingTag]];
}

- (NSArray *)trackingAreas
{
    return [NSArray array];
}

@end

// Layer-backed views are 10.5's, and so are these accessors. A view that
// answers "no layer, and does not want one" is a view drawn the ordinary
// way, which is how this engine runs on Tiger (accelerated compositing
// off). See CoreAnimationStubs.m.
@implementation NSView (CPTigerLayers)

- (id)layer { return nil; }
- (void)setLayer:(id)layer { }
- (BOOL)wantsLayer { return NO; }
- (void)setWantsLayer:(BOOL)wants { }
- (BOOL)canDrawSubviewsIntoLayer { return NO; }
- (void)setCanDrawSubviewsIntoLayer:(BOOL)can { }
- (BOOL)layerUsesCoreImageFilters { return NO; }
- (void)setLayerUsesCoreImageFilters:(BOOL)uses { }
- (NSInteger)layerContentsRedrawPolicy { return 0; }
- (void)setLayerContentsRedrawPolicy:(NSInteger)policy { }
- (id)animator { return self; }
- (NSDictionary *)animations { return nil; }
- (void)setAnimations:(NSDictionary *)animations { }

@end
