/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// Tiger has CoreText - it is where CoreText started, inside
// ApplicationServices - and most of what a 10.5 engine asks for is there
// under the name it had in 2005. Two things changed on the way to Leopard.
//
// One is names: Copy became Create, Locale became Language. Those are a
// table of old names, below, and nothing more.
//
// The other is the size argument, and it is the reason a Tiger engine used
// to stop on the first styled character. Tiger's CoreText takes a font size
// as a **double**; Leopard's takes CGFloat, which on 32-bit PowerPC is a
// float. On this processor a double argument occupies two of the registers
// that carry arguments and a float occupies one, so a call written against
// Leopard's headers leaves the matrix in the register before the one Tiger
// reads it from - and Tiger reads whatever was there. It crashed inside
// TFont::SetMatrix every time, which looked like Tiger's CoreText being
// broken rather than a disagreement about one argument.
//
// So every call that takes a size is declared here as Tiger declares it and
// called with a double. The engine keeps calling the Leopard shape; these
// stand between.
//
// Where Tiger genuinely cannot do a thing, the stand-in answers what a font
// without that feature answers, which the engine already copes with.

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>

// Tiger's own names for these. They are looked up at run time rather than
// linked: the 10.5 SDK this is built against no longer declares them, and
// the library they live in is the same ApplicationServices either way.
#include <dlfcn.h>

static void *CPTigerSymbol(const char *name)
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

// Tiger's shapes: a size is a double.
typedef CTFontRef (*CPFontWithName)(CFStringRef, double, const CGAffineTransform *);
typedef CTFontRef (*CPFontWithDescriptor)(CTFontDescriptorRef, double, const CGAffineTransform *);
typedef CTFontRef (*CPFontCopyWithAttributes)(CTFontRef, double, const CGAffineTransform *, CTFontDescriptorRef);
typedef CTFontRef (*CPFontWithGraphicsFont)(CGFontRef, double, const CGAffineTransform *, CTFontDescriptorRef);
typedef CTFontRef (*CPFontWithPlatformFont)(ATSFontRef, double, const CGAffineTransform *, CTFontDescriptorRef);
typedef CTFontRef (*CPUIFontForLocaleD)(CTFontUIFontType, double, CFStringRef);
typedef CTFontDescriptorRef (*CPDescriptorWithNameAndSize)(CFStringRef, double);

typedef CTFontDescriptorRef (*CPDescriptorWithAttributes)(CTFontDescriptorRef, CFDictionaryRef);
typedef CTFontDescriptorRef (*CPDescriptorWithFeature)(CTFontDescriptorRef, CFNumberRef, CFNumberRef);
typedef CFArrayRef (*CPMatchingDescriptors)(CTFontDescriptorRef, CFSetRef);
typedef CTFontRef (*CPVariantWithTraits)(CTFontRef, CTFontSymbolicTraits, CTFontSymbolicTraits);
typedef CGFontRef (*CPGraphicsFont)(CTFontRef, CTFontDescriptorRef *);

#pragma mark The calls that take a size

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size, const CGAffineTransform *matrix)
{
    CPFontWithName create = (CPFontWithName)CPTigerSymbol("CTFontCreateWithName");
    return create != NULL ? create(name, (double)size, matrix) : NULL;
}

CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor, CGFloat size,
                                         const CGAffineTransform *matrix)
{
    CPFontWithDescriptor create = (CPFontWithDescriptor)CPTigerSymbol("CTFontCreateWithFontDescriptor");
    if (descriptor == NULL)
        return NULL;        // Leopard answers null; Tiger reads the pointer
    return create != NULL ? create(descriptor, (double)size, matrix) : NULL;
}

CTFontRef CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                         CTFontDescriptorRef attributes)
{
    CPFontCopyWithAttributes copy = (CPFontCopyWithAttributes)CPTigerSymbol("CTFontCreateCopyWithAttributes");
    return copy != NULL ? copy(font, (double)size, matrix, attributes) : NULL;
}

CTFontRef CTFontCreateWithGraphicsFont(CGFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                       CTFontDescriptorRef attributes)
{
    CPFontWithGraphicsFont create = (CPFontWithGraphicsFont)CPTigerSymbol("CTFontCreateWithGraphicsFont");
    return create != NULL ? create(font, (double)size, matrix, attributes) : NULL;
}

CTFontRef CTFontCreateWithPlatformFont(ATSFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                       CTFontDescriptorRef attributes)
{
    CPFontWithPlatformFont create = (CPFontWithPlatformFont)CPTigerSymbol("CTFontCreateWithPlatformFont");
    return create != NULL ? create(font, (double)size, matrix, attributes) : NULL;
}

CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size)
{
    CPDescriptorWithNameAndSize create =
        (CPDescriptorWithNameAndSize)CPTigerSymbol("CTFontDescriptorCreateWithNameAndSize");
    return create != NULL ? create(name, (double)size) : NULL;
}

// Tiger asks for a font table by name - the four characters as a string -
// where Leopard takes the tag as a number. Passing the number crashes
// inside CFStringGetBytes, which is Tiger reading 'cmap' as a pointer.
typedef CFDataRef (*CPCopyTableByName)(CTFontRef, CFStringRef, CTFontTableOptions);

static CFStringRef CPTableName(CTFontTableTag tag)
{
    char name[5];
    name[0] = (char)((tag >> 24) & 0xff);
    name[1] = (char)((tag >> 16) & 0xff);
    name[2] = (char)((tag >> 8) & 0xff);
    name[3] = (char)(tag & 0xff);
    name[4] = '\0';
    return CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
}

CFDataRef CTFontCopyTable(CTFontRef font, CTFontTableTag tag, CTFontTableOptions options)
{
    CPCopyTableByName copy = (CPCopyTableByName)CPTigerSymbol("CTFontCopyTable");
    CFStringRef name;
    CFDataRef table;

    if (copy == NULL || font == NULL)
        return NULL;
    name = CPTableName(tag);
    table = copy(font, name, options);
    CFRelease(name);
    return table;
}

// Glyph metrics. Leopard added an orientation argument to both of these and
// changed what the advances call returns; Tiger draws horizontally only and
// hands back the total as a CGSize. On PowerPC a structure return is passed
// as a hidden first argument, which is why calling Tiger's with Leopard's
// shape put the font one register along and crashed in _CTFontEnsureFontRef.
typedef CGSize (*CPAdvancesTiger)(CTFontRef, const CGGlyph *, CGSize *, CFIndex);
typedef CGRect (*CPBoundsTiger)(CTFontRef, const CGGlyph *, CGRect *, CFIndex);

double CTFontGetAdvancesForGlyphs(CTFontRef font, CTFontOrientation orientation,
                                  const CGGlyph glyphs[], CGSize advances[], CFIndex count)
{
    CPAdvancesTiger original = (CPAdvancesTiger)CPTigerSymbol("CTFontGetAdvancesForGlyphs");
    CGSize total;

    if (original == NULL || font == NULL)
        return 0.0;
    total = original(font, glyphs, advances, count);
    return total.width;     // what Leopard answers
}

CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef font, CTFontOrientation orientation,
                                       const CGGlyph glyphs[], CGRect boundingRects[], CFIndex count)
{
    CPBoundsTiger original = (CPBoundsTiger)CPTigerSymbol("CTFontGetBoundingRectsForGlyphs");
    CGRect empty = { { 0.0f, 0.0f }, { 0.0f, 0.0f } };

    if (original == NULL || font == NULL)
        return empty;
    return original(font, glyphs, boundingRects, count);
}

#pragma mark The calls Leopard renamed

CTFontDescriptorRef CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef descriptor,
                                                             CFDictionaryRef attributes)
{
    CPDescriptorWithAttributes copy = (CPDescriptorWithAttributes)CPTigerSymbol("CTFontDescriptorCopyWithAttributes");
    return copy != NULL ? copy(descriptor, attributes) : NULL;
}

CTFontDescriptorRef CTFontDescriptorCreateCopyWithFeature(CTFontDescriptorRef descriptor,
                                                          CFNumberRef featureTypeIdentifier,
                                                          CFNumberRef featureSelectorIdentifier)
{
    CPDescriptorWithFeature copy = (CPDescriptorWithFeature)CPTigerSymbol("CTFontDescriptorCopyWithFeature");
    return copy != NULL ? copy(descriptor, featureTypeIdentifier, featureSelectorIdentifier) : NULL;
}

CFArrayRef CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef descriptor,
                                                         CFSetRef mandatoryAttributes)
{
    CPMatchingDescriptors copy = (CPMatchingDescriptors)CPTigerSymbol("CTFontDescriptorCopyMatchingFontDescriptors");
    return copy != NULL ? copy(descriptor, mandatoryAttributes) : NULL;
}

// 10.5 answers one best match where Tiger answers the whole list.
CTFontDescriptorRef CTFontDescriptorCreateMatchingFontDescriptor(CTFontDescriptorRef descriptor,
                                                                 CFSetRef mandatoryAttributes)
{
    CFArrayRef matches = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, mandatoryAttributes);
    CTFontDescriptorRef best = NULL;

    if (matches != NULL) {
        if (CFArrayGetCount(matches) > 0)
            best = (CTFontDescriptorRef)CFRetain(CFArrayGetValueAtIndex(matches, 0));
        CFRelease(matches);
    }
    return best;
}

CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType type, CGFloat size, CFStringRef language)
{
    CPUIFontForLocaleD create = (CPUIFontForLocaleD)CPTigerSymbol("CTFontCreateUIFontForLocale");
    return create != NULL ? create(type, (double)size, language) : NULL;
}

CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size,
                                             const CGAffineTransform *matrix,
                                             CTFontSymbolicTraits value, CTFontSymbolicTraits mask)
{
    CTFontRef sized = (size > 0.0 || matrix != NULL)
        ? CTFontCreateCopyWithAttributes(font, size, matrix, NULL) : (CTFontRef)CFRetain(font);
    CPVariantWithTraits makeVariant = (CPVariantWithTraits)CPTigerSymbol("CTFontCreateVariantWithMatchingSymbolicTraits");
    CTFontRef variant = makeVariant != NULL ? makeVariant(sized, value, mask) : NULL;

    if (variant == NULL)
        return sized;       // no such variant: the same font, as 10.5 answers
    CFRelease(sized);
    return variant;
}

Boolean CTFontGetGlyphsForUnichars(CTFontRef font, const UniChar characters[], CGGlyph glyphs[], CFIndex count)
{
    return CTFontGetGlyphsForCharacters(font, characters, glyphs, count);
}

// kCTFontFullNameKey is Leopard's. Built for 10.4 against the 10.5 SDK it
// is a weak import, which means it is simply null here rather than a load
// failure - the trap this whole library has to watch for. The PostScript
// name is what Tiger can give, and it names the same face.
CFStringRef CTFontCopyFullName(CTFontRef font)
{
    typedef CFStringRef (*CPCopyPostScriptName)(CTFontRef);
    CPCopyPostScriptName copyPostScript;

    if (font == NULL)
        return NULL;
    if (&kCTFontFullNameKey != NULL && kCTFontFullNameKey != NULL)
        return CTFontCopyName(font, kCTFontFullNameKey);
    copyPostScript = (CPCopyPostScriptName)CPTigerSymbol("CTFontCopyPostScriptName");
    return copyPostScript != NULL ? copyPostScript(font) : NULL;
}

CFIndex CTFontGetGlyphCount(CTFontRef font)
{
    CPGraphicsFont getFont = (CPGraphicsFont)CPTigerSymbol("CTFontGetGraphicsFont");
    CGFontRef graphicsFont = getFont != NULL ? getFont(font, NULL) : NULL;
    return graphicsFont != NULL ? (CFIndex)CGFontGetNumberOfGlyphs(graphicsFont) : 0;
}

// The tables a font carries. Tiger can copy a table by tag but cannot list
// them, so the tags WebKit looks for are asked for one at a time: an empty
// answer for a font that has none is what it expects either way.
CFArrayRef CTFontCopyAvailableTables(CTFontRef font, CTFontTableOptions options)
{
    static const CTFontTableTag interesting[] = {
        kCTFontTableCmap, kCTFontTableGlyf, kCTFontTableHead, kCTFontTableHhea,
        kCTFontTableHmtx, kCTFontTableKern, kCTFontTableLoca, kCTFontTableMaxp,
        kCTFontTableName, kCTFontTableOS2,  kCTFontTablePost, kCTFontTableCFF,
        kCTFontTableGSUB, kCTFontTableGPOS, kCTFontTableGDEF, kCTFontTableMorx,
        kCTFontTableFeat, kCTFontTableTrak, kCTFontTableVhea, kCTFontTableVmtx
    };
    CFMutableArrayRef tags = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    size_t i;

    for (i = 0; i < sizeof interesting / sizeof interesting[0]; i++) {
        CFDataRef table = CTFontCopyTable(font, interesting[i], options);
        if (table == NULL)
            continue;
        CFRelease(table);
        CFArrayAppendValue(tags, (const void *)(uintptr_t)interesting[i]);
    }
    return tags;
}

// Vertical writing: Tiger's CoreText has no vertical metrics, and the engine
// falls back to horizontal layout when the translations are zero, which is
// what a font without vertical tables gives on 10.5 too.
void CTFontGetVerticalTranslationsForGlyphs(CTFontRef font, const CGGlyph glyphs[],
                                            CGSize translations[], CFIndex count)
{
    CFIndex i;
    for (i = 0; i < count; i++)
        translations[i] = CGSizeMake(0.0, 0.0);
}

CGPathRef CTFontCreatePathForGlyph(CTFontRef font, CGGlyph glyph, const CGAffineTransform *transform)
{
    // ATSUI's glyph outlines are the only source on Tiger, and the engine
    // uses this for SVG text on a path and for text-as-shape effects only;
    // an empty path leaves the text drawn the ordinary way.
    return CGPathCreateMutable();
}

double CTLineGetTrailingWhitespaceWidth(CTLineRef line)
{
    // Used to trim a measured line; zero means "no trailing space", which
    // over-measures by at most one space.
    return 0.0;
}

void CTFrameGetLineOrigins(CTFrameRef frame, CFRange range, CGPoint origins[])
{
    CFIndex i, count = CFRangeMake(0, 0).length;
    CFArrayRef lines = CTFrameGetLines(frame);
    count = lines != NULL ? CFArrayGetCount(lines) : 0;
    if (range.length > 0 && range.length < count)
        count = range.length;
    for (i = 0; i < count; i++)
        origins[i] = CGPointMake(0.0, 0.0);
}

CGSize CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterRef framesetter, CFRange stringRange,
                                                    CFDictionaryRef frameAttributes, CGSize constraints,
                                                    CFRange *fitRange)
{
    if (fitRange != NULL)
        *fitRange = stringRange;
    return constraints;
}

// The typesetter option 10.5 added is a bidi override. Tiger's typesetter
// takes no options; the text still lays out, in the direction the characters
// themselves imply.
CTTypesetterRef CTTypesetterCreateWithAttributedStringAndOptions(CFAttributedStringRef string,
                                                                 CFDictionaryRef options)
{
    return CTTypesetterCreateWithAttributedString(string);
}

const CFStringRef kCTTypesetterOptionForcedEmbeddingLevel = CFSTR("CTTypesetterOptionForcedEmbeddingLevel");
const CFStringRef kCTVerticalFormsAttributeName = CFSTR("CTVerticalForms");

