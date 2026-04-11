@import AppKit;
#import "AppDelegate.h"
#import "ControlWindowController.h"
#import "DisplayController.h"
#import "PresetManager.h"
#import "PresetWindowController.h"

// Custom view for embedding a labeled slider inside a menu item
@interface MenuSliderView : NSView
@property(nonatomic, strong) NSButton* minusButton;
@property(nonatomic, strong) NSSlider* slider;
@property(nonatomic, strong) NSButton* plusButton;
@property(nonatomic, strong) NSTextField* valueLabel;
@property(nonatomic, strong) NSProgressIndicator* spinner;
@property(nonatomic, copy) NSString* displayUUID;
@property(nonatomic, assign) UInt8 attrCode;
- (void)setLoading:(BOOL)loading;
- (void)stepBy:(int)delta;
@end

@implementation MenuSliderView

- (instancetype)initWithLabel:(NSString*)label width:(CGFloat)width {
  self = [super initWithFrame:NSMakeRect(0, 0, width, 28)];
  if (self != nullptr) {
    NSTextField* nameLabel = [NSTextField labelWithString:label];
    nameLabel.font = [NSFont systemFontOfSize:12];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _minusButton = [NSButton buttonWithTitle:@"−"
                                      target:self
                                      action:@selector(minusTapped:)];
    _minusButton.bezelStyle = NSBezelStyleInline;
    _minusButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _minusButton.translatesAutoresizingMaskIntoConstraints = NO;

    _slider = [NSSlider sliderWithValue:50
                               minValue:0
                               maxValue:100
                                 target:nil
                                 action:nil];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.continuous = YES;

    _plusButton = [NSButton buttonWithTitle:@"+"
                                     target:self
                                     action:@selector(plusTapped:)];
    _plusButton.bezelStyle = NSBezelStyleInline;
    _plusButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _plusButton.translatesAutoresizingMaskIntoConstraints = NO;

    _valueLabel = [NSTextField labelWithString:@"--"];
    _valueLabel.font =
        [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _valueLabel.alignment = NSTextAlignmentRight;
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.displayedWhenStopped = NO;

    [self addSubview:nameLabel];
    [self addSubview:_minusButton];
    [self addSubview:_slider];
    [self addSubview:_plusButton];
    [self addSubview:_valueLabel];
    [self addSubview:_spinner];

    [NSLayoutConstraint activateConstraints:@[
      [nameLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                              constant:20],
      [nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [nameLabel.widthAnchor constraintEqualToConstant:70],
      [_minusButton.leadingAnchor
          constraintEqualToAnchor:nameLabel.trailingAnchor
                         constant:2],
      [_minusButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_minusButton.widthAnchor constraintEqualToConstant:20],
      [_slider.leadingAnchor constraintEqualToAnchor:_minusButton.trailingAnchor
                                            constant:2],
      [_slider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_plusButton.leadingAnchor constraintEqualToAnchor:_slider.trailingAnchor
                                                constant:2],
      [_plusButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_plusButton.widthAnchor constraintEqualToConstant:20],
      [_valueLabel.leadingAnchor
          constraintEqualToAnchor:_plusButton.trailingAnchor
                         constant:2],
      [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                 constant:-14],
      [_valueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_valueLabel.widthAnchor constraintEqualToConstant:30],
      [_spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor
                                             constant:30],
      [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
  }
  return self;
}

- (void)stepBy:(int)delta {
  NSInteger val = _slider.integerValue + delta;
  val = MAX(0, MIN(100, val));
  _slider.integerValue = val;
  [_slider sendAction:_slider.action to:_slider.target];
}

- (void)minusTapped:(id)sender {
  (void)sender;
  [self stepBy:-1];
}

- (void)plusTapped:(id)sender {
  (void)sender;
  [self stepBy:1];
}

- (void)setLoading:(BOOL)loading {
  if (loading) {
    _slider.hidden = YES;
    _valueLabel.hidden = YES;
    _minusButton.hidden = YES;
    _plusButton.hidden = YES;
    [_spinner startAnimation:nil];
  } else {
    _slider.hidden = NO;
    _valueLabel.hidden = NO;
    _minusButton.hidden = NO;
    _plusButton.hidden = NO;
    [_spinner stopAnimation:nil];
  }
}

@end

@interface AppDelegate () <NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem* statusItem;
@property(nonatomic, strong) DisplayController* displayController;
@property(nonatomic, strong) PresetManager* presetManager;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, ControlWindowController*>* controlWindows;
@property(nonatomic, strong) PresetWindowController* presetWindowController;
@property(nonatomic, assign) int openWindowCount;
@property(nonatomic, strong) dispatch_queue_t ddcQueue;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, NSMutableDictionary<NSNumber*, NSNumber*>*>*
        cachedValues;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, NSTimer*>* debounceTimers;
@property(nonatomic, strong) NSMapTable<NSMenu*, NSString*>* displayMenuToUUID;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;

  _displayController = [[DisplayController alloc] init];
  _presetManager = [[PresetManager alloc] init];
  _controlWindows = [NSMutableDictionary dictionary];
  _openWindowCount = 0;
  _ddcQueue =
      dispatch_queue_create("com.m1ddc-tray.menu-ddc", DISPATCH_QUEUE_SERIAL);
  _cachedValues = [NSMutableDictionary dictionary];
  _debounceTimers = [NSMutableDictionary dictionary];
  _displayMenuToUUID = [NSMapTable weakToStrongObjectsMapTable];

  // Create status item
  _statusItem = [[NSStatusBar systemStatusBar]
      statusItemWithLength:NSVariableStatusItemLength];
  _statusItem.button.image =
      [NSImage imageWithSystemSymbolName:@"display"
                accessibilityDescription:@"Display Controls"];

  [self rebuildMenu];

  // Wake notification — rebuild display list after sleep
  [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserver:self
         selector:@selector(refreshDisplays:)
             name:NSWorkspaceDidWakeNotification
           object:nil];

  // Window close notification for Dock icon toggling
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(windowDidClose:)
             name:NSWindowWillCloseNotification
           object:nil];

  // Preset change notification
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(presetsDidChange:)
                                               name:@"PresetsDidChange"
                                             object:nil];

  // Display settings change notification (rename, input profile)
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(displaySettingsDidChange:)
             name:@"DisplaySettingsDidChange"
           object:nil];
}

#pragma mark - Menu Building

// Refresh display list and load capabilities for new displays, then rebuild the
// menu. Can be called from any thread — handles dispatch internally.
- (void)rebuildMenu {
  [_displayController refreshDisplayList];
  [self buildMenuItems];

  // Load capabilities for any newly detected displays in background,
  // then rebuild the menu once real input options are available.
  dispatch_async(_ddcQueue, ^{
    BOOL newData = [self->_displayController loadCapabilitiesIfNeeded];
    if (newData) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self buildMenuItems];
      });
    }
  });
}

// Pure menu construction from current cached state. Always runs on main thread.
- (void)buildMenuItems {
  NSMenu* menu = [[NSMenu alloc] init];
  [_displayMenuToUUID removeAllObjects];

  // Display items
  if (_displayController.displayCount == 0) {
    NSMenuItem* noDisplay =
        [[NSMenuItem alloc] initWithTitle:@"No Displays Found"
                                   action:nil
                            keyEquivalent:@""];
    noDisplay.enabled = NO;
    [menu addItem:noDisplay];
  } else {
    for (int i = 0; i < _displayController.displayCount; i++) {
      NSString* name = [_displayController displayLabelAtIndex:i];
      NSString* uuid = [_displayController displayUUIDAtIndex:i];
      CGFloat menuWidth = 280;

      NSMenuItem* displayItem = [[NSMenuItem alloc] initWithTitle:name
                                                           action:nil
                                                    keyEquivalent:@""];
      NSMenu* displayMenu = [[NSMenu alloc] init];

      // Brightness slider
      MenuSliderView* brightnessView =
          [[MenuSliderView alloc] initWithLabel:@"Brightness" width:menuWidth];
      brightnessView.displayUUID = uuid;
      brightnessView.attrCode = LUMINANCE;
      brightnessView.slider.target = self;
      brightnessView.slider.action = @selector(menuSliderChanged:);
      brightnessView.slider.tag = i;
      NSNumber* cachedBrightness = _cachedValues[uuid][@(LUMINANCE)];
      if (cachedBrightness != nil) {
        brightnessView.slider.integerValue = cachedBrightness.integerValue;
        brightnessView.valueLabel.stringValue = cachedBrightness.stringValue;
      } else {
        [brightnessView setLoading:YES];
      }
      NSMenuItem* brightnessItem = [[NSMenuItem alloc] init];
      brightnessItem.view = brightnessView;
      [displayMenu addItem:brightnessItem];

      // Volume slider
      MenuSliderView* volumeView =
          [[MenuSliderView alloc] initWithLabel:@"Volume" width:menuWidth];
      volumeView.displayUUID = uuid;
      volumeView.attrCode = VOLUME;
      volumeView.slider.target = self;
      volumeView.slider.action = @selector(menuSliderChanged:);
      volumeView.slider.tag = i;
      NSNumber* cachedVolume = _cachedValues[uuid][@(VOLUME)];
      if (cachedVolume != nullptr) {
        volumeView.slider.integerValue = cachedVolume.integerValue;
        volumeView.valueLabel.stringValue = cachedVolume.stringValue;
      } else {
        [volumeView setLoading:YES];
      }
      NSMenuItem* volumeItem = [[NSMenuItem alloc] init];
      volumeItem.view = volumeView;
      [displayMenu addItem:volumeItem];

      [displayMenu addItem:[NSMenuItem separatorItem]];

      // Input source submenu — options come from capabilities cache (or
      // fallback)
      UInt8 inputAttrCode = [_displayController inputAttributeCodeForIndex:i];
      NSMenuItem* inputItem = [[NSMenuItem alloc] initWithTitle:@"Input Source"
                                                         action:nil
                                                  keyEquivalent:@""];
      NSMenu* inputMenu = [[NSMenu alloc] init];
      for (NSDictionary* opt in
           [_displayController inputOptionsForDisplayIndex:i]) {
        NSMenuItem* optItem =
            [[NSMenuItem alloc] initWithTitle:opt[@"label"]
                                       action:@selector(switchInput:)
                                keyEquivalent:@""];
        optItem.tag = [opt[@"value"] integerValue];
        optItem.representedObject = uuid;
        optItem.target = self;
        [inputMenu addItem:optItem];
      }
      NSNumber* cachedInput = _cachedValues[uuid][@(inputAttrCode)];
      if (cachedInput != nullptr) {
        for (NSMenuItem* opt in inputMenu.itemArray) {
          if (opt.tag == cachedInput.integerValue) {
            opt.state = NSControlStateValueOn;
            break;
          }
        }
      }
      inputItem.submenu = inputMenu;
      [displayMenu addItem:inputItem];

      [displayMenu addItem:[NSMenuItem separatorItem]];

      // Settings...
      NSMenuItem* allControls =
          [[NSMenuItem alloc] initWithTitle:@"Settings..."
                                     action:@selector(openControlWindow:)
                              keyEquivalent:@""];
      allControls.tag = i;
      allControls.target = self;
      [displayMenu addItem:allControls];

      displayMenu.delegate = self;
      [_displayMenuToUUID setObject:uuid forKey:displayMenu];
      displayItem.submenu = displayMenu;
      [menu addItem:displayItem];
    }
  }

  [menu addItem:[NSMenuItem separatorItem]];

  // Presets submenu
  NSMenuItem* presetsItem = [[NSMenuItem alloc] initWithTitle:@"Presets"
                                                       action:nil
                                                keyEquivalent:@""];
  NSMenu* presetsMenu = [[NSMenu alloc] init];
  NSArray<Preset*>* presets = [_presetManager allPresets];

  if (presets.count == 0) {
    NSMenuItem* noPresets = [[NSMenuItem alloc] initWithTitle:@"No Presets"
                                                       action:nil
                                                keyEquivalent:@""];
    noPresets.enabled = NO;
    [presetsMenu addItem:noPresets];
  } else {
    for (Preset* preset in presets) {
      NSMenuItem* item =
          [[NSMenuItem alloc] initWithTitle:preset.name
                                     action:@selector(applyPreset:)
                              keyEquivalent:@""];
      item.representedObject = preset;
      item.target = self;
      [presetsMenu addItem:item];
    }
  }

  [presetsMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem* editPresets =
      [[NSMenuItem alloc] initWithTitle:@"Edit Presets..."
                                 action:@selector(openPresetWindow:)
                          keyEquivalent:@""];
  editPresets.target = self;
  [presetsMenu addItem:editPresets];

  presetsItem.submenu = presetsMenu;
  [menu addItem:presetsItem];

  [menu addItem:[NSMenuItem separatorItem]];

  // Refresh
  NSMenuItem* refresh =
      [[NSMenuItem alloc] initWithTitle:@"Refresh Displays"
                                 action:@selector(refreshDisplays:)
                          keyEquivalent:@"r"];
  refresh.target = self;
  [menu addItem:refresh];

  // Quit
  NSMenuItem* quit = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                action:@selector(quitApp:)
                                         keyEquivalent:@"q"];
  quit.target = self;
  [menu addItem:quit];

  _statusItem.menu = menu;
}

#pragma mark - Actions

- (void)openControlWindow:(NSMenuItem*)sender {
  int index = (int)sender.tag;
  NSString* uuid = [_displayController displayUUIDAtIndex:index];

  ControlWindowController* wc = _controlWindows[uuid];
  if (wc == nullptr) {
    wc = [[ControlWindowController alloc]
        initWithDisplayIndex:index
           displayController:_displayController];
    _controlWindows[uuid] = wc;
  }

  [wc showWindow:nil];
  _openWindowCount++;
  [self updateActivationPolicy];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)openPresetWindow:(id)sender {
  (void)sender;

  if (_presetWindowController == nullptr) {
    _presetWindowController = [[PresetWindowController alloc]
        initWithPresetManager:_presetManager
            displayController:_displayController];
  }

  [_presetWindowController showWindow:nil];
  _openWindowCount++;
  [self updateActivationPolicy];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)applyPreset:(NSMenuItem*)sender {
  Preset* preset = sender.representedObject;
  [_presetManager applyPreset:preset
        withDisplayController:_displayController
                   completion:^(BOOL success) {
                     if (!success) {
                       NSAlert* alert = [[NSAlert alloc] init];
                       alert.messageText = @"Preset Applied";
                       alert.informativeText =
                           @"Some actions could not be applied. The display "
                           @"may be disconnected or the attribute unsupported.";
                       alert.alertStyle = NSAlertStyleWarning;
                       [alert runModal];
                     }
                   }];
}

- (void)menuSliderChanged:(NSSlider*)sender {
  MenuSliderView* view = (MenuSliderView*)sender.superview;
  NSString* uuid = view.displayUUID;
  UInt8 attrCode = view.attrCode;
  UInt16 newValue = (UInt16)sender.integerValue;

  view.valueLabel.stringValue = [NSString stringWithFormat:@"%d", newValue];

  // Update cache
  if (_cachedValues[uuid] == nullptr)
    _cachedValues[uuid] = [NSMutableDictionary dictionary];
  _cachedValues[uuid][@(attrCode)] = @(newValue);

  // Debounce DDC write
  NSString* key = [NSString stringWithFormat:@"%@-%d", uuid, attrCode];
  [_debounceTimers[key] invalidate];
  int displayIndex = [_displayController displayIndexForUUID:uuid];
  if (displayIndex < 0)
    return;

  NSTimer* timer =
      [NSTimer timerWithTimeInterval:0.1
                             repeats:NO
                               block:^(NSTimer* t __unused) {
                                 dispatch_async(self->_ddcQueue, ^{
                                   [self->_displayController
                                        writeAttribute:attrCode
                                                 value:newValue
                                       forDisplayIndex:displayIndex];
                                 });
                               }];
  [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
  _debounceTimers[key] = timer;
}

- (void)switchInput:(NSMenuItem*)sender {
  NSString* uuid = sender.representedObject;
  UInt16 inputValue = (UInt16)sender.tag;
  int displayIndex = [_displayController displayIndexForUUID:uuid];
  if (displayIndex < 0)
    return;

  UInt8 inputAttr =
      [_displayController inputAttributeCodeForIndex:displayIndex];

  // Update cache
  if (_cachedValues[uuid] == nullptr)
    _cachedValues[uuid] = [NSMutableDictionary dictionary];
  _cachedValues[uuid][@(inputAttr)] = @(inputValue);

  dispatch_async(_ddcQueue, ^{
    [self->_displayController writeAttribute:inputAttr
                                       value:inputValue
                             forDisplayIndex:displayIndex];
  });
}

- (void)refreshDisplays:(id)sender {
  (void)sender;
  [self rebuildMenu];
}

#pragma mark - NSMenuDelegate

- (void)menuWillOpen:(NSMenu*)menu {
  NSString* uuid = [_displayMenuToUUID objectForKey:menu];
  if (uuid == nullptr)
    return;

  int displayIndex = [_displayController displayIndexForUUID:uuid];
  if (displayIndex < 0)
    return;

  // Read current values in background, then update menu items in-place
  UInt8 inputAttr =
      [_displayController inputAttributeCodeForIndex:displayIndex];

  dispatch_async(_ddcQueue, ^{
    DDCValue brightness = [self->_displayController readAttribute:LUMINANCE
                                                  forDisplayIndex:displayIndex];
    DDCValue volume = [self->_displayController readAttribute:VOLUME
                                              forDisplayIndex:displayIndex];
    DDCValue input = [self->_displayController readAttribute:inputAttr
                                             forDisplayIndex:displayIndex];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self->_cachedValues[uuid] == nullptr)
        self->_cachedValues[uuid] = [NSMutableDictionary dictionary];

      // Update sliders in the open menu
      for (NSMenuItem* item in menu.itemArray) {
        if (![item.view isKindOfClass:[MenuSliderView class]])
          continue;
        MenuSliderView* sv = (MenuSliderView*)item.view;

        if (sv.attrCode == LUMINANCE && brightness.curValue >= 0) {
          sv.slider.integerValue = brightness.curValue;
          sv.valueLabel.stringValue =
              [NSString stringWithFormat:@"%d", brightness.curValue];
          self->_cachedValues[uuid][@(LUMINANCE)] = @(brightness.curValue);
          [sv setLoading:NO];
        } else if (sv.attrCode == VOLUME && volume.curValue >= 0) {
          sv.slider.integerValue = volume.curValue;
          sv.valueLabel.stringValue =
              [NSString stringWithFormat:@"%d", volume.curValue];
          self->_cachedValues[uuid][@(VOLUME)] = @(volume.curValue);
          [sv setLoading:NO];
        }
      }

      // Update input source checkmark
      if (input.curValue >= 0) {
        self->_cachedValues[uuid][@(inputAttr)] = @(input.curValue);
        for (NSMenuItem* item in menu.itemArray) {
          if (item.submenu == nullptr)
            continue;
          for (NSMenuItem* opt in item.submenu.itemArray) {
            opt.state = (opt.tag == input.curValue) ? NSControlStateValueOn
                                                    : NSControlStateValueOff;
          }
        }
      }
    });
  });
}

- (void)quitApp:(id)sender {
  (void)sender;
  // Force quit — close all windows first so applicationShouldTerminate allows
  // it
  for (NSString* uuid in [_controlWindows allKeys]) {
    [_controlWindows[uuid].window close];
  }
  if (_presetWindowController != nullptr) {
    [_presetWindowController.window close];
  }
  _openWindowCount = 0;
  [NSApp terminate:nil];
}

#pragma mark - Window Tracking & Dock Icon

- (void)windowDidClose:(NSNotification*)notification {
  NSWindow* closedWindow = notification.object;

  // Remove closed control windows from our dictionary
  NSString* keyToRemove = nil;
  for (NSString* uuid in _controlWindows) {
    if (_controlWindows[uuid].window == closedWindow) {
      keyToRemove = uuid;
      break;
    }
  }
  if (keyToRemove != nullptr) {
    [_controlWindows removeObjectForKey:keyToRemove];
  }

  if (_presetWindowController.window == closedWindow) {
    _presetWindowController = nil;
  }

  _openWindowCount = (int)_controlWindows.count +
                     ((_presetWindowController != nullptr) ? 1 : 0);
  [self updateActivationPolicy];
}

- (void)updateActivationPolicy {
  if (_openWindowCount > 0) {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    // Ensure the dock icon uses our app icon
    NSImage* icon = [NSImage imageNamed:@"AppIcon"];
    if (icon != nullptr)
      [NSApp setApplicationIconImage:icon];
  } else {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
  }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return NO;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication*)sender {
  // If windows are open, close them instead of quitting
  // (so dock right-click "Quit" just closes windows, not the tray app)
  if (_openWindowCount > 0) {
    for (NSString* uuid in [_controlWindows allKeys]) {
      [_controlWindows[uuid].window close];
    }
    if (_presetWindowController != nullptr) {
      [_presetWindowController.window close];
    }
    return NSTerminateCancel;
  }
  return NSTerminateNow;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication*)sender
                    hasVisibleWindows:(BOOL)flag {
  (void)sender;
  (void)flag;
  return YES;
}

#pragma mark - Notifications

- (void)presetsDidChange:(NSNotification*)notification {
  (void)notification;
  [self buildMenuItems];
}

- (void)displaySettingsDidChange:(NSNotification*)notification {
  (void)notification;
  [_cachedValues removeAllObjects];
  [self buildMenuItems];
}

@end
