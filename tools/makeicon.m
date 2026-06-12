// makeicon.m — render the app icon at 1024×1024 (native, no Python).
// Design: a violet→indigo squircle (gradient) with a fanned stack of three
// "profile" cards and an app-agnostic avatar glyph on the front card — a profile
// manager for any AI app, not tied to one brand. Writes a PNG to argv[1].
//
//   clang -fobjc-arc -framework CoreGraphics -framework ImageIO \
//         -framework CoreFoundation -framework CoreServices -o makeicon makeicon.m
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>

static const CGFloat S = 1024.0;           // canvas
static const CGFloat PAD = 100.0;          // gutter → 824×824 content
static const CGFloat R_SQUIRCLE = 185.0;   // macOS squircle corner radius

static CGColorRef rgb(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    CGFloat c[4] = {r, g, b, a};
    static CGColorSpaceRef cs; if (!cs) cs = CGColorSpaceCreateDeviceRGB();
    return CGColorCreate(cs, c);
}

// Rounded-rect path.
static CGPathRef roundedRect(CGRect r, CGFloat rad) {
    return CGPathCreateWithRoundedRect(r, rad, rad, NULL);
}

// An app-agnostic avatar glyph (head + shoulders) centered on the front card.
static void addAvatar(CGContextRef c, CGFloat cx, CGFloat cy, CGColorRef col) {
    CGContextSetFillColorWithColor(c, col);
    // Shoulders — top half of a disc, the curve facing up toward the head.
    CGMutablePathRef sh = CGPathCreateMutable();
    CGPathAddArc(sh, NULL, cx, cy - 70, 140, 0, M_PI, false);
    CGPathCloseSubpath(sh);
    CGContextAddPath(c, sh);
    CGContextFillPath(c);
    CGPathRelease(sh);
    // Head — circle above, overlapping the shoulders into one silhouette.
    CGFloat hR = 62;
    CGContextAddEllipseInRect(c, CGRectMake(cx - hR, (cy + 51) - hR, 2*hR, 2*hR));
    CGContextFillPath(c);
}

// Draw one cream card centered at (cx,cy), rotated `deg`, with a soft shadow.
static void drawCard(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat deg,
                     CGFloat w, CGFloat h, CGFloat alpha) {
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, cx, cy);
    CGContextRotateCTM(c, deg * M_PI / 180.0);
    CGContextSetShadowWithColor(c, CGSizeMake(0, -10), 26, rgb(0.10, 0.05, 0.22, 0.35));
    CGPathRef card = roundedRect(CGRectMake(-w/2, -h/2, w, h), 58);
    CGContextSetFillColorWithColor(c, rgb(0.980, 0.975, 1.000, alpha));  // cool white (bg bleeds → lavender)
    CGContextAddPath(c, card);
    CGContextFillPath(c);
    CGPathRelease(card);
    CGContextRestoreGState(c);
}

int main(int argc, const char *argv[]) {
    const char *out = argc > 1 ? argv[1] : "/tmp/icon-1024.png";
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, (size_t)S, (size_t)S, 8, 0, cs,
                        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

    // ── Squircle background with a vertical coral gradient ──────────────────
    CGRect sq = CGRectMake(PAD, PAD, S - 2*PAD, S - 2*PAD);
    CGPathRef squircle = roundedRect(sq, R_SQUIRCLE);
    CGContextSaveGState(c);
    CGContextAddPath(c, squircle);
    CGContextClip(c);
    CGFloat locs[2] = {0.0, 1.0};
    CGColorRef gcols[2] = { rgb(0.553, 0.420, 0.945, 1),   // bright violet (top)
                            rgb(0.270, 0.170, 0.500, 1) }; // deep indigo (bottom)
    CFArrayRef arr = CFArrayCreate(NULL, (const void **)gcols, 2, &kCFTypeArrayCallBacks);
    CGGradientRef grad = CGGradientCreateWithColors(cs, arr, locs);
    CGContextDrawLinearGradient(c, grad, CGPointMake(0, S), CGPointMake(0, 0), 0);
    // Soft highlight glow near the top.
    CGColorRef hcols[2] = { rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0) };
    CFArrayRef harr = CFArrayCreate(NULL, (const void **)hcols, 2, &kCFTypeArrayCallBacks);
    CGGradientRef hg = CGGradientCreateWithColors(cs, harr, locs);
    CGContextDrawRadialGradient(c, hg, CGPointMake(S/2, S*0.74), 0,
                                CGPointMake(S/2, S*0.74), S*0.46, 0);
    CGContextRestoreGState(c);

    // ── Fanned stack of three profile cards ─────────────────────────────────
    CGFloat cw = 300, ch = 384;
    drawCard(c, 512 - 118, 506,  12, cw, ch, 0.62);   // back-left
    drawCard(c, 512 + 118, 506, -12, cw, ch, 0.80);   // back-right
    drawCard(c, 512,       524,   0, cw, ch, 1.00);   // front

    // ── Violet avatar glyph on the front card ────────────────────────────────
    addAvatar(c, 512, 520, rgb(0.486, 0.361, 0.902, 1));   // #7C5CE6 accent violet

    // ── Encode PNG ──────────────────────────────────────────────────────────
    CGImageRef img = CGBitmapContextCreateImage(c);
    CFStringRef path = CFStringCreateWithCString(NULL, out, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, false);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(dst, img, NULL);
    bool ok = CGImageDestinationFinalize(dst);
    return ok ? 0 : 1;
}
