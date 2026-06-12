// Models.m
#import "Models.h"

// ── Paths ───────────────────────────────────────────────────────────────────
@implementation Paths
+ (NSString *)home { return NSHomeDirectory(); }
+ (NSString *)profilesDir   { return [[self home] stringByAppendingPathComponent:@".claude-profiles"]; }
+ (NSString *)profilesJSON  { return [[self profilesDir] stringByAppendingPathComponent:@"profiles.json"]; }
+ (NSString *)versionJSON   { return [[self profilesDir] stringByAppendingPathComponent:@"app-versions.json"]; }
+ (NSString *)userAppsDir   { return [[self home] stringByAppendingPathComponent:@"Applications"]; }
+ (NSString *)appSupportDir { return [[self home] stringByAppendingPathComponent:@"Library/Application Support"]; }
+ (NSString *)launchAgentsDir { return [[self home] stringByAppendingPathComponent:@"Library/LaunchAgents"]; }
@end

// ── AppDescriptor ────────────────────────────────────────────────────────────
@implementation AppDescriptor

+ (AppDescriptor *)_make:(NSString *)appID
             displayName:(NSString *)displayName
              sourcePath:(NSString *)sourcePath
        originalBundleName:(NSString *)origName
            bundleIDPrefix:(NSString *)prefix {
    AppDescriptor *d = [AppDescriptor new];
    d.appID = appID;
    d.displayName = displayName;
    d.sourcePath = sourcePath;
    d.originalBundleName = origName;
    d.bundleIDPrefix = prefix;
    return d;
}

+ (NSArray<AppDescriptor *> *)allKnown {
    static NSArray *apps;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        apps = @[
            // Claude — fully supported / tested.
            [self _make:@"claude" displayName:@"Claude"
             sourcePath:@"/Applications/Claude.app"
       originalBundleName:@"Claude"
         bundleIDPrefix:@"com.anthropic.claude.profile"],
            // Cursor — same Electron isolation pattern (helpers: "Cursor Helper*.app").
            [self _make:@"cursor" displayName:@"Cursor"
             sourcePath:@"/Applications/Cursor.app"
       originalBundleName:@"Cursor"
         bundleIDPrefix:@"com.claudeprofiles.cursor.profile"],
            // Windsurf — likewise.
            [self _make:@"windsurf" displayName:@"Windsurf"
             sourcePath:@"/Applications/Windsurf.app"
       originalBundleName:@"Windsurf"
         bundleIDPrefix:@"com.claudeprofiles.windsurf.profile"],
        ];
    });
    return apps;
}

+ (NSArray<AppDescriptor *> *)available {
    NSMutableArray *out = [NSMutableArray array];
    for (AppDescriptor *d in [self allKnown]) if ([d isAvailable]) [out addObject:d];
    return out;
}

+ (AppDescriptor *)claude { return [self byID:@"claude"]; }

+ (AppDescriptor *)byID:(NSString *)appID {
    for (AppDescriptor *d in [self allKnown]) if ([d.appID isEqualToString:appID]) return d;
    return [self allKnown].firstObject; // fall back to Claude
}

- (BOOL)isAvailable {
    return [[NSFileManager defaultManager] fileExistsAtPath:self.sourcePath];
}

- (nullable NSString *)sourceVersion {
    NSString *plistPath = [self.sourcePath stringByAppendingPathComponent:@"Contents/Info.plist"];
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    return p[@"CFBundleShortVersionString"];
}
@end

// ── Profile ──────────────────────────────────────────────────────────────────
@implementation Profile

- (NSString *)slug {
    NSString *s = [self.name lowercaseString];
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    return s;
}

- (AppDescriptor *)app { return [AppDescriptor byID:(self.appID ?: @"claude")]; }

- (NSString *)bundleID {
    return [NSString stringWithFormat:@"%@.%@", [self app].bundleIDPrefix, [self slug]];
}

- (NSString *)internalBundleName {
    // CFBundleName — Electron derives helper paths AND userData base from this.
    return [NSString stringWithFormat:@"%@-%@", [self app].originalBundleName, [self slug]];
}

- (NSString *)appDisplayName {
    return [NSString stringWithFormat:@"%@ (%@)", [self app].displayName, self.displayName];
}

- (NSString *)appBundlePath {
    NSString *file = [NSString stringWithFormat:@"%@-%@.app", [self app].originalBundleName, [self slug]];
    return [[Paths userAppsDir] stringByAppendingPathComponent:file];
}

- (NSString *)userDataDir {
    return [[Paths appSupportDir] stringByAppendingPathComponent:[self internalBundleName]];
}

- (NSString *)profileDir {
    return [[Paths profilesDir] stringByAppendingPathComponent:[self slug]];
}

- (NSString *)codeConfigDir {
    return [[self profileDir] stringByAppendingPathComponent:@"claude-code"];
}

- (BOOL)isDesktopInstalled {
    // Genuine-app model: a profile can launch Desktop whenever its source app is
    // installed (no per-profile copied bundle exists anymore).
    return [[self app] isAvailable];
}

- (BOOL)isCodeInitialized {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self codeConfigDir]];
}

- (NSDictionary *)toDict {
    return @{
        @"name": self.name ?: @"",
        @"display_name": self.displayName ?: @"",
        @"color": self.color ?: @"#0066CC",
        @"emoji": self.emoji ?: @"👤",
        @"app_id": self.appID ?: @"claude",
        @"created_at": self.createdAt ?: @"",
    };
}

+ (instancetype)fromDict:(NSDictionary *)d {
    Profile *p = [Profile new];
    p.name = d[@"name"];
    p.displayName = d[@"display_name"] ?: d[@"name"];
    p.color = d[@"color"] ?: @"#0066CC";
    p.emoji = d[@"emoji"] ?: @"👤";
    p.appID = d[@"app_id"] ?: @"claude";   // backward compat: old profiles → Claude
    p.createdAt = d[@"created_at"] ?: @"";
    return p;
}
@end

// ── ProfileStore ─────────────────────────────────────────────────────────────
@implementation ProfileStore {
    NSMutableArray<Profile *> *_profiles;
}

- (instancetype)init {
    if ((self = [super init])) {
        _profiles = [NSMutableArray array];
        [[NSFileManager defaultManager] createDirectoryAtPath:[Paths profilesDir]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        [self reload];
    }
    return self;
}

- (NSArray<Profile *> *)profiles { return [_profiles copy]; }

- (void)reload {
    [_profiles removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:[Paths profilesJSON]];
    if (!data) return;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    for (NSDictionary *pd in root[@"profiles"]) {
        if ([pd isKindOfClass:[NSDictionary class]]) [_profiles addObject:[Profile fromDict:pd]];
    }
}

- (void)_save {
    NSMutableArray *arr = [NSMutableArray array];
    for (Profile *p in _profiles) [arr addObject:[p toDict]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"profiles": arr}
                                                  options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[Paths profilesJSON] atomically:YES];
}

- (nullable Profile *)get:(NSString *)nameOrSlug {
    NSString *lower = [nameOrSlug lowercaseString];
    for (Profile *p in _profiles)
        if ([p.name isEqualToString:nameOrSlug] || [[p slug] isEqualToString:lower]) return p;
    return nil;
}

- (nullable Profile *)create:(NSString *)name
                 displayName:(nullable NSString *)displayName
                       emoji:(NSString *)emoji
                       color:(NSString *)color
                       appID:(NSString *)appID
                       error:(NSError **)error {
    if ([self get:name]) {
        if (error) *error = [NSError errorWithDomain:@"ClaudeProfiles" code:1
                              userInfo:@{NSLocalizedDescriptionKey:
                              [NSString stringWithFormat:@"Profile '%@' already exists", name]}];
        return nil;
    }
    NSString *stripped = [[name stringByReplacingOccurrencesOfString:@"-" withString:@""]
                                stringByReplacingOccurrencesOfString:@"_" withString:@""];
    NSCharacterSet *nonAlnum = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    if (stripped.length == 0 || [stripped rangeOfCharacterFromSet:nonAlnum].location != NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"ClaudeProfiles" code:2
                              userInfo:@{NSLocalizedDescriptionKey:
                              @"Name must be alphanumeric (hyphens/underscores allowed)"}];
        return nil;
    }

    Profile *p = [Profile new];
    p.name = name;
    p.displayName = (displayName.length ? displayName : [name capitalizedString]);
    p.emoji = emoji ?: @"👤";
    p.color = color ?: @"#0066CC";
    p.appID = appID ?: @"claude";
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    p.createdAt = [f stringFromDate:[NSDate date]];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[p codeConfigDir] withIntermediateDirectories:YES attributes:nil error:nil];

    [_profiles addObject:p];
    [self _save];
    return p;
}

- (BOOL)delete:(NSString *)name keepData:(BOOL)keepData {
    Profile *p = [self get:name];
    if (!p) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([p isDesktopInstalled]) [fm removeItemAtPath:[p appBundlePath] error:nil];
    if (!keepData) [fm removeItemAtPath:[p profileDir] error:nil];
    [_profiles removeObject:p];
    [self _save];
    return YES;
}
@end
