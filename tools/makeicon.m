// makeicon.m — render the app icon at 1024×1024 (native, no Python).
// Design: a violet→indigo Apple-style squircle (superellipse) with a soft drop
// shadow, a fanned stack of three "profile" cards, and a clean app-agnostic avatar
// on the front card. Sized to match macOS system icons. Writes a PNG to argv[1].
//
//   clang -fobjc-arc -framework CoreGraphics -framework ImageIO \
//         -framework CoreFoundation -framework CoreServices -o makeicon makeicon.m
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>
#import <math.h>

static const CGFloat S = 1024.0;     // canvas
static const CGFloat HALF = 404.0;   // squircle half-size → 808px content (108px gutter),
                                     // matching macOS system icons' footprint.
static const CGFloat NEXP = 5.0;     // superellipse exponent (Apple-like squircle)

static CGColorRef rgb(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    CGFloat c[4] = {r, g, b, a};
    static CGColorSpaceRef cs; if (!cs) cs = CGColorSpaceCreateDeviceRGB();
    return CGColorCreate(cs, c);
}
static CGFloat sgn(CGFloat x) { return (x > 0) - (x < 0); }

// Apple-style squircle (superellipse): |x/a|^n + |y/a|^n = 1.
static CGPathRef squirclePath(CGFloat cx, CGFloat cy, CGFloat a) {
    CGMutablePathRef p = CGPathCreateMutable();
    const int STEPS = 240;
    for (int i = 0; i <= STEPS; i++) {
        double t = 2.0 * M_PI * i / STEPS;
        double ct = cos(t), st = sin(t);
        double x = cx + a * sgn(ct) * pow(fabs(ct), 2.0 / NEXP);
        double y = cy + a * sgn(st) * pow(fabs(st), 2.0 / NEXP);
        if (i == 0) CGPathMoveToPoint(p, NULL, x, y);
        else        CGPathAddLineToPoint(p, NULL, x, y);
    }
    CGPathCloseSubpath(p);
    return p;
}

static CGPathRef roundedRect(CGRect r, CGFloat rad) {
    return CGPathCreateWithRoundedRect(r, rad, rad, NULL);
}

// A clean person silhouette: a head circle above a smooth semi-elliptical shoulder
// dome, with a small gap so they read as one tidy glyph (no notch).
static void addAvatar(CGContextRef c, CGFloat cx, CGColorRef col) {
    CGContextSetFillColorWithColor(c, col);
    // Head.
    CGFloat headR = 60, headCY = 576;
    CGContextAddEllipseInRect(c, CGRectMake(cx - headR, headCY - headR, 2*headR, 2*headR));
    CGContextFillPath(c);
    // Shoulder dome — top half of a wide ellipse, drawn via a y-scaled semicircle.
    CGFloat baseY = 432, sw = 134, domeH = 78;   // dome top ≈ 510, gap to head ≈ 6
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, cx, baseY);
    CGContextScaleCTM(c, 1.0, domeH / sw);
    CGMutablePathRef dome = CGPathCreateMutable();
    CGPathMoveToPoint(dome, NULL, sw, 0);
    CGPathAddArc(dome, NULL, 0, 0, sw, 0, M_PI, false);  // arc over the top
    CGPathCloseSubpath(dome);
    CGContextAddPath(c, dome);
    CGContextFillPath(c);
    CGPathRelease(dome);
    CGContextRestoreGState(c);
}

static void drawCard(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat deg,
                     CGFloat w, CGFloat h, CGFloat alpha) {
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, cx, cy);
    CGContextRotateCTM(c, deg * M_PI / 180.0);
    CGContextSetShadowWithColor(c, CGSizeMake(0, -9), 24, rgb(0.10, 0.05, 0.22, 0.32));
    CGPathRef card = roundedRect(CGRectMake(-w/2, -h/2, w, h), 54);
    CGContextSetFillColorWithColor(c, rgb(0.980, 0.975, 1.000, alpha));
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

    CGFloat cx = S/2, cy = S/2;
    CGPathRef squircle = squirclePath(cx, cy, HALF);

    // ── Soft contact shadow under the squircle (like system icons) ──────────
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, -14), 30, rgb(0.06, 0.03, 0.18, 0.30));
    CGContextAddPath(c, squircle);
    CGContextSetFillColorWithColor(c, rgb(0.4, 0.3, 0.7, 1));   // placeholder fill → casts shadow
    CGContextFillPath(c);
    CGContextRestoreGState(c);

    // ── Squircle fill: violet→indigo vertical gradient ──────────────────────
    CGContextSaveGState(c);
    CGContextAddPath(c, squircle);
    CGContextClip(c);
    CGFloat locs[2] = {0.0, 1.0};
    CGColorRef gcols[2] = { rgb(0.553, 0.420, 0.945, 1),   // bright violet (top)
                            rgb(0.270, 0.170, 0.500, 1) }; // deep indigo (bottom)
    CFArrayRef arr = CFArrayCreate(NULL, (const void **)gcols, 2, &kCFTypeArrayCallBacks);
    CGGradientRef grad = CGGradientCreateWithColors(cs, arr, locs);
    CGContextDrawLinearGradient(c, grad, CGPointMake(0, S), CGPointMake(0, 0), 0);
    // Soft top highlight.
    CGColorRef hcols[2] = { rgb(1, 1, 1, 0.15), rgb(1, 1, 1, 0) };
    CFArrayRef harr = CFArrayCreate(NULL, (const void **)hcols, 2, &kCFTypeArrayCallBacks);
    CGGradientRef hg = CGGradientCreateWithColors(cs, harr, locs);
    CGContextDrawRadialGradient(c, hg, CGPointMake(cx, S*0.72), 0,
                                CGPointMake(cx, S*0.72), S*0.44, 0);
    CGContextRestoreGState(c);

    // ── Fanned stack of three profile cards ─────────────────────────────────
    CGFloat cw = 286, ch = 364;
    drawCard(c, cx - 112, 506,  12, cw, ch, 0.62);   // back-left
    drawCard(c, cx + 112, 506, -12, cw, ch, 0.80);   // back-right
    drawCard(c, cx,       524,   0, cw, ch, 1.00);   // front

    // ── Avatar on the front card ────────────────────────────────────────────
    addAvatar(c, cx, rgb(0.486, 0.361, 0.902, 1));   // #7C5CE6 accent violet

    // ── Encode PNG ──────────────────────────────────────────────────────────
    CGImageRef img = CGBitmapContextCreateImage(c);
    CFStringRef path = CFStringCreateWithCString(NULL, out, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, false);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(dst, img, NULL);
    bool ok = CGImageDestinationFinalize(dst);
    return ok ? 0 : 1;
}
