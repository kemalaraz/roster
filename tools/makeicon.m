// makeicon.m — render the app icon at 1024×1024 (native, no Python).
// Design: a dark mallard green-blue Apple-style squircle (superellipse) with a soft drop
// shadow, a profile card (one peeking behind for depth), and a roster (group of three
// avatars) on the front card. Sized to match macOS system icons. Writes a PNG to argv[1].
//
//   clang -fobjc-arc -framework CoreGraphics -framework ImageIO \
//         -framework CoreFoundation -framework CoreServices -o makeicon makeicon.m
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>
#import <math.h>

static const CGFloat S = 1024.0;     // canvas
static const CGFloat HALF = 411.0;   // squircle half-size → 822px content (101px gutter),
                                     // the exact macOS system-icon footprint (verified
                                     // against Notes/Maps/App Store/Reminders/Calculator).
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

// One clean person silhouette: a head circle above a smooth semi-elliptical
// shoulder dome (drawn via a y-scaled semicircle), with a small gap between them.
static void drawPerson(CGContextRef c, CGFloat cx, CGFloat headCY, CGFloat headR,
                       CGFloat baseY, CGFloat sw, CGFloat domeH, CGColorRef col) {
    CGContextSetFillColorWithColor(c, col);
    CGContextAddEllipseInRect(c, CGRectMake(cx - headR, headCY - headR, 2*headR, 2*headR));
    CGContextFillPath(c);
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

// A "roster": a group of three avatars — two lighter figures flanking a larger,
// darker centre figure drawn on top, reading as a team of profiles.
static void addRoster(CGContextRef c, CGFloat cx) {
    CGColorRef side = rgb(0.169, 0.478, 0.400, 1);   // #2B7A66 lighter mallard (behind)
    CGColorRef mid  = rgb(0.102, 0.361, 0.298, 1);   // #1A5C4C dark mallard (front)
    drawPerson(c, cx - 78, 545, 36, 472, 74,  60, side);   // left
    drawPerson(c, cx + 78, 545, 36, 472, 74,  60, side);   // right
    drawPerson(c, cx,      576, 50, 470, 116, 76, mid);    // centre (on top)
}

static void drawCard(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat deg,
                     CGFloat w, CGFloat h, CGFloat alpha) {
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, cx, cy);
    CGContextRotateCTM(c, deg * M_PI / 180.0);
    CGContextSetShadowWithColor(c, CGSizeMake(0, -9), 24, rgb(0.01, 0.10, 0.08, 0.34));
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
    CGContextSetShadowWithColor(c, CGSizeMake(0, -14), 30, rgb(0.01, 0.09, 0.07, 0.32));
    CGContextAddPath(c, squircle);
    CGContextSetFillColorWithColor(c, rgb(0.10, 0.30, 0.25, 1));   // placeholder fill → casts shadow
    CGContextFillPath(c);
    CGContextRestoreGState(c);

    // ── Squircle fill: mallard-green vertical gradient ──────────────────────
    CGContextSaveGState(c);
    CGContextAddPath(c, squircle);
    CGContextClip(c);
    CGFloat locs[2] = {0.0, 1.0};
    CGColorRef gcols[2] = { rgb(0.169, 0.478, 0.400, 1),   // mallard green-blue (top)
                            rgb(0.063, 0.220, 0.184, 1) }; // deep mallard (bottom)
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

    // ── Profile card (with one peeking behind for depth) ─────────────────────
    drawCard(c, cx - 66, 512,  9, 300, 356, 0.50);   // back card peeking
    drawCard(c, cx,      524,  0, 320, 372, 1.00);   // front card

    // ── Roster: a group of three avatars on the front card ───────────────────
    addRoster(c, cx);

    // ── Encode PNG ──────────────────────────────────────────────────────────
    CGImageRef img = CGBitmapContextCreateImage(c);
    CFStringRef path = CFStringCreateWithCString(NULL, out, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, false);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(dst, img, NULL);
    bool ok = CGImageDestinationFinalize(dst);
    return ok ? 0 : 1;
}
