// Spike C.1 of docs/ENGINE_PLAN.md: do the 2.52 dependencies actually work
// together on the target, or only build?
//
// The dependency phase produced twelve archives that the linker accepted and
// otool called ppc750. That is not the same as a working text stack. This
// walks the whole path WebCore's font code takes -- fontconfig finds a face,
// FreeType opens it, HarfBuzz shapes a string, Cairo renders the glyphs and
// writes a PNG -- and it runs on the machine, where the questions that a
// cross build cannot answer live:
//
//  - Can fontconfig see any fonts at all? It was configured with Mac OS X's
//    font directories, but its cache is built on the target and Tiger's
//    /System/Library/Fonts is a different set from Leopard's.
//  - Do HarfBuzz and ICU agree at runtime? harfbuzz-icu is four kilobytes of
//    glue over an ICU built separately, by a different script, months apart.
//  - Does any of this survive one process with one C++ runtime? Cairo and
//    FreeType are C, HarfBuzz and ICU are C++, and mixing runtimes is the
//    fault this port has been bitten by twice.
//
// Built by scripts/toolchain/build-spike-c.sh. Prints one line per stage and
// a count; exit status is the number of failures.
#include <cairo.h>
#include <cairo-ft.h>
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb.h>
#include <hb-ft.h>
#include <hb-icu.h>
#include <stdio.h>
#include <string.h>
#include <unicode/uversion.h>

static int failures = 0;

static void check(const char *what, int ok, const char *detail)
{
    printf("  %-30s %-4s %s\n", what, ok ? "ok" : "FAIL", detail ? detail : "");
    if (!ok)
        failures++;
}

// The string is deliberately not plain ASCII: "AWAV fi 1/2 Wave" with a
// kerning pair, a standard ligature and a fraction, so that a shaper that
// silently does nothing looks different from one that works.
static const char *kText = "AWAV fi \xc2\xbd Wave";

int main(void)
{
    char detail[512];

    printf("spike C.1: the 2.52 text stack, on the target\n");
    printf("  freetype %d.%d.%d  cairo %s  harfbuzz %s  icu %s\n",
           FREETYPE_MAJOR, FREETYPE_MINOR, FREETYPE_PATCH,
           cairo_version_string(), hb_version_string(), U_ICU_VERSION);

    // 1. fontconfig. The interesting failure is an empty font set, which
    //    happens when the cache has never been built or the directories
    //    compiled in do not exist on this system.
    FcConfig *fc = FcInitLoadConfigAndFonts();
    check("FcInitLoadConfigAndFonts", fc != NULL, NULL);
    if (!fc)
        return failures;

    FcFontSet *all = FcConfigGetFonts(fc, FcSetSystem);
    snprintf(detail, sizeof detail, "%d fonts", all ? all->nfont : 0);
    check("fontconfig sees fonts", all && all->nfont > 0, detail);

    // The three generic families WebCore resolves for every page that does
    // not name a font. Mac OS X ships no fontconfig aliases for them, so
    // what comes back is whatever the scan happened to find first, which on
    // a stock system is a Japanese face. Each is reported by name, because
    // "it matched something" is not the question - the question is whether
    // it matched something a reader would recognise as that kind of type.
    static const char *kGenerics[] = { "serif", "sans-serif", "monospace" };
    FcPattern *matched = NULL;
    unsigned int g;
    for (g = 0; g < sizeof kGenerics / sizeof kGenerics[0]; g++) {
        FcPattern *p = FcNameParse((const FcChar8 *)kGenerics[g]);
        FcConfigSubstitute(fc, p, FcMatchPattern);
        FcDefaultSubstitute(p);
        FcResult r;
        FcPattern *m = FcFontMatch(fc, p, &r);
        FcChar8 *fam = NULL;
        if (m)
            FcPatternGetString(m, FC_FAMILY, 0, &fam);
        snprintf(detail, sizeof detail, "%-11s -> %s",
                 kGenerics[g], fam ? (const char *)fam : "(none)");
        check("generic family resolves", m != NULL && r == FcResultMatch, detail);
        // The serif match is the one carried forward and rendered.
        if (g == 0)
            matched = m;
        else if (m)
            FcPatternDestroy(m);
        FcPatternDestroy(p);
    }
    if (!matched)
        return failures;

    FcChar8 *file = NULL;
    int index = 0;
    FcPatternGetString(matched, FC_FILE, 0, &file);
    FcPatternGetInteger(matched, FC_INDEX, 0, &index);
    snprintf(detail, sizeof detail, "%s [%d]", file ? (const char *)file : "(none)", index);
    check("matched face has a file", file != NULL, detail);
    if (!file)
        return failures;

    // 2. FreeType opens it. A Mac font is very often a .dfont or a TrueType
    //    collection, so the face index from fontconfig matters.
    FT_Library ft;
    check("FT_Init_FreeType", FT_Init_FreeType(&ft) == 0, NULL);
    FT_Face face = NULL;
    FT_Error fte = FT_New_Face(ft, (const char *)file, index, &face);
    snprintf(detail, sizeof detail, "error %d", fte);
    check("FT_New_Face", fte == 0 && face != NULL, fte ? detail : NULL);
    if (fte || !face)
        return failures;
    snprintf(detail, sizeof detail, "%s %s, %ld glyphs",
             face->family_name ? face->family_name : "?",
             face->style_name ? face->style_name : "?",
             (long)face->num_glyphs);
    check("face is usable", face->num_glyphs > 0, detail);
    FT_Set_Char_Size(face, 0, 32 * 64, 72, 72);

    // 3. HarfBuzz shapes. A shaper that is not working returns one glyph per
    //    byte with zero advances, so both are checked.
    hb_font_t *hbfont = hb_ft_font_create_referenced(face);
    check("hb_ft_font_create", hbfont != NULL, NULL);
    hb_buffer_t *buf = hb_buffer_create();
    // Explicitly ICU's Unicode functions, not HarfBuzz's built-in ones.
    // harfbuzz-icu is four kilobytes of glue over an ICU that was built by a
    // different script months earlier, and this is the call that makes the
    // linker prove the two agree.
    hb_unicode_funcs_t *ufuncs = hb_icu_get_unicode_funcs();
    check("hb_icu_get_unicode_funcs", ufuncs != NULL, NULL);
    hb_buffer_set_unicode_funcs(buf, ufuncs);
    hb_buffer_add_utf8(buf, kText, -1, 0, -1);
    hb_buffer_guess_segment_properties(buf);
    hb_shape(hbfont, buf, NULL, 0);

    unsigned int n = hb_buffer_get_length(buf);
    hb_glyph_info_t *info = hb_buffer_get_glyph_infos(buf, NULL);
    hb_glyph_position_t *pos = hb_buffer_get_glyph_positions(buf, NULL);
    int advance = 0, notdef = 0;
    unsigned int i;
    for (i = 0; i < n; i++) {
        advance += pos[i].x_advance;
        if (info[i].codepoint == 0)
            notdef++;
    }
    snprintf(detail, sizeof detail, "%u glyphs, %d/64 px wide, %d notdef",
             n, advance, notdef);
    check("hb_shape", n > 0 && advance > 0, detail);
    // Shaping fewer glyphs than input characters means a ligature was formed,
    // which is the one thing here that proves the shaper read the font's
    // tables rather than mapping characters one to one.
    snprintf(detail, sizeof detail, "%u glyphs for %u characters",
             n, (unsigned)strlen(kText) - 1 /* the fraction is two bytes */);
    check("shaper used font tables", n < (unsigned)strlen(kText) - 1, detail);

    // 4. Cairo renders them, through the same FT_Face. This is where a
    //    mismatched freetype would show up: cairo-ft holds the face itself.
    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 420, 60);
    cairo_t *cr = cairo_create(surf);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_paint(cr);
    cairo_set_source_rgb(cr, 0, 0, 0);

    cairo_font_face_t *cff = cairo_ft_font_face_create_for_ft_face(face, 0);
    check("cairo_ft_font_face_create", cairo_font_face_status(cff) == CAIRO_STATUS_SUCCESS,
          cairo_status_to_string(cairo_font_face_status(cff)));
    cairo_set_font_face(cr, cff);
    cairo_set_font_size(cr, 32);

    cairo_glyph_t *glyphs = cairo_glyph_allocate(n);
    double x = 8, y = 42;
    for (i = 0; i < n; i++) {
        glyphs[i].index = info[i].codepoint;
        glyphs[i].x = x + pos[i].x_offset / 64.0;
        glyphs[i].y = y - pos[i].y_offset / 64.0;
        x += pos[i].x_advance / 64.0;
    }
    cairo_show_glyphs(cr, glyphs, n);
    check("cairo_show_glyphs", cairo_status(cr) == CAIRO_STATUS_SUCCESS,
          cairo_status_to_string(cairo_status(cr)));

    // Count non-white pixels. A text stack can complete every call above and
    // still draw nothing at all, which is what a broken rasterizer looks
    // like and what no status code reports.
    cairo_surface_flush(surf);
    unsigned char *data = cairo_image_surface_get_data(surf);
    int stride = cairo_image_surface_get_stride(surf);
    int w = cairo_image_surface_get_width(surf);
    int h = cairo_image_surface_get_height(surf);
    long inked = 0;
    int row, col;
    for (row = 0; row < h; row++) {
        uint32_t *p = (uint32_t *)(data + row * stride);
        for (col = 0; col < w; col++)
            if ((p[col] & 0x00ffffff) != 0x00ffffff)
                inked++;
    }
    snprintf(detail, sizeof detail, "%ld of %d pixels", inked, w * h);
    check("glyphs reached the surface", inked > 200, detail);

    cairo_status_t png = cairo_surface_write_to_png(surf, "spike-c-text.png");
    check("write_to_png", png == CAIRO_STATUS_SUCCESS, cairo_status_to_string(png));

    cairo_glyph_free(glyphs);
    cairo_font_face_destroy(cff);
    cairo_destroy(cr);
    cairo_surface_destroy(surf);
    hb_buffer_destroy(buf);
    hb_font_destroy(hbfont);
    FT_Done_Face(face);
    FT_Done_FreeType(ft);
    FcPatternDestroy(matched);

    printf("  %s\n", failures ? "FAILURES" : "all stages passed");
    return failures;
}
