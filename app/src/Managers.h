// Managers.h — shell helpers + the three managers (Desktop, Code, LaunchAgent).
#import <Foundation/Foundation.h>
#import "Models.h"

NS_ASSUME_NONNULL_BEGIN

// ── Shell — thin NSTask wrappers ─────────────────────────────────────────────
@interface Shell : NSObject
// Run a tool, wait, return exit status. Captures nothing.
+ (int)run:(NSString *)launchPath args:(NSArray<NSString *> *)args;
// Run and capture stdout (trimmed). status written to *status if provided.
+ (NSString *)capture:(NSString *)launchPath args:(NSArray<NSString *> *)args status:(nullable int *)status;
// Fire-and-forget (does not wait).
+ (void)spawn:(NSString *)launchPath args:(NSArray<NSString *> *)args;
@end

// ── DesktopManager — isolated Electron app bundles ──────────────────────────
@interface DesktopManager : NSObject

// Create/refresh a profile's isolated app bundle. Returns the bundle path, or
// nil with *error set (e.g. source app missing).
- (nullable NSString *)setup:(Profile *)profile force:(BOOL)force error:(NSError **)error;

// Launch the profile's Desktop app (sets up first if needed). Returns NO on error.
- (BOOL)launch:(Profile *)profile error:(NSError **)error;

// Re-copy installed bundles for the given app after it updates.
- (void)syncAllInstalledForApp:(AppDescriptor *)app;

- (BOOL)isRunning:(Profile *)profile;

// Version tracking (per app id).
- (nullable NSString *)syncedVersionForApp:(AppDescriptor *)app;
- (void)writeSyncedVersion:(NSString *)version forApp:(AppDescriptor *)app;
// Returns @[syncedVersion, installedVersion] if an update is pending, else nil.
- (nullable NSArray<NSString *> *)updateAvailableForApp:(AppDescriptor *)app;

@end

// ── CodeManager — Claude Code isolation via CLAUDE_CONFIG_DIR ────────────────
@interface CodeManager : NSObject
// Open a terminal running `claude` with this profile's config dir. Returns NO if
// no terminal could be launched.
- (BOOL)launch:(Profile *)profile error:(NSError **)error;
@end

// ── LaunchAgent — auto-sync on login ────────────────────────────────────────
@interface LaunchAgent : NSObject
+ (BOOL)isInstalled;
+ (BOOL)install:(NSError **)error;   // writes plist + launchctl load
+ (BOOL)remove:(NSError **)error;    // launchctl unload + delete
@end

NS_ASSUME_NONNULL_END
