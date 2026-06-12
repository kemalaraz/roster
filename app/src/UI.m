// UI.m — windowed Cocoa GUI: profile cards, new-profile sheet, sync, auto-sync.
#import "UI.h"
#import "Models.h"
#import "Managers.h"

// ── Palette (own brand — violet/lavender, app-agnostic) ──────────────────────
static NSColor *CPColor(int r, int g, int b) {
    return [NSColor colorWithSRGBRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static NSColor *CPAccent(void)    { return CPColor( 15, 164, 127); } // #0FA47F teal green
static NSColor *CPAccentDeep(void){ return CPColor( 11, 125,  96); } // #0B7D60 pressed/deep
static NSColor *CPBg(void)        { return CPColor(212, 238, 230); } // soft teal wash (matches backdrop top)
static NSColor *CPSurface(void)   { return CPColor(251, 254, 253); } // #FBFEFD card surface
static NSColor *CPBorder(void)    { return CPColor(210, 232, 224); } // #D2E8E0 teal hairline
static NSColor *CPInk(void)       { return CPColor( 28,  46,  41); } // #1C2E29 deep teal-charcoal text
static NSColor *CPInkSoft(void)   { return CPColor(104, 124, 118); } // #687C76 secondary text

// A filled accent "primary" button, fully custom-drawn. Drawing the fill and label
// ourselves (instead of bezelColor + a manual white attributedTitle) means the color
// and letters never vanish on press — the system bezel's highlighted state was
// blanking them.
@interface CPButton : NSButton @end
@implementation CPButton
- (NSSize)intrinsicContentSize {
    NSDictionary *a = @{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]};
    NSSize s = [(self.title ?: @"") sizeWithAttributes:a];
    return NSMakeSize(ceil(s.width) + 28, 28);   // same height as secondary buttons
}
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *fill = CPAccent();
    if (!self.isEnabled)         fill = [CPAccent() colorWithAlphaComponent:0.45];
    else if (self.isHighlighted) fill = CPAccentDeep();
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6];
    [fill setFill];
    [p fill];
    NSDictionary *a = @{
        NSForegroundColorAttributeName: [[NSColor whiteColor] colorWithAlphaComponent:(self.isEnabled ? 1.0 : 0.85)],
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]};
    NSString *t = self.title ?: @"";
    NSSize ts = [t sizeWithAttributes:a];
    NSPoint pt = NSMakePoint(round((NSWidth(self.bounds) - ts.width) / 2),
                             round((NSHeight(self.bounds) - ts.height) / 2));
    [t drawAtPoint:pt withAttributes:a];
}
@end

// A secondary button — same height/shape as the primary, but a light surface with a
// hairline border and ink label. Keeps the whole action row visually consistent.
@interface CPSecButton : NSButton @end
@implementation CPSecButton
- (NSSize)intrinsicContentSize {
    NSDictionary *a = @{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]};
    NSSize s = [(self.title ?: @"") sizeWithAttributes:a];
    return NSMakeSize(ceil(s.width) + 26, 28);
}
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *fill = self.isHighlighted ? CPColor(224, 242, 236) : CPSurface();
    NSRect b = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:b xRadius:6 yRadius:6];
    [fill setFill]; [p fill];
    [CPBorder() setStroke]; p.lineWidth = 1; [p stroke];
    NSDictionary *a = @{
        NSForegroundColorAttributeName: (self.isEnabled ? CPInk() : CPInkSoft()),
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium]};
    NSString *t = self.title ?: @"";
    NSSize ts = [t sizeWithAttributes:a];
    [t drawAtPoint:NSMakePoint(round((NSWidth(self.bounds) - ts.width) / 2),
                               round((NSHeight(self.bounds) - ts.height) / 2)) withAttributes:a];
}
@end

static NSButton *_cpMakeButton(Class cls, NSString *title, id target, SEL action) {
    NSButton *b = [cls new];
    b.title = title;
    b.target = target;
    b.action = action;
    b.bordered = NO;
    [b setButtonType:NSButtonTypeMomentaryChange];
    b.wantsLayer = YES;
    return b;
}
static NSButton *CPPrimaryButton(NSString *title, id target, SEL action) {
    return _cpMakeButton([CPButton class], title, target, action);
}
static NSButton *CPSecondaryButton(NSString *title, id target, SEL action) {
    return _cpMakeButton([CPSecButton class], title, target, action);
}

// Window backdrop — a subtle vertical lavender gradient with a faint violet glow,
// so the background reads as soft depth rather than a flat fill.
@interface CPBackgroundView : NSView @end
@implementation CPBackgroundView
- (void)drawRect:(NSRect)dirtyRect {
    // Soft teal-green wash, in the family of the app's teal accent (#0FA47F).
    NSGradient *g = [[NSGradient alloc] initWithStartingColor:CPColor(212, 238, 230)
                                                  endingColor:CPColor(234, 246, 242)];
    [g drawInRect:self.bounds angle:-90];
    NSColor *glow = [CPAccent() colorWithAlphaComponent:0.18];
    NSGradient *rg = [[NSGradient alloc] initWithStartingColor:glow
                                                   endingColor:[CPAccent() colorWithAlphaComponent:0]];
    NSPoint ctr = NSMakePoint(NSWidth(self.bounds) * 0.82, NSHeight(self.bounds) * 0.90);
    [rg drawFromCenter:ctr radius:0 toCenter:ctr radius:NSWidth(self.bounds) * 0.55 options:0];
}
@end

// ── A top-down (flipped) container so cards stack from the top of the scroll view.
@interface FlippedView : NSView @end
@implementation FlippedView - (BOOL)isFlipped { return YES; } @end

#pragma mark - New Profile Sheet

@interface NewProfileSheet : NSObject
@property (nonatomic, strong) NSWindow *sheet;
@property (nonatomic, strong) NSTextField *nameField, *displayField, *emojiField;
@property (nonatomic, strong) NSPopUpButton *appPopup;
@property (nonatomic, copy) void (^completion)(NSDictionary * _Nullable);
@end

@implementation NewProfileSheet

static NSTextField *Label(NSString *s) {
    NSTextField *l = [NSTextField labelWithString:s];
    l.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    l.textColor = [NSColor secondaryLabelColor];
    return l;
}

- (void)presentForWindow:(NSWindow *)parent completion:(void (^)(NSDictionary * _Nullable))completion {
    self.completion = completion;

    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 320)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.sheet = w;
    NSView *c = w.contentView;

    NSTextField *title = [NSTextField labelWithString:@"New Profile"];
    title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];

    self.nameField = [NSTextField new];
    self.nameField.placeholderString = @"work";
    self.displayField = [NSTextField new];
    self.displayField.placeholderString = @"Work (optional)";
    self.emojiField = [NSTextField new];
    self.emojiField.stringValue = @"💼";
    self.emojiField.alignment = NSTextAlignmentCenter;

    self.appPopup = [[NSPopUpButton alloc] init];
    for (AppDescriptor *a in [AppDescriptor available]) [self.appPopup addItemWithTitle:a.displayName];
    if (self.appPopup.numberOfItems == 0) [self.appPopup addItemWithTitle:@"Claude"];

    // Preset emoji quick-picks
    NSStackView *emojis = [NSStackView new];
    emojis.spacing = 2;
    for (NSString *e in @[@"💼", @"🏠", @"🎓", @"🔬", @"🎨", @"🚀", @"⭐", @"🔧"]) {
        NSButton *b = [NSButton buttonWithTitle:e target:self action:@selector(pickEmoji:)];
        b.bordered = NO;
        b.font = [NSFont systemFontOfSize:16];
        [emojis addArrangedSubview:b];
    }

    NSButton *create = [NSButton buttonWithTitle:@"Create" target:self action:@selector(create:)];
    create.keyEquivalent = @"\r";
    create.bezelStyle = NSBezelStyleRounded;
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";
    cancel.bezelStyle = NSBezelStyleRounded;

    NSStackView *buttons = [NSStackView stackViewWithViews:@[cancel, create]];
    buttons.spacing = 10;

    NSStackView *form = [NSStackView stackViewWithViews:@[
        title,
        Label(@"Profile name (identifier)"), self.nameField,
        Label(@"Display name"), self.displayField,
        Label(@"Emoji"), self.emojiField, emojis,
        Label(@"App"), self.appPopup,
    ]];
    form.orientation = NSUserInterfaceLayoutOrientationVertical;
    form.alignment = NSLayoutAttributeLeading;
    form.spacing = 6;
    form.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:form];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:buttons];

    [NSLayoutConstraint activateConstraints:@[
        [form.topAnchor constraintEqualToAnchor:c.topAnchor constant:20],
        [form.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:20],
        [form.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-20],
        [self.nameField.widthAnchor constraintEqualToConstant:340],
        [self.displayField.widthAnchor constraintEqualToConstant:340],
        [self.emojiField.widthAnchor constraintEqualToConstant:60],
        [self.appPopup.widthAnchor constraintEqualToConstant:200],
        [buttons.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-20],
        [buttons.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-20],
    ]];

    [parent beginSheet:w completionHandler:nil];
}

- (void)pickEmoji:(NSButton *)sender { self.emojiField.stringValue = sender.title; }

- (void)finishWith:(NSDictionary *)result {
    [self.sheet.sheetParent endSheet:self.sheet];
    if (self.completion) self.completion(result);
}
- (void)cancel:(id)sender { [self finishWith:nil]; }
- (void)create:(id)sender {
    NSString *name = [self.nameField.stringValue stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceCharacterSet]];
    if (name.length == 0) { NSBeep(); return; }
    AppDescriptor *picked = [AppDescriptor available].count
        ? [AppDescriptor available][self.appPopup.indexOfSelectedItem] : [AppDescriptor claude];
    [self finishWith:@{
        @"name": name,
        @"display": self.displayField.stringValue ?: @"",
        @"emoji": self.emojiField.stringValue.length ? self.emojiField.stringValue : @"👤",
        @"appID": picked.appID,
    }];
}
@end

#pragma mark - Main Window Controller

@interface MainWindowController : NSObject
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) ProfileStore *store;
@property (nonatomic, strong) DesktopManager *dm;
@property (nonatomic, strong) CodeManager *cm;
@property (nonatomic, strong) NSStackView *cards;     // vertical stack of profile rows
@property (nonatomic, strong) NSStackView *bannerRow; // update banner container
@property (nonatomic, strong) NSButton *autoSyncToggle;
@property (nonatomic, strong) NSArray<Profile *> *ordered; // matches button tags
@property (nonatomic, strong) NewProfileSheet *activeSheet;
@end

@implementation MainWindowController

- (instancetype)init {
    if ((self = [super init])) {
        self.store = [ProfileStore new];
        self.dm = [DesktopManager new];
        self.cm = [CodeManager new];
        [self buildWindow];
        [self reload];
    }
    return self;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 580, 620);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    w.title = @"Claude Profiles";
    w.minSize = NSMakeSize(480, 420);
    w.backgroundColor = CPBg();
    w.contentView = [CPBackgroundView new];   // subtle gradient backdrop
    w.titlebarAppearsTransparent = YES;   // let the cream extend into the title bar
    [w center];
    self.window = w;
    NSView *root = w.contentView;

    // Header
    NSTextField *h = [NSTextField labelWithString:@"Claude Profiles"];
    h.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    h.textColor = CPInk();
    NSButton *newBtn = CPPrimaryButton(@"+ New Profile", self, @selector(newProfile:));
    newBtn.keyEquivalent = @"n"; newBtn.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    NSButton *syncBtn = CPSecondaryButton(@"Sync", self, @selector(syncNow:));
    NSStackView *headerRight = [NSStackView stackViewWithViews:@[syncBtn, newBtn]];
    headerRight.spacing = 8;
    NSStackView *header = [NSStackView stackViewWithViews:@[h, [NSView new], headerRight]];
    header.distribution = NSStackViewDistributionFill;
    [h setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    // Update banner (hidden unless updates pending)
    self.bannerRow = [NSStackView stackViewWithViews:@[]];
    self.bannerRow.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.bannerRow.alignment = NSLayoutAttributeLeading;
    self.bannerRow.spacing = 6;

    // Cards in a scroll view
    self.cards = [NSStackView new];
    self.cards.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.cards.alignment = NSLayoutAttributeLeading;
    self.cards.spacing = 10;
    self.cards.translatesAutoresizingMaskIntoConstraints = NO;

    FlippedView *doc = [FlippedView new];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:self.cards];

    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = doc;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    // Standard macOS overlay scroller: a thin pill that appears on scroll and fades
    // out, rather than a permanent legacy track.
    scroll.scrollerStyle = NSScrollerStyleOverlay;
    scroll.autohidesScrollers = YES;
    scroll.verticalScrollElasticity = NSScrollElasticityAllowed;

    [NSLayoutConstraint activateConstraints:@[
        [doc.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [doc.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [doc.trailingAnchor constraintEqualToAnchor:scroll.contentView.trailingAnchor],
        [doc.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [self.cards.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [self.cards.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor],
        [self.cards.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor],
        [self.cards.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor],
    ]];

    // Footer: auto-sync toggle
    self.autoSyncToggle = [NSButton checkboxWithTitle:@"Auto-sync profiles when Claude updates (on login)"
                                               target:self action:@selector(toggleAutoSync:)];
    self.autoSyncToggle.state = [LaunchAgent isInstalled] ? NSControlStateValueOn : NSControlStateValueOff;

    NSStackView *outer = [NSStackView stackViewWithViews:@[header, self.bannerRow, scroll, self.autoSyncToggle]];
    outer.orientation = NSUserInterfaceLayoutOrientationVertical;
    outer.alignment = NSLayoutAttributeLeading;
    outer.spacing = 14;
    outer.translatesAutoresizingMaskIntoConstraints = NO;
    outer.edgeInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    [root addSubview:outer];

    [NSLayoutConstraint activateConstraints:@[
        [outer.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],
        [outer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [outer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [outer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20],
        [header.widthAnchor constraintEqualToAnchor:outer.widthAnchor],
        [self.bannerRow.widthAnchor constraintEqualToAnchor:outer.widthAnchor],
        [scroll.widthAnchor constraintEqualToAnchor:outer.widthAnchor],
    ]];
    // Let the scroll view absorb extra vertical space.
    [scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
}

#pragma mark Rendering

- (void)reload {
    [self.store reload];
    self.ordered = self.store.profiles;

    for (NSView *v in [self.cards.arrangedSubviews copy]) [self.cards removeArrangedSubview:v], [v removeFromSuperview];

    if (self.ordered.count == 0) {
        NSTextField *empty = [NSTextField labelWithString:
            @"No profiles yet.\nClick “+ New Profile” to create your first isolated Claude account."];
        empty.textColor = [NSColor secondaryLabelColor];
        empty.font = [NSFont systemFontOfSize:13];
        [self.cards addArrangedSubview:empty];
    } else {
        NSInteger i = 0;
        for (Profile *p in self.ordered) {
            NSView *card = [self buildCard:p index:i++];
            [self.cards addArrangedSubview:card];
            // Now that the card shares an ancestor with the stack, stretch it full-width.
            [card.widthAnchor constraintEqualToAnchor:self.cards.widthAnchor].active = YES;
        }
    }
    [self refreshBanner];
}

- (NSView *)buildCard:(Profile *)p index:(NSInteger)i {
    NSView *card = [NSView new];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 12;
    card.layer.backgroundColor = CPSurface().CGColor;
    card.layer.borderWidth = 1;
    card.layer.borderColor = CPBorder().CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *emoji = [NSTextField labelWithString:p.emoji ?: @"👤"];
    emoji.font = [NSFont systemFontOfSize:30];

    NSTextField *name = [NSTextField labelWithString:p.displayName];
    name.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    name.textColor = CPInk();

    BOOL desk = [p isDesktopInstalled], code = [p isCodeInitialized];
    NSString *sub = [NSString stringWithFormat:@"%@  ·  Desktop %@  ·  Code %@",
        [p app].displayName,
        desk ? @"ready" : @"not set up",
        code ? @"ready" : @"—"];
    NSTextField *subtitle = [NSTextField labelWithString:sub];
    subtitle.font = [NSFont systemFontOfSize:11];
    subtitle.textColor = CPInkSoft();

    NSStackView *text = [NSStackView stackViewWithViews:@[name, subtitle]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 3;

    NSButton *launch = CPPrimaryButton(@"Launch Desktop", self, @selector(launchDesktop:));
    launch.tag = i;
    NSButton *open = CPSecondaryButton(@"Open Code", self, @selector(openCode:));
    open.tag = i;
    NSButton *more = CPSecondaryButton(@"⋯", self, @selector(showRowMenu:));
    more.tag = i;
    [more.widthAnchor constraintEqualToConstant:34].active = YES;

    NSStackView *actions = [NSStackView stackViewWithViews:@[launch, open, more]];
    actions.spacing = 6;

    NSStackView *rowStack = [NSStackView stackViewWithViews:@[emoji, text, [NSView new], actions]];
    rowStack.spacing = 12;
    rowStack.alignment = NSLayoutAttributeCenterY;
    rowStack.translatesAutoresizingMaskIntoConstraints = NO;
    [text setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [card addSubview:rowStack];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:64],
        [rowStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [rowStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [rowStack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [rowStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
    ]];
    return card;
}

- (void)refreshBanner {
    for (NSView *v in [self.bannerRow.arrangedSubviews copy]) [self.bannerRow removeArrangedSubview:v], [v removeFromSuperview];
    for (AppDescriptor *app in [AppDescriptor available]) {
        NSArray *pending = [self.dm updateAvailableForApp:app];
        if (!pending) continue;
        NSString *msg = [NSString stringWithFormat:@"⚠️  %@ updated v%@ → v%@ — your profiles need a sync",
                         app.displayName, pending[0], pending[1]];
        NSTextField *l = [NSTextField labelWithString:msg];
        l.textColor = [NSColor systemOrangeColor];
        l.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        [self.bannerRow addArrangedSubview:l];
    }
}

#pragma mark Helpers

- (Profile *)profileForSender:(NSControl *)sender {
    NSInteger i = sender.tag;
    return (i >= 0 && i < (NSInteger)self.ordered.count) ? self.ordered[i] : nil;
}

// Run a potentially-slow block off the main thread; disable `button` meanwhile.
- (void)runBusy:(NSButton *)button title:(NSString *)busyTitle
          block:(NSError *(^)(void))block done:(void (^)(NSError *))done {
    // Works for both the custom CPButton (draws from .title) and plain NSButtons.
    NSString *orig = button.title;
    button.title = busyTitle;
    [button invalidateIntrinsicContentSize];
    button.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = block();
        dispatch_async(dispatch_get_main_queue(), ^{
            button.enabled = YES;
            button.title = orig;
            [button invalidateIntrinsicContentSize];
            if (done) done(err);
        });
    });
}

- (void)alert:(NSString *)title info:(NSString *)info style:(NSAlertStyle)style {
    NSAlert *a = [NSAlert new];
    a.messageText = title; a.informativeText = info ?: @""; a.alertStyle = style;
    [a beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark Actions

- (void)launchDesktop:(NSButton *)sender {
    Profile *p = [self profileForSender:sender]; if (!p) return;
    __weak typeof(self) ws = self;
    [self runBusy:sender title:([p isDesktopInstalled] ? @"Launching…" : @"Setting up…")
            block:^NSError *{
        NSError *e = nil; [self.dm launch:p error:&e]; return e;
    } done:^(NSError *err) {
        if (err) [ws alert:@"Could not launch" info:err.localizedDescription style:NSAlertStyleWarning];
        [ws reload];
    }];
}

- (void)openCode:(NSButton *)sender {
    Profile *p = [self profileForSender:sender]; if (!p) return;
    NSError *e = nil;
    if (![self.cm launch:p error:&e])
        [self alert:@"Could not open Claude Code" info:e.localizedDescription style:NSAlertStyleWarning];
    [self reload];
}

- (void)showRowMenu:(NSButton *)sender {
    Profile *p = [self profileForSender:sender]; if (!p) return;
    NSMenu *menu = [NSMenu new];
    NSMenuItem *(^item)(NSString *, SEL) = ^(NSString *t, SEL s) {
        NSMenuItem *m = [[NSMenuItem alloc] initWithTitle:t action:s keyEquivalent:@""];
        m.target = self; m.representedObject = p; return m;
    };
    [menu addItem:item([p isDesktopInstalled] ? @"Re-setup Desktop bundle" : @"Set up Desktop bundle",
                       @selector(resetup:))];
    [menu addItem:item(@"Reveal bundle in Finder", @selector(revealBundle:))];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *del = item(@"Delete profile…", @selector(deleteProfile:));
    [menu addItem:del];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height) inView:sender];
}

- (void)resetup:(NSMenuItem *)sender {
    Profile *p = sender.representedObject;
    NSAlert *a = [NSAlert new];
    a.messageText = [NSString stringWithFormat:@"Set up %@?", [p appDisplayName]];
    a.informativeText = @"Copies the app, isolates it, and re-signs it. Takes a few seconds.";
    [a addButtonWithTitle:@"Set Up"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *e = nil; [self.dm setup:p force:YES error:&e];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (e) [self alert:@"Setup failed" info:e.localizedDescription style:NSAlertStyleWarning];
                [self reload];
            });
        });
    }];
}

- (void)revealBundle:(NSMenuItem *)sender {
    Profile *p = sender.representedObject;
    if ([p isDesktopInstalled])
        [[NSWorkspace sharedWorkspace] selectFile:[p appBundlePath] inFileViewerRootedAtPath:@""];
    else
        [self alert:@"Not set up yet" info:@"Set up the Desktop bundle first." style:NSAlertStyleInformational];
}

- (void)deleteProfile:(NSMenuItem *)sender {
    Profile *p = sender.representedObject;
    NSAlert *a = [NSAlert new];
    a.messageText = [NSString stringWithFormat:@"Delete “%@”?", p.displayName];
    a.informativeText = @"Removes its isolated app bundle and all its profile data. This cannot be undone.";
    a.alertStyle = NSAlertStyleCritical;
    [a addButtonWithTitle:@"Delete"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn) return;
        [self.store delete:p.name keepData:NO];
        [self reload];
    }];
}

- (void)newProfile:(id)sender {
    if ([AppDescriptor available].count == 0) {
        [self alert:@"No supported app found"
               info:@"Install Claude Desktop (or Cursor/Windsurf) first.\nDownload Claude from https://claude.ai/download."
              style:NSAlertStyleWarning];
        return;
    }
    self.activeSheet = [NewProfileSheet new];
    __weak typeof(self) ws = self;
    [self.activeSheet presentForWindow:self.window completion:^(NSDictionary *result) {
        ws.activeSheet = nil;
        if (!result) return;
        NSError *e = nil;
        Profile *p = [ws.store create:result[@"name"]
                          displayName:([result[@"display"] length] ? result[@"display"] : nil)
                                emoji:result[@"emoji"] color:@"#0066CC"
                                appID:result[@"appID"] error:&e];
        if (!p) { [ws alert:@"Could not create profile" info:e.localizedDescription style:NSAlertStyleWarning]; return; }
        [ws reload];
    }];
}

- (void)syncNow:(NSButton *)sender {
    __weak typeof(self) ws = self;
    [self runBusy:sender title:@"Syncing…" block:^NSError *{
        for (AppDescriptor *app in [AppDescriptor available]) [self.dm syncAllInstalledForApp:app];
        return nil;
    } done:^(NSError *err) {
        [ws reload];
        [ws alert:@"Sync complete" info:@"All installed profiles are up to date." style:NSAlertStyleInformational];
    }];
}

- (void)toggleAutoSync:(NSButton *)sender {
    NSError *e = nil;
    if (sender.state == NSControlStateValueOn) [LaunchAgent install:&e];
    else [LaunchAgent remove:&e];
    if (e) {
        [self alert:@"Auto-sync change failed" info:e.localizedDescription style:NSAlertStyleWarning];
        sender.state = [LaunchAgent isInstalled] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

@end

#pragma mark - App Delegate

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) MainWindowController *controller;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.controller = [MainWindowController new];
    [self.controller.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
@end

#pragma mark - Bootstrap

static void buildMainMenu(void) {
    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    NSString *name = @"Claude Profiles";
    [appMenu addItemWithTitle:[@"About " stringByAppendingString:name] action:NULL keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:name]
                       action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:name]
                       action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSApp.mainMenu = mainMenu;
}

int RunGUIApp(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        buildMainMenu();
        [app run];
    }
    return 0;
}
