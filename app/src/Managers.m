// Managers.m
#import "Managers.h"

// Wrap a string for safe inclusion inside a single-quoted shell word.
static NSString *ShQuote(NSString *s) {
    NSString *escaped = [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

// ── Shell ────────────────────────────────────────────────────────────────────
@implementation Shell

+ (int)run:(NSString *)launchPath args:(NSArray<NSString *> *)args {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:launchPath];
    t.arguments = args;
    t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *err = nil;
    if (![t launchAndReturnError:&err]) return -1;
    [t waitUntilExit];
    return t.terminationStatus;
}

+ (NSString *)capture:(NSString *)launchPath args:(NSArray<NSString *> *)args status:(int *)status {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:launchPath];
    t.arguments = args;
    NSPipe *pipe = [NSPipe pipe];
    t.standardOutput = pipe;
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *err = nil;
    if (![t launchAndReturnError:&err]) { if (status) *status = -1; return @""; }
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [t waitUntilExit];
    if (status) *status = t.terminationStatus;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

+ (void)spawn:(NSString *)launchPath args:(NSArray<NSString *> *)args {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:launchPath];
    t.arguments = args;
    t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    [t launchAndReturnError:nil];
}
@end

// ── DesktopManager ────────────────────────────────────────────────────────────
@implementation DesktopManager

- (nullable NSString *)setup:(Profile *)profile force:(BOOL)force error:(NSError **)error {
    AppDescriptor *app = [profile app];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:app.sourcePath]) {
        if (error) *error = [NSError errorWithDomain:@"ClaudeProfiles" code:10 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"%@ not found at %@", app.displayName, app.sourcePath]}];
        return nil;
    }
    [fm createDirectoryAtPath:[Paths userAppsDir] withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dest = [profile appBundlePath];
    BOOL exists = [fm fileExistsAtPath:dest];

    if (exists && !force) {
        // Re-apply patches/signature to an existing bundle without re-copying.
        [self _patchOuterPlist:dest profile:profile];
        [self _renameHelpers:dest profile:profile];
        [self _signInsideOut:dest];
        [self _clearQuarantine:dest];
        return dest;
    }
    if (exists) [fm removeItemAtPath:dest error:nil];

    NSError *cpErr = nil;
    if (![fm copyItemAtPath:app.sourcePath toPath:dest error:&cpErr]) {
        if (error) *error = cpErr;
        return nil;
    }
    [self _patchOuterPlist:dest profile:profile];
    [self _renameHelpers:dest profile:profile];
    [self _signInsideOut:dest];
    [self _clearQuarantine:dest];
    return dest;
}

- (BOOL)launch:(Profile *)profile error:(NSError **)error {
    if (![profile isDesktopInstalled]) {
        if (![self setup:profile force:NO error:error]) return NO;
    }
    [self _clearQuarantine:[profile appBundlePath]];
    // Pass --user-data-dir so each profile uses an isolated Electron userData path.
    NSString *udd = [NSString stringWithFormat:@"--user-data-dir=%@", [profile userDataDir]];
    [Shell spawn:@"/usr/bin/open"
            args:@[@"-n", [profile appBundlePath], @"--args", udd]];
    return YES;
}

- (void)syncAllInstalledForApp:(AppDescriptor *)app {
    ProfileStore *store = [ProfileStore new];
    for (Profile *p in store.profiles) {
        if ([p.appID isEqualToString:app.appID] && [p isDesktopInstalled]) {
            [self setup:p force:YES error:nil];
        }
    }
    NSString *v = [app sourceVersion];
    if (v) [self writeSyncedVersion:v forApp:app];
}

- (BOOL)isRunning:(Profile *)profile {
    int status = 0;
    [Shell capture:@"/usr/bin/pgrep" args:@[@"-f", [profile bundleID]] status:&status];
    return status == 0;
}

// ── Version tracking ─────────────────────────────────────────────────────────

- (NSMutableDictionary *)_loadVersions {
    NSData *d = [NSData dataWithContentsOfFile:[Paths versionJSON]];
    if (!d) return [NSMutableDictionary dictionary];
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return [NSMutableDictionary dictionary];
    return [obj mutableCopy];
}

- (nullable NSString *)syncedVersionForApp:(AppDescriptor *)app {
    NSDictionary *all = [self _loadVersions];
    NSDictionary *entry = all[app.appID];
    return [entry isKindOfClass:[NSDictionary class]] ? entry[@"synced_version"] : nil;
}

- (void)writeSyncedVersion:(NSString *)version forApp:(AppDescriptor *)app {
    NSMutableDictionary *all = [self _loadVersions];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    all[app.appID] = @{ @"synced_version": version, @"last_synced": [f stringFromDate:[NSDate date]] };
    NSData *out = [NSJSONSerialization dataWithJSONObject:all options:NSJSONWritingPrettyPrinted error:nil];
    [out writeToFile:[Paths versionJSON] atomically:YES];
}

- (nullable NSArray<NSString *> *)updateAvailableForApp:(AppDescriptor *)app {
    NSString *installed = [app sourceVersion];
    NSString *synced = [self syncedVersionForApp:app];
    if (installed && synced && ![installed isEqualToString:synced]) return @[synced, installed];
    return nil;
}

// ── Internals ─────────────────────────────────────────────────────────────────

- (void)_patchOuterPlist:(NSString *)appBundle profile:(Profile *)profile {
    NSString *plistPath = [appBundle stringByAppendingPathComponent:@"Contents/Info.plist"];
    NSMutableDictionary *plist = [[NSDictionary dictionaryWithContentsOfFile:plistPath] mutableCopy];
    if (!plist) return;
    plist[@"CFBundleIdentifier"]  = [profile bundleID];
    plist[@"CFBundleName"]        = [profile internalBundleName];   // Electron helper/userData base
    plist[@"CFBundleDisplayName"] = [profile appDisplayName];        // shown in Dock/Finder
    [plist writeToFile:plistPath atomically:YES];
}

// Rename "<OrigName> Helper*.app" → "<Internal> Helper*.app" (dir + binary + plist).
- (void)_renameHelpers:(NSString *)appBundle profile:(Profile *)profile {
    NSString *frameworks = [appBundle stringByAppendingPathComponent:@"Contents/Frameworks"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *entries = [fm contentsOfDirectoryAtPath:frameworks error:nil];
    if (!entries) return;

    NSString *origName  = [profile app].originalBundleName;
    NSString *newName   = [profile internalBundleName];
    NSString *origPrefix = [NSString stringWithFormat:@"%@ Helper", origName]; // "Claude Helper"

    for (NSString *entry in entries) {
        if (![entry hasPrefix:origPrefix] || ![entry hasSuffix:@".app"]) continue;
        NSString *stem    = [entry substringToIndex:entry.length - 4];          // "Claude Helper (GPU)"
        NSString *suffix  = [stem substringFromIndex:origPrefix.length];        // " (GPU)" or ""
        NSString *newStem = [NSString stringWithFormat:@"%@ Helper%@", newName, suffix];

        NSString *helperApp = [frameworks stringByAppendingPathComponent:entry];
        NSString *macosDir  = [helperApp stringByAppendingPathComponent:@"Contents/MacOS"];
        NSString *oldBin    = [macosDir stringByAppendingPathComponent:stem];
        NSString *newBin    = [macosDir stringByAppendingPathComponent:newStem];
        if ([fm fileExistsAtPath:oldBin]) [fm moveItemAtPath:oldBin toPath:newBin error:nil];

        NSString *hp = [helperApp stringByAppendingPathComponent:@"Contents/Info.plist"];
        NSMutableDictionary *hplist = [[NSDictionary dictionaryWithContentsOfFile:hp] mutableCopy];
        if (hplist) {
            hplist[@"CFBundleExecutable"]  = newStem;
            hplist[@"CFBundleName"]        = newName;
            hplist[@"CFBundleDisplayName"] = newName;
            hplist[@"CFBundleIdentifier"]  = [NSString stringWithFormat:@"%@.helper", [profile bundleID]];
            [hplist writeToFile:hp atomically:YES];
        }
        NSString *newApp = [frameworks stringByAppendingPathComponent:
                            [newStem stringByAppendingString:@".app"]];
        [fm moveItemAtPath:helperApp toPath:newApp error:nil];
    }
}

// Ad-hoc sign inside-out: deepest nested bundles first, outer app last.
// --deep alone does NOT descend into nested .app bundles inside Frameworks/.
- (void)_signInsideOut:(NSString *)appBundle {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *bundles = [NSMutableArray array];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:appBundle];
    for (NSString *rel in en) {
        if ([rel hasSuffix:@".app"] || [rel hasSuffix:@".framework"]) {
            [bundles addObject:[appBundle stringByAppendingPathComponent:rel]];
        }
    }
    // Deepest first (more path components → sign earlier).
    [bundles sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger da = a.pathComponents.count, db = b.pathComponents.count;
        if (da == db) return NSOrderedSame;
        return da > db ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSString *b in bundles) {
        [Shell run:@"/usr/bin/codesign" args:@[@"--sign", @"-", @"--force", b]];
    }
    [Shell run:@"/usr/bin/codesign" args:@[@"--sign", @"-", @"--force", appBundle]];
}

- (void)_clearQuarantine:(NSString *)appBundle {
    NSString *pipeline = [NSString stringWithFormat:
        @"find %@ -print0 | xargs -0 xattr -c 2>/dev/null || true", ShQuote(appBundle)];
    [Shell run:@"/bin/sh" args:@[@"-c", pipeline]];
}
@end

// ── CodeManager ────────────────────────────────────────────────────────────────
@implementation CodeManager

- (NSString *)_resolveClaude {
    int status = 0;
    NSString *p = [Shell capture:@"/bin/bash" args:@[@"-lc", @"command -v claude"] status:&status];
    if (status == 0 && p.length) return p;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *cand in @[ [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin/claude"],
                              @"/opt/homebrew/bin/claude", @"/usr/local/bin/claude" ]) {
        if ([fm fileExistsAtPath:cand]) return cand;
    }
    return @"claude"; // let the terminal's login shell resolve it
}

- (BOOL)launch:(Profile *)profile error:(NSError **)error {
    NSString *configDir = [profile codeConfigDir];
    [[NSFileManager defaultManager] createDirectoryAtPath:configDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *claudeBin = [self _resolveClaude];

    // Build the command the terminal's shell will run. Set the env var, run claude,
    // then drop back to an interactive login shell so the window stays open.
    NSString *cmd = [NSString stringWithFormat:
        @"export CLAUDE_CONFIG_DIR=%@; %@; exec bash -l",
        ShQuote(configDir), ShQuote(claudeBin)];

    NSString *ghostty = @"/Applications/Ghostty.app/Contents/MacOS/ghostty";
    if ([[NSFileManager defaultManager] fileExistsAtPath:ghostty]) {
        [Shell spawn:ghostty args:@[@"-e", @"bash", @"-lc", cmd]];
        return YES;
    }

    // Fallback: Terminal.app via AppleScript.
    NSString *escaped = [cmd stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *script = [NSString stringWithFormat:
        @"tell application \"Terminal\"\nactivate\ndo script \"%@\"\nend tell", escaped];
    int status = [Shell run:@"/usr/bin/osascript" args:@[@"-e", script]];
    if (status != 0 && error) {
        *error = [NSError errorWithDomain:@"ClaudeProfiles" code:20 userInfo:@{
            NSLocalizedDescriptionKey: @"Could not open a terminal (Ghostty or Terminal.app)."}];
        return NO;
    }
    return YES;
}
@end

// ── LaunchAgent ─────────────────────────────────────────────────────────────────
@implementation LaunchAgent

+ (NSString *)label { return @"com.claudeprofiles.autosync"; }
+ (NSString *)plistPath {
    return [[Paths launchAgentsDir] stringByAppendingPathComponent:
            [[self label] stringByAppendingPathExtension:@"plist"]];
}

+ (BOOL)isInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self plistPath]];
}

+ (BOOL)install:(NSError **)error {
    NSString *binary = [[NSBundle mainBundle] executablePath];
    if (!binary) {
        if (error) *error = [NSError errorWithDomain:@"ClaudeProfiles" code:30 userInfo:@{
            NSLocalizedDescriptionKey:@"Could not resolve app binary path."}];
        return NO;
    }
    NSDictionary *plist = @{
        @"Label": [self label],
        @"ProgramArguments": @[binary, @"--sync"],
        @"RunAtLoad": @YES,
        @"StartInterval": @21600,   // every 6 hours
    };
    [[NSFileManager defaultManager] createDirectoryAtPath:[Paths launchAgentsDir]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *serErr = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                        format:NSPropertyListXMLFormat_v1_0 options:0 error:&serErr];
    if (!data || ![data writeToFile:[self plistPath] atomically:YES]) {
        if (error) *error = serErr ?: [NSError errorWithDomain:@"ClaudeProfiles" code:31 userInfo:@{
            NSLocalizedDescriptionKey:@"Could not write LaunchAgent plist."}];
        return NO;
    }
    [Shell run:@"/bin/launchctl" args:@[@"unload", [self plistPath]]]; // ignore if not loaded
    [Shell run:@"/bin/launchctl" args:@[@"load", @"-w", [self plistPath]]];
    return YES;
}

+ (BOOL)remove:(NSError **)error {
    if ([self isInstalled]) {
        [Shell run:@"/bin/launchctl" args:@[@"unload", @"-w", [self plistPath]]];
        [[NSFileManager defaultManager] removeItemAtPath:[self plistPath] error:nil];
    }
    return YES;
}
@end
