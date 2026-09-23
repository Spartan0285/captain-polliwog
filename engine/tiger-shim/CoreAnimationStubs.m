/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// Core Animation arrived in Mac OS X 10.5. Tiger's QuartzCore has Core
// Image and nothing else, so an engine built for 10.4 stops in dyld before
// it runs a line: WebCore and WebKitLegacy name seven CA classes, four CA
// functions and eleven CA constants between them, and a class reference
// cannot be weak on Tiger's Objective-C runtime.
//
// This library supplies them. The classes are empty: the engine is run with
// accelerated compositing off on 10.4 (Leopard WebKit's own 10.4 target did
// the same), so nothing should ever build a layer tree. "Should" is why
// they also swallow any message they are sent, answering zero, rather than
// stopping the browser on an unrecognized selector - and say so in the
// system log the first time, so a path that does reach Core Animation can
// be found and closed.
//
// The functions and constants are real: the transforms are pure arithmetic
// on a matrix, CACurrentMediaTime is the same clock CA used (animation
// timing reads it whether or not anything is composited), and the constants
// are the strings CA itself uses, so a value set from one and read back
// through another still compares equal.

#import <Foundation/Foundation.h>
#include <mach/mach_time.h>

#if !defined(CGFLOAT_DEFINED)
typedef float CGFloat;
#endif

typedef struct CATransform3D {
    CGFloat m11, m12, m13, m14;
    CGFloat m21, m22, m23, m24;
    CGFloat m31, m32, m33, m34;
    CGFloat m41, m42, m43, m44;
} CATransform3D;

const CATransform3D CATransform3DIdentity = {
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f
};

CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz)
{
    CATransform3D t = CATransform3DIdentity;
    t.m11 = sx;
    t.m22 = sy;
    t.m33 = sz;
    return t;
}

CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz)
{
    t.m41 += tx * t.m11 + ty * t.m21 + tz * t.m31;
    t.m42 += tx * t.m12 + ty * t.m22 + tz * t.m32;
    t.m43 += tx * t.m13 + ty * t.m23 + tz * t.m33;
    t.m44 += tx * t.m14 + ty * t.m24 + tz * t.m34;
    return t;
}

// CA's clock: seconds since boot, from the same mach timebase.
double CACurrentMediaTime(void)
{
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0)
        mach_timebase_info(&timebase);
    return (double)mach_absolute_time() * (double)timebase.numer
        / (double)timebase.denom / 1000000000.0;
}

// The strings Core Animation itself uses for these: a layer property set
// from one and read back through another has to compare equal.
NSString * const kCATransactionAnimationDuration = @"animationDuration";
NSString * const kCATransactionDisableActions = @"disableActions";
NSString * const kCAFillModeForwards = @"forwards";
NSString * const kCAFillModeBackwards = @"backwards";
NSString * const kCAFillModeBoth = @"both";
NSString * const kCAFilterLinear = @"linear";
NSString * const kCAFilterNearest = @"nearest";
NSString * const kCAFilterTrilinear = @"trilinear";
NSString * const kCAFilterGaussianBlur = @"gaussianBlur";
NSString * const kCAGravityCenter = @"center";
NSString * const kCAMediaTimingFunctionLinear = @"linear";

static void CPReportCoreAnimationUse(id receiver, SEL selector)
{
    NSLog(@"Captain Polliwog: Core Animation is not on this system - ignored %@ to %@",
          NSStringFromSelector(selector), receiver);
}

// Any message at all, answered with zero. The signature says "returns an
// object, takes objects", which is what almost every call here would be;
// a caller wanting a structure or a float still gets zeroed memory back,
// because the invocation's return buffer starts that way.
#define CP_STUB_CLASS(name)                                                     \
@interface name : NSObject                                                      \
@end                                                                            \
@implementation name                                                            \
+ (NSMethodSignature *)methodSignatureForSelector:(SEL)selector                 \
{                                                                               \
    NSMethodSignature *signature = [super methodSignatureForSelector:selector]; \
    return signature != nil ? signature                                         \
        : [NSMethodSignature signatureWithObjCTypes:"@@:@@@@@@@@"];             \
}                                                                               \
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector                 \
{                                                                               \
    NSMethodSignature *signature = [super methodSignatureForSelector:selector]; \
    return signature != nil ? signature                                         \
        : [NSMethodSignature signatureWithObjCTypes:"@@:@@@@@@@@"];             \
}                                                                               \
+ (void)forwardInvocation:(NSInvocation *)invocation                            \
{                                                                               \
    CPReportCoreAnimationUse(self, [invocation selector]);                      \
}                                                                               \
- (void)forwardInvocation:(NSInvocation *)invocation                            \
{                                                                               \
    CPReportCoreAnimationUse(self, [invocation selector]);                      \
}                                                                               \
@end

CP_STUB_CLASS(CALayer)
CP_STUB_CLASS(CATransaction)
CP_STUB_CLASS(CABasicAnimation)
CP_STUB_CLASS(CAKeyframeAnimation)
CP_STUB_CLASS(CAMediaTimingFunction)
CP_STUB_CLASS(CAFilter)
CP_STUB_CLASS(CAOpenGLLayer)
