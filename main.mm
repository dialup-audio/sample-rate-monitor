#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>

// The alert rate (Hz) lives in NSUserDefaults under this key; 0 / unset means "no alert".
//   defaults read audio.dialup.khzdisp alertRate
//   defaults delete audio.dialup.khzdisp
static NSString * const kAlertRateKey = @"alertRate";

static double LoadPreferredRate(void) {
    double hz = [[NSUserDefaults standardUserDefaults] doubleForKey:kAlertRateKey];
    return hz > 0 ? hz : 0;
}

static void SavePreferredRate(double hz) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (hz > 0) {
        [defaults setDouble:hz forKey:kAlertRateKey];
    } else {
        [defaults removeObjectForKey:kAlertRateKey];
    }
}

static NSString * const kRepo    = @"dialup-audio/sample-rate-display";
static NSString * const kSiteURL = @"https://dialup.audio";

static AudioObjectPropertyAddress Addr(AudioObjectPropertySelector sel) {
    return { sel, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) NSMenuItem *deviceItem;
@property (strong) NSMenu *setRateMenu;
@property (strong) NSMenu *alertMenu;
@property (strong) NSMenuItem *alertParent;
@property double preferredRate;
// While a rate change we initiated is in flight, the alert is suppressed so the
// menubar item doesn't flash red between "clicked" and "device actually switched".
@property BOOL switching;
@property double switchTarget;
@property double switchPrevPreferred;
@property NSUInteger switchGeneration;
@property AudioDeviceID device;
@property (copy) AudioObjectPropertyListenerBlock rateListener;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.preferredRate = LoadPreferredRate();

    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"? kHz";

    NSMenu *menu = [[NSMenu alloc] init];

    self.deviceItem = [[NSMenuItem alloc] initWithTitle:@"No output device"
                                                 action:nil keyEquivalent:@""];
    [menu addItem:self.deviceItem];
    [menu addItem:[NSMenuItem separatorItem]];

    // Both submenus are populated per-device in rebuildMenus.
    // "Sample rate": changes the device's rate.
    self.setRateMenu = [[NSMenu alloc] init];
    NSMenuItem *setParent = [[NSMenuItem alloc] initWithTitle:@"Set sample rate to…"
                                                       action:nil keyEquivalent:@""];
    setParent.submenu = self.setRateMenu;
    [menu addItem:setParent];

    // "Alert if not…": the menubar item turns red when the device is running at anything else.
    self.alertMenu = [[NSMenu alloc] init];
    self.alertParent = [[NSMenuItem alloc] initWithTitle:@"Alert if not…"
                                                  action:nil keyEquivalent:@""];
    self.alertParent.submenu = self.alertMenu;
    [menu addItem:self.alertParent];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *about = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"About %@", self.appName]
               action:@selector(showAbout:)
        keyEquivalent:@""];
    about.target = self;
    [menu addItem:about];

    NSMenuItem *check = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…"
                                                   action:@selector(checkForUpdates:)
                                            keyEquivalent:@""];
    check.target = self;
    [menu addItem:check];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    [menu addItem:quit];
    self.statusItem.menu = menu;

    // Fires when the default output device changes (switching interfaces, plugging in headphones, ...)
    AudioObjectPropertyAddress addr = Addr(kAudioHardwarePropertyDefaultOutputDevice);
    AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &addr,
                                        dispatch_get_main_queue(),
                                        ^(UInt32 n, const AudioObjectPropertyAddress *a) {
        [self attachToDefaultDevice];
    });

    [self attachToDefaultDevice];
}

- (NSString *)appName {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"DialUp kHzDisp";
}

- (NSString *)appVersion {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.0.0";
}

- (void)showAbout:(id)sender {
    NSString *text = @"Free tools by dialup.audio";
    NSMutableAttributedString *credits = [[NSMutableAttributedString alloc] initWithString:text];

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentCenter;
    [credits addAttributes:@{ NSParagraphStyleAttributeName: para,
                              NSFontAttributeName: [NSFont systemFontOfSize:11],
                              NSForegroundColorAttributeName: NSColor.labelColor }
                     range:NSMakeRange(0, text.length)];
    [credits addAttribute:NSLinkAttributeName
                    value:[NSURL URLWithString:kSiteURL]
                    range:[text rangeOfString:@"dialup.audio"]];

    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{ NSAboutPanelOptionCredits: credits }];
}

#pragma mark - Updates

- (void)alert:(NSString *)message info:(NSString *)info downloadURL:(NSString *)url {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = info;
    if (url) {
        [alert addButtonWithTitle:@"Download"];
        [alert addButtonWithTitle:@"Later"];
    }
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertFirstButtonReturn && url) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
    }
}

// Only runs when the user clicks "Check for Updates…": the app makes no other network
// requests of its own. Asks GitHub for the latest release and, if it's newer, offers to
// open the release page. The user downloads and installs it themselves.
- (void)checkForUpdates:(id)sender {
    NSURL *url = [NSURL URLWithString:
        [NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", kRepo]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 15;
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"dialup-audio-sample-rate-display" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        id json = (!error && data && status == 200)
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *tag = [json isKindOfClass:[NSDictionary class]] ? json[@"tag_name"] : nil;
        NSString *page = [json isKindOfClass:[NSDictionary class]] ? json[@"html_url"] : nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![tag isKindOfClass:[NSString class]]) {
                NSLog(@"update check failed (status %ld): %@", (long)status, error);
                [self alert:@"Couldn't check for updates"
                       info:@"Check your internet connection and try again."
                downloadURL:nil];
                return;
            }

            NSString *latest = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
            BOOL newer = [latest compare:[self appVersion] options:NSNumericSearch]
                         == NSOrderedDescending;

            if (!newer) {
                [self alert:@"You're up to date"
                       info:[NSString stringWithFormat:@"%@ %@ is the latest version.",
                             [self appName], [self appVersion]]
                downloadURL:nil];
                return;
            }

            // Only ever open a page on this project's own GitHub repo.
            NSString *repoPrefix = [NSString stringWithFormat:@"https://github.com/%@/", kRepo];
            NSString *target = ([page isKindOfClass:[NSString class]] && [page hasPrefix:repoPrefix])
                ? page : [repoPrefix stringByAppendingString:@"releases/latest"];

            [self alert:[NSString stringWithFormat:@"Version %@ is available", latest]
                   info:[NSString stringWithFormat:@"You have version %@.", [self appVersion]]
            downloadURL:target];
        });
    }];
    [task resume];
}

#pragma mark - Sample rate

- (NSString *)formatRate:(double)hz {
    return [NSString stringWithFormat:@"%g kHz", hz / 1000.0];
}

// Sample rates the current device claims to support. Devices report either discrete
// rates (min == max) or continuous ranges; for ranges, fall back to the standard rates inside them.
- (NSArray<NSNumber *> *)supportedRates {
    if (self.device == kAudioObjectUnknown) return @[];

    AudioObjectPropertyAddress addr = Addr(kAudioDevicePropertyAvailableNominalSampleRates);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(self.device, &addr, 0, NULL, &size) != noErr || size == 0) {
        return @[];
    }

    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(self.device, &addr, 0, NULL, &size, data.mutableBytes) != noErr) {
        return @[];
    }

    NSArray<NSNumber *> *standard = @[@8000, @11025, @16000, @22050, @32000, @44100, @48000,
                                      @88200, @96000, @176400, @192000, @352800, @384000];
    NSMutableSet<NSNumber *> *rates = [NSMutableSet set];
    const AudioValueRange *ranges = (const AudioValueRange *)data.bytes;
    UInt32 count = size / sizeof(AudioValueRange);

    for (UInt32 i = 0; i < count; i++) {
        if (ranges[i].mMinimum == ranges[i].mMaximum) {
            [rates addObject:@(ranges[i].mMinimum)];
        } else {
            for (NSNumber *hz in standard) {
                if (hz.doubleValue >= ranges[i].mMinimum && hz.doubleValue <= ranges[i].mMaximum) {
                    [rates addObject:hz];
                }
            }
        }
    }

    return [rates.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

- (void)rebuildMenus {
    [self.alertMenu removeAllItems];
    [self.setRateMenu removeAllItems];

    NSArray<NSNumber *> *supported = [self supportedRates];
    for (NSNumber *hz in supported) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self formatRate:hz.doubleValue]
                                                      action:@selector(setDeviceRate:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = hz;
        [self.setRateMenu addItem:item];
    }
    if (supported.count == 0) {
        [self.setRateMenu addItemWithTitle:@"No rates available" action:nil keyEquivalent:@""];
    }

    NSMutableArray<NSNumber *> *rates = [supported mutableCopy];

    // Keep a saved preference selectable even if this device doesn't list it,
    // so switching devices never silently drops the setting.
    if (self.preferredRate > 0 && ![rates containsObject:@(self.preferredRate)]) {
        [rates addObject:@(self.preferredRate)];
        [rates sortUsingSelector:@selector(compare:)];
    }

    NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"Off"
                                                  action:@selector(selectRate:)
                                           keyEquivalent:@""];
    none.target = self;
    none.representedObject = @0;
    [self.alertMenu addItem:none];
    [self.alertMenu addItem:[NSMenuItem separatorItem]];

    for (NSNumber *hz in rates) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self formatRate:hz.doubleValue]
                                                      action:@selector(selectRate:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = hz;
        [self.alertMenu addItem:item];
    }

    [self updateAlertMenuChecks];
}

- (void)updateAlertMenuChecks {
    // Parent title reads as a sentence: "Alert if not 96 kHz" / "Alert: Off"
    self.alertParent.title = self.preferredRate > 0
        ? [NSString stringWithFormat:@"Alert if not %@", [self formatRate:self.preferredRate]]
        : @"Alert: Off";

    for (NSMenuItem *item in self.alertMenu.itemArray) {
        if (!item.representedObject) continue;
        item.state = ([item.representedObject doubleValue] == self.preferredRate)
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

// Checkmark on the rate the device is actually running at.
- (void)updateSetRateMenuChecks:(Float64)currentRate {
    for (NSMenuItem *item in self.setRateMenu.itemArray) {
        if (!item.representedObject) continue;
        item.state = (fabs([item.representedObject doubleValue] - currentRate) < 0.5)
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

// Ends the suppression window. On failure, put the alert rate back how it was.
// Doesn't refresh; callers do that when they need to.
- (void)finishSwitchSuccess:(BOOL)success {
    if (!self.switching) return;
    self.switching = NO;
    self.switchGeneration++;

    if (!success && self.preferredRate != self.switchPrevPreferred) {
        self.preferredRate = self.switchPrevPreferred;
        SavePreferredRate(self.preferredRate);
        [self updateAlertMenuChecks];
    }
}

- (void)setDeviceRate:(NSMenuItem *)sender {
    Float64 hz = [sender.representedObject doubleValue];

    NSUInteger generation = ++self.switchGeneration;
    self.switching = YES;
    self.switchTarget = hz;
    self.switchPrevPreferred = self.preferredRate;

    // If an alert rate is set, keep it in step with the rate being chosen.
    if (self.preferredRate > 0) {
        self.preferredRate = hz;
        SavePreferredRate(hz);
        [self updateAlertMenuChecks];
    }

    AudioObjectPropertyAddress addr = Addr(kAudioDevicePropertyNominalSampleRate);
    Boolean settable = false;
    OSStatus err = AudioObjectIsPropertySettable(self.device, &addr, &settable);
    if (err == noErr && settable) {
        err = AudioObjectSetPropertyData(self.device, &addr, 0, NULL, sizeof(hz), &hz);
    } else if (err == noErr) {
        err = kAudioHardwareIllegalOperationError;
    }

    if (err != noErr) {
        NSLog(@"couldn't set sample rate to %.0f: %d", hz, (int)err);
        [self finishSwitchSuccess:NO];
        [self refresh];

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Couldn't switch to %@", [self formatRate:hz]];
        alert.informativeText = @"This device may be controlled by its driver, or in use by an app that needs its current rate.";
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
        return;
    }

    // Success is detected in refresh (the rate listener fires when the device lands on the
    // target). If that never happens, give up after a few seconds and revert.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.switching && self.switchGeneration == generation) {
            NSLog(@"timed out waiting for device to switch to %.0f", hz);
            [self finishSwitchSuccess:NO];
            [self refresh];
        }
    });

    [self refresh];
}

- (void)selectRate:(NSMenuItem *)sender {
    self.preferredRate = [sender.representedObject doubleValue];
    SavePreferredRate(self.preferredRate);
    [self updateAlertMenuChecks];
    [self refresh];
}

- (void)detachFromDevice {
    if (self.device != kAudioObjectUnknown && self.rateListener) {
        AudioObjectPropertyAddress addr = Addr(kAudioDevicePropertyNominalSampleRate);
        AudioObjectRemovePropertyListenerBlock(self.device, &addr,
                                               dispatch_get_main_queue(), self.rateListener);
    }
    self.rateListener = nil;
    self.device = kAudioObjectUnknown;
}

- (void)attachToDefaultDevice {
    [self detachFromDevice];

    AudioDeviceID dev = kAudioObjectUnknown;
    UInt32 size = sizeof(dev);
    AudioObjectPropertyAddress addr = Addr(kAudioHardwarePropertyDefaultOutputDevice);
    OSStatus err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &dev);

    if (err == noErr && dev != kAudioObjectUnknown) {
        self.device = dev;

        // Fires when the device's sample rate changes (DAW, Audio MIDI Setup, driver panel, ...)
        __weak AppDelegate *weakSelf = self;
        self.rateListener = ^(UInt32 n, const AudioObjectPropertyAddress *a) {
            [weakSelf refresh];
        };
        AudioObjectPropertyAddress rateAddr = Addr(kAudioDevicePropertyNominalSampleRate);
        AudioObjectAddPropertyListenerBlock(dev, &rateAddr,
                                            dispatch_get_main_queue(), self.rateListener);
    }

    [self rebuildMenus];
    [self refresh];
}

- (void)refresh {
    if (self.device == kAudioObjectUnknown) {
        self.statusItem.button.title = @"? kHz";
        self.deviceItem.title = @"No output device";
        return;
    }

    Float64 rate = 0;
    UInt32 size = sizeof(rate);
    AudioObjectPropertyAddress addr = Addr(kAudioDevicePropertyNominalSampleRate);
    OSStatus err = AudioObjectGetPropertyData(self.device, &addr, 0, NULL, &size, &rate);

    CFStringRef cfName = NULL;
    size = sizeof(cfName);
    AudioObjectPropertyAddress nameAddr = Addr(kAudioObjectPropertyName);
    if (AudioObjectGetPropertyData(self.device, &nameAddr, 0, NULL, &size, &cfName) == noErr && cfName) {
        self.deviceItem.title = (__bridge_transfer NSString *)cfName;
    }
    self.statusItem.button.toolTip = self.deviceItem.title;

    if (err != noErr || rate <= 0) {
        self.statusItem.button.title = @"? kHz";
        [self updateSetRateMenuChecks:0];
        return;
    }
    [self updateSetRateMenuChecks:rate];

    if (self.switching && fabs(rate - self.switchTarget) < 0.5) {
        [self finishSwitchSuccess:YES];
    }

    NSString *text = [self formatRate:rate];
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:text];

    if (!self.switching && self.preferredRate > 0 && fabs(rate - self.preferredRate) > 0.5) {
        [title addAttribute:NSBackgroundColorAttributeName
                      value:NSColor.systemRedColor
                      range:NSMakeRange(0, text.length)];
    }

    self.statusItem.button.attributedTitle = title;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];

        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }

    return 0;
}
