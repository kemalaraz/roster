// Picker.m — a small, styled terminal picker (raw-mode TUI) for choosing a profile.
#import "Picker.h"
#import "Models.h"
#import <termios.h>
#import <unistd.h>
#import <fcntl.h>

// ── ANSI helpers ─────────────────────────────────────────────────────────────
#define ESC      "\x1b"
#define RESET    ESC "[0m"
#define BOLD     ESC "[1m"
#define DIM      ESC "[2m"
#define GREEN    ESC "[38;2;46;138;112m"   // mallard green accent
#define CREAM    ESC "[38;2;240;236;232m"
#define GREENBG  ESC "[48;2;30;87;70m"     // mallard highlight bar
#define WHITEFG  ESC "[38;2;248;245;242m"
#define ALTON    ESC "[?1049h" ESC "[?25l" // alt screen + hide cursor
#define ALTOFF   ESC "[?25h" ESC "[?1049l" // show cursor + leave alt screen
#define CLEAR    ESC "[H" ESC "[2J"

enum { K_UP, K_DOWN, K_ENTER, K_ESC, K_DIGIT, K_OTHER };

static void wr(int fd, NSString *s) {
    const char *b = s.UTF8String; write(fd, b, strlen(b));
}

static int readKey(int fd, int *digit) {
    unsigned char ch;
    if (read(fd, &ch, 1) != 1) return K_ESC;
    if (ch == '\r' || ch == '\n') return K_ENTER;
    if (ch == 'q')               return K_ESC;
    if (ch == 'k')               return K_UP;
    if (ch == 'j')               return K_DOWN;
    if (ch >= '0' && ch <= '9') { *digit = ch - '0'; return K_DIGIT; }
    if (ch == 0x1b) {
        // Could be a bare ESC or an arrow sequence (ESC [ A/B). Read the rest with
        // a short timeout so a lone ESC doesn't block.
        struct termios t; tcgetattr(fd, &t);
        cc_t vmin = t.c_cc[VMIN], vtime = t.c_cc[VTIME];
        t.c_cc[VMIN] = 0; t.c_cc[VTIME] = 1; tcsetattr(fd, TCSANOW, &t);
        unsigned char seq[2]; long n = read(fd, seq, 2);
        t.c_cc[VMIN] = vmin; t.c_cc[VTIME] = vtime; tcsetattr(fd, TCSANOW, &t);
        if (n >= 2 && seq[0] == '[') { if (seq[1] == 'A') return K_UP; if (seq[1] == 'B') return K_DOWN; }
        return K_ESC;
    }
    return K_OTHER;
}

// One menu row: a full-width mallard highlight bar when selected, plain otherwise.
static NSString *row(NSString *emoji, NSString *name, BOOL selected, BOOL dim) {
    const int W = 30;
    NSMutableString *c = [NSMutableString stringWithFormat:@" %@  %@", emoji, name];
    while ((int)c.length < W) [c appendString:@" "];
    if (selected)
        return [NSString stringWithFormat:@"   %s%s%s%@%s\r\n", GREENBG, WHITEFG, BOLD, c, RESET];
    return [NSString stringWithFormat:@"   %s%@%s\r\n", dim ? DIM : CREAM, c, RESET];
}

static void draw(int fd, NSArray<Profile *> *profs, NSInteger sel, NSString *tool) {
    NSMutableString *s = [NSMutableString stringWithUTF8String:CLEAR];
    [s appendString:@"\r\n"];
    [s appendFormat:@"   %s%s🐿  Roster%s   %schoose a profile for %@%s\r\n\r\n",
        BOLD, CREAM, RESET, DIM, tool, RESET];
    NSInteger i = 0;
    for (Profile *p in profs) {
        [s appendString:row(p.emoji ?: @"👤", p.displayName, i == sel, NO)];
        i++;
    }
    BOOL defOn = (sel == (NSInteger)profs.count);
    [s appendString:row(@"·", @"Default — global ~/.claude", defOn, YES)];
    [s appendFormat:@"\r\n   %s↑ ↓  move    ⏎  open    esc  cancel    0–9  jump%s\r\n", DIM, RESET];
    wr(fd, s);
}

// Config dir for the chosen profile + tool (created if needed).
static NSString *configDir(Profile *p, NSString *tool) {
    NSString *dir = [tool isEqualToString:@"codex"]
        ? [[p profileDir] stringByAppendingPathComponent:@"codex"]
        : [p codeConfigDir];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
        withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

int RunPicker(NSString *tool) {
    ProfileStore *store = [ProfileStore new];
    NSArray<Profile *> *profs = store.profiles;
    if (profs.count == 0) { return 0; }   // nothing to pick → caller runs default

    NSString *lastPath = [[Paths profilesDir]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"last-%@", tool]];
    NSString *last = [[NSString stringWithContentsOfFile:lastPath encoding:NSUTF8StringEncoding error:nil]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger sel = 0;
    if (last.length) {
        if ([last isEqualToString:@"default"]) sel = profs.count;
        else for (NSInteger i = 0; i < (NSInteger)profs.count; i++)
            if ([[profs[i] slug] isEqualToString:last]) { sel = i; break; }
    }

    int fd = open("/dev/tty", O_RDWR);
    if (fd < 0) return 0;   // no controlling terminal → caller runs default
    struct termios old, raw; tcgetattr(fd, &old); raw = old; cfmakeraw(&raw);
    tcsetattr(fd, TCSANOW, &raw);
    wr(fd, @ALTON);

    NSInteger n = profs.count + 1;   // + Default
    BOOL cancelled = NO;
    for (;;) {
        draw(fd, profs, sel, tool);
        int dg = -1, k = readKey(fd, &dg);
        if (k == K_UP)        sel = (sel - 1 + n) % n;
        else if (k == K_DOWN) sel = (sel + 1) % n;
        else if (k == K_DIGIT) {
            if (dg == 0) { sel = profs.count; break; }
            if (dg >= 1 && dg <= (NSInteger)profs.count) { sel = dg - 1; break; }
        }
        else if (k == K_ENTER) break;
        else if (k == K_ESC) { cancelled = YES; break; }
    }

    wr(fd, @ALTOFF);
    tcsetattr(fd, TCSANOW, &old);
    close(fd);

    if (cancelled) return 130;                     // non-zero → caller opens nothing
    if (sel == (NSInteger)profs.count) {           // Default
        [@"default" writeToFile:lastPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return 0;
    }
    Profile *chosen = profs[sel];
    [[chosen slug] writeToFile:lastPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    fprintf(stdout, "%s\n", configDir(chosen, tool).UTF8String);
    return 0;
}
