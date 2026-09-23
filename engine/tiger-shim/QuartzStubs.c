/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// What Leopard added to Quartz. Tiger draws everything these do, by older
// means: gradients through CGShading and a CGFunction, positioned glyphs one
// at a time. The font-smoothing switches have no Tiger equivalent and are
// no-ops, which leaves text drawn the way Tiger draws it anyway.

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>

#pragma mark Colours

CGColorRef CGColorCreateGenericRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[4] = { red, green, blue, alpha };
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);
    return color;
}

CGColorRef CGColorCreateGenericGray(CGFloat gray, CGFloat alpha)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGFloat components[2] = { gray, alpha };
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);
    return color;
}

const CFStringRef kCGColorWhite = CFSTR("kCGColorWhite");
const CFStringRef kCGColorSpaceSRGB = CFSTR("kCGColorSpaceGenericRGB");   // the nearest Tiger has

// The constant colours, made once and kept, as Quartz does.
CGColorRef CGColorGetConstantColor(CFStringRef name)
{
    static CGColorRef white, black, clear;

    if (name != NULL && CFStringCompare(name, CFSTR("kCGColorBlack"), 0) == kCFCompareEqualTo) {
        if (black == NULL)
            black = CGColorCreateGenericGray(0.0, 1.0);
        return black;
    }
    if (name != NULL && CFStringCompare(name, CFSTR("kCGColorClear"), 0) == kCFCompareEqualTo) {
        if (clear == NULL)
            clear = CGColorCreateGenericGray(0.0, 0.0);
        return clear;
    }
    if (white == NULL)
        white = CGColorCreateGenericGray(1.0, 1.0);
    return white;
}

// Tiger has CGColorSpaceGetNumberOfComponents but not the model enumeration.
// Component counts tell the models WebKit asks about apart.
typedef int32_t CGColorSpaceModelShim;
CGColorSpaceModelShim CGColorSpaceGetModel(CGColorSpaceRef space)
{
    switch (space != NULL ? CGColorSpaceGetNumberOfComponents(space) : 0) {
    case 1: return 0;   // kCGColorSpaceModelMonochrome
    case 3: return 1;   // kCGColorSpaceModelRGB
    case 4: return 2;   // kCGColorSpaceModelCMYK
    default: return -1; // kCGColorSpaceModelUnknown
    }
}

#pragma mark Gradients

// CGGradient is Leopard's; Tiger has CGShading, which is the same thing with
// the colour ramp supplied as a function. The gradient here keeps the stops
// and hands out a function when it is drawn.
typedef struct CPGradient {
    CFIndex             retainCount;
    CGColorSpaceRef     space;
    size_t              count;
    CGFloat            *components;   // count * componentsPerColour
    CGFloat            *locations;
    size_t              perColour;
} CPGradient;

// CGGradientRef is opaque in the header; here is what it points at.
#define CP_GRADIENT(g) ((CPGradient *)(g))

static void CPGradientEvaluate(void *info, const CGFloat *in, CGFloat *out)
{
    CPGradient *gradient = (CPGradient *)info;
    CGFloat t = in[0];
    size_t i, upper = 1;

    if (gradient->count == 0)
        return;
    while (upper < gradient->count && gradient->locations[upper] < t)
        upper++;
    if (upper >= gradient->count)
        upper = gradient->count - 1;
    {
        size_t lower = upper > 0 ? upper - 1 : 0;
        CGFloat a = gradient->locations[lower], b = gradient->locations[upper];
        CGFloat f = (b > a) ? (t - a) / (b - a) : 0.0;
        if (f < 0.0) f = 0.0;
        if (f > 1.0) f = 1.0;
        for (i = 0; i < gradient->perColour; i++) {
            CGFloat from = gradient->components[lower * gradient->perColour + i];
            CGFloat to = gradient->components[upper * gradient->perColour + i];
            out[i] = from + (to - from) * f;
        }
    }
}

static CGFunctionRef CPGradientFunction(CPGradient *gradient)
{
    static const CGFunctionCallbacks callbacks = { 0, CPGradientEvaluate, NULL };
    CGFloat domain[2] = { 0.0, 1.0 };
    CGFloat *range = (CGFloat *)calloc(gradient->perColour * 2, sizeof(CGFloat));
    size_t i;
    CGFunctionRef function;

    for (i = 0; i < gradient->perColour; i++) {
        range[i * 2] = 0.0;
        range[i * 2 + 1] = 1.0;
    }
    function = CGFunctionCreate(gradient, 1, domain, gradient->perColour, range, &callbacks);
    free(range);
    return function;
}

CGGradientRef CGGradientCreateWithColorComponents(CGColorSpaceRef space, const CGFloat components[],
                                                      const CGFloat locations[], size_t count)
{
    CPGradient *gradient = (CPGradient *)calloc(1, sizeof(CPGradient));
    size_t i;

    gradient->retainCount = 1;
    gradient->space = space != NULL ? CGColorSpaceRetain(space) : CGColorSpaceCreateDeviceRGB();
    gradient->perColour = CGColorSpaceGetNumberOfComponents(gradient->space) + 1;   // plus alpha
    gradient->count = count;
    gradient->components = (CGFloat *)calloc(count * gradient->perColour, sizeof(CGFloat));
    gradient->locations = (CGFloat *)calloc(count, sizeof(CGFloat));
    memcpy(gradient->components, components, count * gradient->perColour * sizeof(CGFloat));
    for (i = 0; i < count; i++)
        gradient->locations[i] = locations != NULL ? locations[i] : (count > 1 ? (CGFloat)i / (count - 1) : 0.0);
    return (CGGradientRef)gradient;
}

CGGradientRef CGGradientCreateWithColors(CGColorSpaceRef space, CFArrayRef colors, const CGFloat locations[])
{
    size_t count = colors != NULL ? (size_t)CFArrayGetCount(colors) : 0;
    CGColorSpaceRef useSpace = space != NULL ? space : CGColorSpaceCreateDeviceRGB();
    size_t perColour = CGColorSpaceGetNumberOfComponents(useSpace) + 1;
    CGFloat *components = (CGFloat *)calloc(count > 0 ? count * perColour : 1, sizeof(CGFloat));
    CGGradientRef gradient;
    size_t i, j;

    for (i = 0; i < count; i++) {
        CGColorRef color = (CGColorRef)CFArrayGetValueAtIndex(colors, i);
        const CGFloat *from = CGColorGetComponents(color);
        size_t have = CGColorGetNumberOfComponents(color);
        for (j = 0; j < perColour; j++)
            components[i * perColour + j] = j < have ? from[j] : 1.0;
    }
    gradient = CGGradientCreateWithColorComponents(useSpace, components, locations, count);
    free(components);
    if (space == NULL)
        CGColorSpaceRelease(useSpace);
    return gradient;
}

void CGGradientRelease(CGGradientRef ref)
{
    CPGradient *gradient = CP_GRADIENT(ref);
    if (gradient == NULL || --gradient->retainCount > 0)
        return;
    CGColorSpaceRelease(gradient->space);
    free(gradient->components);
    free(gradient->locations);
    free(gradient);
}

CGGradientRef CGGradientRetain(CGGradientRef ref)
{
    if (ref != NULL)
        CP_GRADIENT(ref)->retainCount++;
    return ref;
}

CFTypeID CGGradientGetTypeID(void)
{
    return (CFTypeID)0x47524144;    // 'GRAD': only ever compared with itself
}

CGFunctionRef CGGradientGetFunction(CGGradientRef ref)
{
    return ref != NULL ? CPGradientFunction(CP_GRADIENT(ref)) : NULL;
}

void CGContextDrawLinearGradient(CGContextRef context, CGGradientRef ref,
                                 CGPoint start, CGPoint end, CGGradientDrawingOptions options)
{
    CPGradient *gradient = CP_GRADIENT(ref);
    CGFunctionRef function = CPGradientFunction(gradient);
    CGShadingRef shading = CGShadingCreateAxial(gradient->space, start, end, function,
                                                (options & 1) != 0, (options & 2) != 0);
    CGContextDrawShading(context, shading);
    CGShadingRelease(shading);
    CGFunctionRelease(function);
}

void CGContextDrawRadialGradient(CGContextRef context, CGGradientRef ref,
                                 CGPoint startCenter, CGFloat startRadius,
                                 CGPoint endCenter, CGFloat endRadius,
                                 CGGradientDrawingOptions options)
{
    CPGradient *gradient = CP_GRADIENT(ref);
    CGFunctionRef function = CPGradientFunction(gradient);
    CGShadingRef shading = CGShadingCreateRadial(gradient->space, startCenter, startRadius,
                                                 endCenter, endRadius, function,
                                                 (options & 1) != 0, (options & 2) != 0);
    CGContextDrawShading(context, shading);
    CGShadingRelease(shading);
    CGFunctionRelease(function);
}

#pragma mark Drawing

void CGContextBeginTransparencyLayerWithRect(CGContextRef context, CGRect rect, CFDictionaryRef auxiliaryInfo)
{
    // The rect is an optimization: it says where the layer's contents will
    // be. Clipping to it gives the same drawing.
    CGContextSaveGState(context);
    CGContextClipToRect(context, rect);
    CGContextBeginTransparencyLayer(context, auxiliaryInfo);
}

void CGContextDrawTiledImage(CGContextRef context, CGRect rect, CGImageRef image)
{
    CGRect clip = CGContextGetClipBoundingBox(context);
    CGFloat x, y;

    if (CGRectIsEmpty(rect) || CGRectIsEmpty(clip))
        return;
    for (y = CGRectGetMinY(rect); y < CGRectGetMaxY(clip); y += CGRectGetHeight(rect))
        for (x = CGRectGetMinX(rect); x < CGRectGetMaxX(clip); x += CGRectGetWidth(rect))
            CGContextDrawImage(context, CGRectMake(x, y, CGRectGetWidth(rect), CGRectGetHeight(rect)), image);
}

void CGContextShowGlyphsAtPositions(CGContextRef context, const CGGlyph glyphs[],
                                    const CGPoint positions[], size_t count)
{
    size_t i;
    // Positions are in text space, relative to the current text position.
    CGPoint origin = CGContextGetTextPosition(context);
    for (i = 0; i < count; i++) {
        CGContextShowGlyphsAtPoint(context, origin.x + positions[i].x, origin.y + positions[i].y,
                                   &glyphs[i], 1);
    }
    CGContextSetTextPosition(context, origin.x, origin.y);
}

// Subpixel positioning and quantization are Leopard's; Tiger neither does
// nor promises them, and the simple text path asks only so it can stay on it.
void CGContextSetShouldSubpixelPositionFonts(CGContextRef context, bool should) { }
void CGContextSetShouldSubpixelQuantizeFonts(CGContextRef context, bool should) { }
void CGContextSetAllowsFontSubpixelQuantization(CGContextRef context, bool allows) { }
bool CGContextGetAllowsFontSubpixelQuantization(CGContextRef context) { return false; }

void CGContextSetShouldAntialiasFonts(CGContextRef context, bool should)
{
    // Tiger's switch is for smoothing; antialiasing follows the context.
    CGContextSetShouldSmoothFonts(context, should);
}

#pragma mark Paths, fonts, data

CGPathRef CGPathCreateWithRect(CGRect rect, const CGAffineTransform *transform)
{
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, transform, rect);
    return path;
}

#include <dlfcn.h>

// Tiger's own names, looked up at run time: the 10.5 SDK no longer declares
// them, and they live in the same framework either way.
static void *CPQuartzSymbol(const char *name)
{
    static void *image;
    if (image == NULL) {
        image = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                       RTLD_LAZY | RTLD_NOLOAD);
        if (image == NULL)
            image = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                           RTLD_LAZY);
    }
    return image != NULL ? dlsym(image, name) : NULL;
}

typedef CFStringRef (*CPPostScriptName)(CGFontRef);
typedef bool (*CPGlyphsForUnicodes)(CGFontRef, const UniChar[], CGGlyph[], size_t);
typedef bool (*CPGlyphAdvances)(CGFontRef, const CGGlyph[], size_t, int[]);

CFStringRef CGFontCopyFullName(CGFontRef font)
{
    CPPostScriptName copyName = (CPPostScriptName)CPQuartzSymbol("CGFontCopyPostScriptName");
    return (font != NULL && copyName != NULL) ? copyName(font) : NULL;
}

bool CGFontGetGlyphsForUnichars(CGFontRef font, const UniChar characters[], CGGlyph glyphs[], size_t count)
{
    CPGlyphsForUnicodes forUnicodes = (CPGlyphsForUnicodes)CPQuartzSymbol("CGFontGetGlyphsForUnicodes");
    return forUnicodes != NULL ? forUnicodes(font, characters, glyphs, count) : false;
}

bool CGFontGetGlyphAdvancesForStyle(CGFontRef font, const CGAffineTransform *transform, int style,
                                    const CGGlyph glyphs[], size_t count, CGSize advances[])
{
    int *integerAdvances = (int *)calloc(count > 0 ? count : 1, sizeof(int));
    CPGlyphAdvances getAdvances = (CPGlyphAdvances)CPQuartzSymbol("CGFontGetGlyphAdvances");
    bool ok = getAdvances != NULL && getAdvances(font, glyphs, count, integerAdvances);
    size_t i;
    // Advances come back in units of 1/1000 em, as the style-aware call
    // answers them for the font's own size.
    for (i = 0; i < count; i++)
        advances[i] = CGSizeMake(ok ? integerAdvances[i] / 1000.0 : 0.0, 0.0);
    free(integerAdvances);
    return ok;
}

// Tiger's direct-access provider asks for the bytes at an offset where
// Leopard's asks at a position, and names its callbacks differently, so the
// caller's callbacks are wrapped rather than passed through.
typedef struct CPDirectWrapper {
    void *info;
    CGDataProviderDirectCallbacks callbacks;
} CPDirectWrapper;

static const void *CPDirectGetBytePointer(void *info)
{
    CPDirectWrapper *wrapper = (CPDirectWrapper *)info;
    return wrapper->callbacks.getBytePointer != NULL
        ? wrapper->callbacks.getBytePointer(wrapper->info) : NULL;
}

static void CPDirectReleaseBytePointer(void *info, const void *pointer)
{
    CPDirectWrapper *wrapper = (CPDirectWrapper *)info;
    if (wrapper->callbacks.releaseBytePointer != NULL)
        wrapper->callbacks.releaseBytePointer(wrapper->info, pointer);
}

static size_t CPDirectGetBytes(void *info, void *buffer, size_t offset, size_t count)
{
    CPDirectWrapper *wrapper = (CPDirectWrapper *)info;
    return wrapper->callbacks.getBytesAtPosition != NULL
        ? wrapper->callbacks.getBytesAtPosition(wrapper->info, buffer, (off_t)offset, count) : 0;
}

static void CPDirectRelease(void *info)
{
    CPDirectWrapper *wrapper = (CPDirectWrapper *)info;
    if (wrapper->callbacks.releaseInfo != NULL)
        wrapper->callbacks.releaseInfo(wrapper->info);
    free(wrapper);
}

CGDataProviderRef CGDataProviderCreateDirect(void *info, off_t size,
                                             const CGDataProviderDirectCallbacks *callbacks)
{
    static const CGDataProviderDirectAccessCallbacks tigerCallbacks = {
        CPDirectGetBytePointer, CPDirectReleaseBytePointer, CPDirectGetBytes, CPDirectRelease
    };
    CPDirectWrapper *wrapper = (CPDirectWrapper *)calloc(1, sizeof(CPDirectWrapper));

    wrapper->info = info;
    if (callbacks != NULL)
        wrapper->callbacks = *callbacks;
    return CGDataProviderCreateDirectAccess(wrapper, (size_t)size, &tigerCallbacks);
}

// Screenshots of other windows: used for the window snapshot an application
// can ask for, which this browser does not.
CGImageRef CGWindowListCreateImage(CGRect screenBounds, uint32_t listOption,
                                   uint32_t windowID, uint32_t imageOption)
{
    return NULL;
}
