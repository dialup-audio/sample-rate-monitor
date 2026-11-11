#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>

// Preferred sample rate is stored as plain text (Hz, e.g. "96000") in this file.
// No file (or an unparseable one) means "no preference": nothing gets highlighted.
static NSString *PrefPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/dialup.audio/sample-rate-display"];
}

static double LoadPreferredRate(void) {
    NSString *s = [NSString stringWithContentsOfFile:PrefPath()
                                            encoding:NSUTF8StringEncoding
                                               error:nil];
    double hz = s.doubleValue;
    return hz > 0 ? hz : 0;
}

static void SavePreferredRate(double hz) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = PrefPath();

    if (hz <= 0) {
        [fm removeItemAtPath:path error:nil];
        return;
    }

    NSError *error = nil;
    [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent
  withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) { NSLog(@"couldn't create pref dir: %@", error); return; }

    NSString *text = [NSString stringWithFormat:@"%.0f\n", hz];
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"couldn't save preference: %@", error);
    }
}

static AudioObjectPropertyAddress Addr(AudioObjectPropertySelector sel) {
    return { sel, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) NSMenuItem *deviceItem;
@property (strong) NSMenu *rateMenu;
@property double preferredRate;
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

    // "Expected sample rate": the menubar item turns red when the device is running at anything else.
    // Populated per-device in rebuildRateMenu.
    self.rateMenu = [[NSMenu alloc] init];

    NSMenuItem *rateParent = [[NSMenuItem alloc] initWithTitle:@"Expected sample rate"
                                                        action:nil keyEquivalent:@""];
    rateParent.submenu = self.rateMenu;
    [menu addItem:rateParent];
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

- (void)rebuildRateMenu {
    [self.rateMenu removeAllItems];

    NSMutableArray<NSNumber *> *rates = [[self supportedRates] mutableCopy];

    // Keep a saved preference selectable even if this device doesn't list it,
    // so switching devices never silently drops the setting.
    if (self.preferredRate > 0 && ![rates containsObject:@(self.preferredRate)]) {
        [rates addObject:@(self.preferredRate)];
        [rates sortUsingSelector:@selector(compare:)];
    }

    NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"None"
                                                  action:@selector(selectRate:)
                                           keyEquivalent:@""];
    none.target = self;
    none.representedObject = @0;
    [self.rateMenu addItem:none];
    [self.rateMenu addItem:[NSMenuItem separatorItem]];

    for (NSNumber *hz in rates) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self formatRate:hz.doubleValue]
                                                      action:@selector(selectRate:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = hz;
        [self.rateMenu addItem:item];
    }

    [self updateRateMenuChecks];
}

- (void)updateRateMenuChecks {
    for (NSMenuItem *item in self.rateMenu.itemArray) {
        if (!item.representedObject) continue;
        item.state = ([item.representedObject doubleValue] == self.preferredRate)
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)selectRate:(NSMenuItem *)sender {
    self.preferredRate = [sender.representedObject doubleValue];
    SavePreferredRate(self.preferredRate);
    [self updateRateMenuChecks];
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

    [self rebuildRateMenu];
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
        return;
    }

    NSString *text = [self formatRate:rate];
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:text];

    if (self.preferredRate > 0 && fabs(rate - self.preferredRate) > 0.5) {
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
