// Models.h — core data model: paths, app descriptors, profiles, store.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ── Shared paths ────────────────────────────────────────────────────────────
@interface Paths : NSObject
+ (NSString *)profilesDir;       // ~/.claude-profiles
+ (NSString *)profilesJSON;      // ~/.claude-profiles/profiles.json
+ (NSString *)versionJSON;       // ~/.claude-profiles/app-versions.json
+ (NSString *)userAppsDir;       // ~/Applications
+ (NSString *)appSupportDir;     // ~/Library/Application Support
+ (NSString *)launchAgentsDir;   // ~/Library/LaunchAgents
@end

// ── AppDescriptor — describes an isolatable Electron app ────────────────────
@interface AppDescriptor : NSObject
@property (nonatomic, copy) NSString *appID;              // "claude", "cursor", …
@property (nonatomic, copy) NSString *displayName;        // "Claude"
@property (nonatomic, copy) NSString *sourcePath;         // "/Applications/Claude.app"
@property (nonatomic, copy) NSString *originalBundleName; // "Claude" — finds "Claude Helper*.app"
@property (nonatomic, copy) NSString *bundleIDPrefix;     // "com.anthropic.claude.profile"

- (BOOL)isAvailable;             // source app exists on disk
- (nullable NSString *)sourceVersion;  // CFBundleShortVersionString of the source app

+ (NSArray<AppDescriptor *> *)allKnown;       // every descriptor (installed or not)
+ (NSArray<AppDescriptor *> *)available;      // only those whose source exists
+ (AppDescriptor *)claude;
+ (nullable AppDescriptor *)byID:(NSString *)appID;
@end

// ── Profile — one isolated identity, tied to one app ────────────────────────
@interface Profile : NSObject
@property (nonatomic, copy) NSString *name;         // "work"
@property (nonatomic, copy) NSString *displayName;  // "Work"
@property (nonatomic, copy) NSString *color;        // "#0066CC"
@property (nonatomic, copy) NSString *emoji;        // "💼"
@property (nonatomic, copy) NSString *appID;        // "claude"
@property (nonatomic, copy) NSString *createdAt;    // ISO8601

- (NSString *)slug;                                   // "work"
- (AppDescriptor *)app;                               // resolved descriptor (defaults to Claude)

// Per-app derived values
- (NSString *)bundleID;                               // com.anthropic.claude.profile.work
- (NSString *)internalBundleName;                     // "Claude-work" (CFBundleName)
- (NSString *)appDisplayName;                         // "Claude (Work)"
- (NSString *)appBundlePath;                          // ~/Applications/Claude-work.app
- (NSString *)userDataDir;                            // ~/Library/Application Support/Claude-work

// Profile-wide values
- (NSString *)profileDir;                             // ~/.claude-profiles/work
- (NSString *)codeConfigDir;                          // .../claude-code
- (BOOL)isDesktopInstalled;
- (BOOL)isCodeInitialized;

- (NSDictionary *)toDict;
+ (instancetype)fromDict:(NSDictionary *)d;
@end

// ── ProfileStore — load/save profiles.json ─────────────────────────────────
@interface ProfileStore : NSObject
@property (nonatomic, readonly) NSArray<Profile *> *profiles;

- (void)reload;
- (nullable Profile *)get:(NSString *)nameOrSlug;
- (nullable Profile *)create:(NSString *)name
                 displayName:(nullable NSString *)displayName
                       emoji:(NSString *)emoji
                       color:(NSString *)color
                       appID:(NSString *)appID
                       error:(NSError **)error;
- (BOOL)delete:(NSString *)name keepData:(BOOL)keepData;
@end

NS_ASSUME_NONNULL_END
