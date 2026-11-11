#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) NSTimer *timer;
@end

@implementation AppDelegate


- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSLog(@"sample rate menu thing launched");
    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];

    self.statusItem.button.title = @"? kHz";

    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *quit = [[NSMenuItem alloc]
        initWithTitle:@"Quit"
               action:@selector(terminate:)
        keyEquivalent:@"q"];

    [menu addItem:quit];
    self.statusItem.menu = menu;

    self.timer = [NSTimer scheduledTimerWithTimeInterval:10
                                                  target:self
                                                selector:@selector(poll)
                                                userInfo:nil
                                                 repeats:YES];
    [self poll];

}

- (void) poll {
    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"de.rme-audio.TotalmixFX"];

    NSMutableAttributedString *title =
        [[NSMutableAttributedString alloc] initWithString:@"RME"];

    self.statusItem.button.attributedTitle = title;

    if (apps.count == 0) {
        NSLog(@"TotalMix not running / bundle id mismatch");
        return;
    }

    pid_t pid = apps.firstObject.processIdentifier;
    AXUIElementRef appElement = AXUIElementCreateApplication(pid);

    CFArrayRef windows = NULL;
    AXError err = AXUIElementCopyAttributeValue(appElement,
                                                kAXWindowsAttribute,
                                                (CFTypeRef *)&windows);

    if (err != kAXErrorSuccess || !windows) {
        NSLog(@"Could not get TotalMix windows: %d", err);
        CFRelease(appElement);
        return;
    }

    for (id windowObj in (__bridge NSArray *)windows) {
        AXUIElementRef window = (__bridge AXUIElementRef)windowObj;

        CFTypeRef titleValue = NULL;
        AXError titleErr = AXUIElementCopyAttributeValue(window,
                                                         kAXTitleAttribute,
                                                         &titleValue);

        if (titleErr == kAXErrorSuccess && titleValue) {
            NSString *title = (__bridge NSString *)titleValue;
            NSLog(@"TotalMix window title: %@", title);

            NSRegularExpression *regex =
                [NSRegularExpression regularExpressionWithPattern:@"-\\s*([0-9.]+)k\\s*$"
                                                          options:0
                                                            error:nil];

            NSTextCheckingResult *match =
                [regex firstMatchInString:title
                                  options:0
                                    range:NSMakeRange(0, title.length)];

            if (match && match.numberOfRanges >= 2) {
                NSString *sampleRate =
                    [title substringWithRange:[match rangeAtIndex:1]];

                NSLog(@"sampleRate: %@", sampleRate);  // "44.1k"
                NSString *text = [NSString stringWithFormat:@"%@ kHz", sampleRate];

                text = [text stringByReplacingOccurrencesOfString:@".0"
                                                                   withString:@""];

                NSMutableAttributedString *title =
                    [[NSMutableAttributedString alloc] initWithString:text];

                if (![sampleRate isEqualToString:@"96.0"]) {
                    [title addAttribute:NSBackgroundColorAttributeName
                                  value:NSColor.systemRedColor
                                  range:NSMakeRange(0, text.length)];
                }

                self.statusItem.button.attributedTitle = title;
            }


            CFRelease(titleValue);
        }
    }

    CFRelease(windows);
    CFRelease(appElement);
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
