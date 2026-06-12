// makeicon.m — render the Claude Profiles app icon at 1024×1024 (native, no Python).
// Design: a Claude-coral squircle (gradient) with a fanned stack of three cream
// "profile" cards and a coral AI-sparkle on the front card. Writes a PNG to argv[1].
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

// A 4-point AI "sparkle" (concave star) centered at (cx,cy), tip radius R.
static void addSparkle(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat R) {
    CGFloat ri = R * 0.34;               // inner valley radius
    CGFloat d  = ri * 0.70710678;        // diagonal component
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, cx,       cy + R);   // top tip
    CGPathAddLineToPoint(p, NULL, cx + d, cy + d);
    CGPathAddLineToPoint(p, NULL, cx + R, cy);      // right tip
    CGPathAddLineToPoint(p, NULL, cx + d, cy - d);
    CGPathAddLineToPoint(p, NULL, cx,     cy - R);  // bottom tip
    CGPathAddLineToPoint(p, NULL, cx - d, cy - d);
    CGPathAddLineToPoint(p, NULL, cx - R, cy);      // left tip
    CGPathAddLineToPoint(p, NULL, cx - d, cy + d);
    CGPathCloseSubpath(p);
    CGContextAddPath(c, p);
    CGContextFillPath(c);
    CGPathRelease(p);
}

// Draw one cream card centered at (cx,cy), rotated `deg`, with a soft shadow.
static void drawCard(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat deg,
                     CGFloat w, CGFloat h, CGFloat alpha) {
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, cx, cy);
    CGContextRotateCTM(c, deg * M_PI / 180.0);
    CGContextSetShadowWithColor(c, CGSizeMake(0, -10), 26, rgb(0.20, 0.07, 0.03, 0.33));
    CGPathRef card = roundedRect(CGRectMake(-w/2, -h/2, w, h), 58);
    CGContextSetFillColorWithColor(c, rgb(0.972, 0.957, 0.930, alpha));  // warm cream
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
    CGColorRef gcols[2] = { rgb(0.910, 0.553, 0.408, 1),   // lighter coral (top)
                            rgb(0.776, 0.357, 0.231, 1) }; // deep terracotta (bottom)
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

    // ── Coral AI-sparkle on the front card ──────────────────────────────────
    CGContextSetFillColorWithColor(c, rgb(0.812, 0.396, 0.267, 1));   // Claude coral
    addSparkle(c, 512, 524, 96);
    CGContextSetFillColorWithColor(c, rgb(0.812, 0.396, 0.267, 0.85));
    addSparkle(c, 512 + 96, 524 + 118, 34);   // small accent sparkle

    // ── Encode PNG ──────────────────────────────────────────────────────────
    CGImageRef img = CGBitmapContextCreateImage(c);
    CFStringRef path = CFStringCreateWithCString(NULL, out, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, false);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(dst, img, NULL);
    bool ok = CGImageDestinationFinalize(dst);
    return ok ? 0 : 1;
}
