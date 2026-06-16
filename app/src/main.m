// main.m — entry point. With no recognised args, launches the GUI. With CLI
// flags it runs headless (also used by the auto-sync LaunchAgent: --sync).
#import <Foundation/Foundation.h>
#import <unistd.h>
#import "Models.h"
#import "Managers.h"
#import "UI.h"
#import "Picker.h"

static void pout(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fprintf(stdout, "%s\n", s.UTF8String);
}
static void perr(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fprintf(stderr, "%s\n", s.UTF8String);
}

static int cliList(void) {
    ProfileStore *store = [ProfileStore new];
    DesktopManager *dm = [DesktopManager new];
    if (store.profiles.count == 0) { pout(@"No profiles yet."); return 0; }
    pout(@"  %-14s %-16s %-8s %-6s %-6s", "PROFILE", "DISPLAY", "APP", "DESKTOP", "CODE");
    pout(@"  ─────────────────────────────────────────────────────────");
    for (Profile *p in store.profiles) {
        pout(@"  %-14s %@ %-12s %-8s %-6s %-6s",
             p.name.UTF8String, p.emoji, p.displayName.UTF8String,
             [p app].displayName.UTF8String,
             [p isDesktopInstalled] ? "✓" : "·",
             [p isCodeInitialized] ? "✓" : "·");
    }
    // Update hints
    for (AppDescriptor *app in [AppDescriptor available]) {
        NSArray *pending = [dm updateAvailableForApp:app];
        if (pending) pout(@"\n⚠️  %@ updated: v%@ → v%@. Run with --sync",
                           app.displayName, pending[0], pending[1]);
    }
    return 0;
}

static int cliSetup(NSString *name, BOOL force) {
    ProfileStore *store = [ProfileStore new];
    Profile *p = [store get:name];
    if (!p) { perr(@"Profile '%@' not found", name); return 1; }
    DesktopManager *dm = [DesktopManager new];
    pout(@"Setting up Desktop app for '%@' …", p.displayName);
    NSError *err = nil;
    NSString *path = [dm setup:p force:force error:&err];
    if (!path) { perr(@"✗ %@", err.localizedDescription); return 1; }
    pout(@"✓ App ready: %@", path);
    return 0;
}

static int cliLaunch(NSString *name) {
    ProfileStore *store = [ProfileStore new];
    Profile *p = [store get:name];
    if (!p) { perr(@"Profile '%@' not found", name); return 1; }
    DesktopManager *dm = [DesktopManager new];
    NSError *err = nil;
    if (![dm launch:p error:&err]) { perr(@"✗ %@", err.localizedDescription); return 1; }
    pout(@"✓ Launched %@", [p appDisplayName]);
    return 0;
}

static int cliCode(NSString *name) {
    ProfileStore *store = [ProfileStore new];
    Profile *p = [store get:name];
    if (!p) { perr(@"Profile '%@' not found", name); return 1; }
    CodeManager *cm = [CodeManager new];
    NSError *err = nil;
    if (![cm launch:p error:&err]) { perr(@"✗ %@", err.localizedDescription); return 1; }
    pout(@"✓ Opened Claude Code for %@", p.displayName);
    return 0;
}

static int cliSync(void) {
    DesktopManager *dm = [DesktopManager new];
    BOOL did = NO;
    for (AppDescriptor *app in [AppDescriptor available]) {
        NSArray *pending = [dm updateAvailableForApp:app];
        NSString *src = [app sourceVersion];
        // Sync if an update is pending OR we've never recorded a version.
        if (pending || ![dm syncedVersionForApp:app]) {
            pout(@"Syncing %@ profiles → v%@ …", app.displayName, src ?: @"?");
            [dm syncAllInstalledForApp:app];
            did = YES;
        }
    }
    pout(did ? @"✓ Sync complete" : @"Nothing to sync.");
    return 0;
}

static int cliDelete(NSString *name) {
    ProfileStore *store = [ProfileStore new];
    if (![store delete:name keepData:NO]) { perr(@"Profile '%@' not found", name); return 1; }
    pout(@"✓ Deleted '%@'", name);
    return 0;
}

static int cliCreate(NSString *name, NSString *emoji, NSString *appID) {
    ProfileStore *store = [ProfileStore new];
    NSError *err = nil;
    Profile *p = [store create:name displayName:nil emoji:(emoji ?: @"👤")
                         color:@"#0066CC" appID:(appID ?: @"claude") error:&err];
    if (!p) { perr(@"✗ %@", err.localizedDescription); return 1; }
    pout(@"✓ Created '%@' [%@]", p.displayName, p.name);
    return 0;
}

// ── doctor: health checks ────────────────────────────────────────────────────
static BOOL pathHasDir(NSString *dir) {
    const char *pe = getenv("PATH"); if (!pe) return NO;
    return [[@(pe) componentsSeparatedByString:@":"] containsObject:dir];
}
static NSString *findInPath(NSString *name, NSString *excludeDir) {
    const char *pe = getenv("PATH"); if (!pe) return nil;
    for (NSString *d in [@(pe) componentsSeparatedByString:@":"]) {
        if (excludeDir && [d isEqualToString:excludeDir]) continue;
        NSString *p = [d stringByAppendingPathComponent:name];
        if (access(p.UTF8String, X_OK) == 0) return p;
    }
    return nil;
}

static int cliDoctor(void) {
    BOOL color = isatty(1);
    NSString *(^c)(NSString *, NSString *) = ^(NSString *code, NSString *s) {
        return color ? [NSString stringWithFormat:@"\x1b[%@m%@\x1b[0m", code, s] : s;
    };
    NSString *OK   = c(@"32", @"✓"), *BAD = c(@"31", @"✗"), *NOTE = c(@"2", @"•");
    void (^line)(NSString *, NSString *) = ^(NSString *sym, NSString *msg) { pout(@"  %@ %@", sym, msg); };
    void (^hint)(NSString *) = ^(NSString *msg) { pout(@"      %@", c(@"2", [@"→ " stringByAppendingString:msg])); };

    NSString *home = NSHomeDirectory();
    NSString *shimDir = [home stringByAppendingPathComponent:@".roster/bin"];
    NSString *shim = [shimDir stringByAppendingPathComponent:@"claude"];

    pout(@"\n%@  %@\n", c(@"1", @"🐿  Roster"), c(@"2", @"doctor"));

    // App
    pout(@"%@", c(@"1", @"App"));
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    if ([bundle hasPrefix:@"/Applications/"]) line(OK, [NSString stringWithFormat:@"Roster.app at %@", bundle]);
    else line(NOTE, [NSString stringWithFormat:@"running from %@ (not /Applications)", bundle]);
    AppDescriptor *claude = [AppDescriptor claude];
    if ([claude isAvailable]) line(OK, [NSString stringWithFormat:@"Claude Desktop installed (%@)", claude.sourcePath]);
    else { line(BAD, @"Claude Desktop not found at /Applications/Claude.app"); hint(@"download it from https://claude.ai/download"); }
    ProfileStore *store = [ProfileStore new];
    NSMutableArray *names = [NSMutableArray array];
    for (Profile *p in store.profiles) [names addObject:p.name];
    line(store.profiles.count ? OK : NOTE,
         [NSString stringWithFormat:@"%lu profile(s)%@", (unsigned long)store.profiles.count,
          names.count ? [@": " stringByAppendingString:[names componentsJoinedByString:@", "]] : @""]);

    // Terminal CLI
    pout(@"\n%@", c(@"1", @"Terminal CLI"));
    BOOL shimOK = (access(shim.UTF8String, X_OK) == 0);
    if (shimOK) line(OK, @"claude shim installed (~/.roster/bin/claude)");
    else { line(BAD, @"claude shim not installed"); hint(@"run: bash tools/install-cli.sh"); }

    NSString *realClaude = findInPath(@"claude", shimDir);
    if (realClaude) line(OK, [NSString stringWithFormat:@"real claude found (%@)", realClaude]);
    else { line(BAD, @"real claude not found on PATH"); hint(@"npm install -g @anthropic-ai/claude-code"); }

    NSString *zshrc = [home stringByAppendingPathComponent:@".zshrc"];
    NSString *zc = [NSString stringWithContentsOfFile:zshrc encoding:NSUTF8StringEncoding error:nil];
    BOOL inRc = (zc && [zc containsString:@"roster/bin"]);
    line(inRc ? OK : BAD, inRc ? @"~/.roster/bin on PATH in ~/.zshrc" : @"~/.roster/bin not in ~/.zshrc");
    if (!inRc) hint(@"run: bash tools/install-cli.sh");

    BOOL activeNow = pathHasDir(shimDir) && [findInPath(@"claude", nil) isEqualToString:shim];
    if (activeNow) line(OK, @"picker is active in THIS shell");
    else {
        line(BAD, @"picker is NOT active in this terminal");
        if (inRc && shimOK) {
            pout(@"");
            pout(@"  %@", c(@"1;33", @"┌──────────────────────────────────────────────┐"));
            pout(@"  %@", c(@"1;33", @"│  This terminal started before setup.           │"));
            pout(@"  %@", c(@"1;33", @"│  → Open a NEW terminal (or run: exec zsh)      │"));
            pout(@"  %@", c(@"1;33", @"│    then type `claude` to get the picker.       │"));
            pout(@"  %@", c(@"1;33", @"└──────────────────────────────────────────────┘"));
        } else {
            hint(@"run: bash tools/install-cli.sh, then open a new terminal");
        }
    }

    NSString *codexReal = findInPath(@"codex", shimDir);
    line(NOTE, codexReal ? [NSString stringWithFormat:@"codex found (%@) — re-run install-cli.sh to add its shim", codexReal]
                         : @"codex not installed (its shim activates once codex is on PATH)");

    // Notes
    NSString *bak = [[Paths appSupportDir] stringByAppendingPathComponent:@"Claude-work.bak"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:bak]) {
        pout(@"\n%@", c(@"1", @"Notes"));
        line(NOTE, @"backup ~/Library/Application Support/Claude-work.bak can be deleted once Work looks right");
    }
    pout(@"");
    return 0;
}

static NSString *argAfter(NSArray<NSString *> *args, NSString *flag) {
    NSUInteger i = [args indexOfObject:flag];
    if (i != NSNotFound && i + 1 < args.count) return args[i + 1];
    return nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 1; i < argc; i++) [args addObject:[NSString stringWithUTF8String:argv[i]]];

        if (args.count == 0) return RunGUIApp();

        NSString *cmd = args[0];
        BOOL force = [args containsObject:@"--force"] || [args containsObject:@"-f"];

        if ([cmd isEqualToString:@"--list"] || [cmd isEqualToString:@"list"])
            return cliList();
        if ([cmd isEqualToString:@"--sync"] || [cmd isEqualToString:@"sync"])
            return cliSync();
        if ([cmd isEqualToString:@"--setup"] || [cmd isEqualToString:@"setup"])
            return args.count > 1 ? cliSetup(args[1], force) : (perr(@"usage: --setup <name>"), 1);
        if ([cmd isEqualToString:@"--launch"] || [cmd isEqualToString:@"launch"])
            return args.count > 1 ? cliLaunch(args[1]) : (perr(@"usage: --launch <name>"), 1);
        if ([cmd isEqualToString:@"--code"] || [cmd isEqualToString:@"code"])
            return args.count > 1 ? cliCode(args[1]) : (perr(@"usage: --code <name>"), 1);
        if ([cmd isEqualToString:@"--delete"] || [cmd isEqualToString:@"delete"])
            return args.count > 1 ? cliDelete(args[1]) : (perr(@"usage: --delete <name>"), 1);
        if ([cmd isEqualToString:@"--create"] || [cmd isEqualToString:@"create"])
            return args.count > 1 ? cliCreate(args[1], argAfter(args, @"--emoji"), argAfter(args, @"--app"))
                                  : (perr(@"usage: --create <name> [--emoji X] [--app id]"), 1);
        if ([cmd isEqualToString:@"doctor"] || [cmd isEqualToString:@"--doctor"])
            return cliDoctor();
        if ([cmd isEqualToString:@"--pick"])
            return args.count > 1 ? RunPicker(args[1]) : (perr(@"usage: --pick <claude|codex>"), 1);
        if ([cmd isEqualToString:@"--gui"]) return RunGUIApp();

        perr(@"Unknown command: %@\nCommands: --list --create --setup --launch --code --sync --delete (no args = GUI)", cmd);
        return 1;
    }
}
